use super::Target;
use crate::{
    paths,
    theme::{
        command::{self, find_command},
        expand_user_path, fnv1a_fingerprint,
        schema::{ColorScheme, ThemeState},
    },
};
use std::{
    fs, io,
    path::{Path, PathBuf},
    thread,
    time::{Duration, Instant, UNIX_EPOCH},
};

pub const TARGET: Target = Target::hooks(
    "wallpaper",
    &["color_scheme", "wallpaper", "filter_wallpaper"],
)
.sync_safe(false)
.on_apply(on_apply);

const CACHE_VERSION: &str = "lutgen-apply-v2";

fn awww_command(path: &str) -> Vec<String> {
    vec![
        "awww".to_owned(),
        "img".to_owned(),
        path.to_owned(),
        "--transition-type".to_owned(),
        "fade".to_owned(),
        "--transition-duration".to_owned(),
        "0.3".to_owned(),
    ]
}

fn cache_root() -> crate::Result<PathBuf> {
    Ok(paths::xdg_cache_home()?.join("apply-theme/wallpaper"))
}

fn cache_key(colors: &ColorScheme, wallpaper: &Path) -> crate::Result<String> {
    let stat = wallpaper.metadata()?;
    let resolved = wallpaper.canonicalize()?;
    let modified_ns = stat
        .modified()?
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_nanos()
        .to_string();

    let mut input = String::new();
    input.push_str(CACHE_VERSION);
    input.push_str(&resolved.to_string_lossy());
    input.push_str(&stat.len().to_string());
    input.push_str(&modified_ns);
    for color in &colors.palette {
        input.push_str(&color.to_ascii_lowercase());
    }
    Ok(fnv1a_fingerprint(&input))
}

pub(crate) fn filtered_wallpaper_path(
    colors: &ColorScheme,
    state: &ThemeState,
) -> crate::Result<PathBuf> {
    let wallpaper = expand_user_path(&state.wallpaper)?;
    let stem = sanitize_stem(
        wallpaper
            .file_stem()
            .and_then(|stem| stem.to_str())
            .unwrap_or_default(),
    );
    let scheme = sanitize_component(&state.color_scheme);
    Ok(cache_root()?.join(format!(
        "{stem}-{scheme}-{}.png",
        cache_key(colors, &wallpaper)?
    )))
}

pub(crate) fn selected_wallpaper_path(
    colors: &ColorScheme,
    state: &ThemeState,
) -> crate::Result<PathBuf> {
    let source = expand_user_path(&state.wallpaper)?;
    if !state.filter_wallpaper {
        return Ok(source);
    }

    match filtered_wallpaper_path(colors, state) {
        Ok(filtered) if filtered.is_file() => Ok(filtered),
        _ => Ok(source),
    }
}

fn sanitize_component(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_') {
                character
            } else {
                '-'
            }
        })
        .collect()
}

fn sanitize_stem(value: &str) -> String {
    let sanitized = sanitize_component(value);
    let trimmed = sanitized.trim_matches(['-', '_']);
    if trimmed.is_empty() {
        "wallpaper".to_owned()
    } else {
        trimmed.to_owned()
    }
}

fn warn(message: &str) {
    eprintln!("  wallpaper warning: {message}");
}

/// awww accepts connections before it has registered an output, and `img` fails with "none of the
/// requested outputs are valid" until it has; `awww query` prints one line per registered output.
fn wait_for_awww_output() {
    const TIMEOUT: Duration = Duration::from_secs(5);
    const POLL_INTERVAL: Duration = Duration::from_millis(50);

    if find_command("awww").is_none() {
        return;
    }

    let deadline = Instant::now() + TIMEOUT;
    while Instant::now() < deadline {
        if command::output(&["awww", "query"]).is_ok_and(|outputs| !outputs.trim().is_empty()) {
            return;
        }
        thread::sleep(POLL_INTERVAL);
    }
}

fn apply_wallpaper(path: &Path) {
    wait_for_awww_output();
    if let Err(error) = command::run(&awww_command(&path.display().to_string())) {
        warn(&format!(
            "failed to apply wallpaper {}: {error}",
            path.display()
        ));
    }
}

fn fallback_to_source(source: &Path, reason: &str) {
    warn(&format!("{reason}; using original wallpaper"));
    apply_wallpaper(source);
}

pub fn on_apply(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let source = expand_user_path(&state.wallpaper)?;
    if !source.is_file() {
        warn(&format!(
            "source wallpaper does not exist: {}",
            source.display()
        ));
        return Ok(());
    }

    if !state.filter_wallpaper {
        apply_wallpaper(&source);
        return Ok(());
    }

    match filtered_wallpaper_path(colors, state) {
        Ok(filtered) => {
            if !filtered.is_file() {
                if find_command("lutgen").is_none() {
                    fallback_to_source(
                        &source,
                        "filter_wallpaper is enabled but 'lutgen' is not installed",
                    );
                    return Ok(());
                }

                if let Err(error) =
                    fs::create_dir_all(filtered.parent().expect("filtered wallpaper parent"))
                {
                    fallback_to_source(
                        &source,
                        &format!(
                            "could not create wallpaper filter cache at {}: {error}",
                            filtered
                                .parent()
                                .expect("filtered wallpaper parent")
                                .display()
                        ),
                    );
                    return Ok(());
                }

                let mut lutgen = vec![
                    "lutgen".to_owned(),
                    "apply".to_owned(),
                    "--cache".to_owned(),
                    "-o".to_owned(),
                    filtered.display().to_string(),
                    source.display().to_string(),
                    "--".to_owned(),
                ];
                lutgen.extend(colors.palette.iter().cloned());
                if let Err(error) = command::run(&lutgen) {
                    let _ = fs::remove_file(&filtered);
                    fallback_to_source(
                        &source,
                        &format!("could not generate filtered wallpaper with lutgen: {error}"),
                    );
                    return Ok(());
                }
            }
            apply_wallpaper(&filtered);
        }
        Err(error) => fallback_to_source(
            &source,
            &format!("unexpected error while preparing filtered wallpaper: {error}"),
        ),
    }

    Ok(())
}
