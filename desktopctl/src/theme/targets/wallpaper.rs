use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    expand_user_path, find_command, fnv1a_fingerprint,
    schema::{ColorScheme, ThemeState},
};
use std::{
    fs, io,
    path::{Path, PathBuf},
    process::Command,
    time::UNIX_EPOCH,
};

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "wallpaper",
    Assembly::Command,
    &["color_scheme", "wallpaper", "filter_wallpaper"],
)
.sync_safe(false);

// v2: cache key digest switched from SHA-256 to the shared FNV-1a fingerprint;
// v1 entries are simply never matched again and regenerate on demand.
const CACHE_VERSION: &str = "lutgen-apply-v2";

fn awww_command(path: &str) -> Vec<String> {
    vec![
        "awww".to_owned(),
        "img".to_owned(),
        path.to_owned(),
        "--transition-type".to_owned(),
        "fade".to_owned(),
        "--transition-duration".to_owned(),
        "1".to_owned(),
    ]
}

fn cache_root() -> crate::Result<PathBuf> {
    match std::env::var("XDG_CACHE_HOME") {
        Ok(base) => Ok(PathBuf::from(base).join("apply-theme").join("wallpaper")),
        Err(std::env::VarError::NotPresent) => expand_user_path("~/.cache/apply-theme/wallpaper"),
        Err(error) => Err(io::Error::new(io::ErrorKind::InvalidInput, error).into()),
    }
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
    let wallpaper = PathBuf::from(&state.wallpaper).expanduser()?;
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
    let source = PathBuf::from(&state.wallpaper).expanduser()?;
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

fn run_command(command: &[String]) -> (bool, String) {
    let output = Command::new(&command[0]).args(&command[1..]).output();
    match output {
        Ok(output) if output.status.success() => (true, String::new()),
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
            let message = if !stderr.is_empty() {
                stderr
            } else if !stdout.is_empty() {
                stdout
            } else {
                output.status.to_string()
            };
            (false, message)
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            (false, format!("{:?} not found", command[0]))
        }
        Err(error) => (false, error.to_string()),
    }
}

fn warn(message: &str) {
    eprintln!("  wallpaper warning: {message}");
}

fn apply_wallpaper(path: &Path) {
    let (ok, message) = run_command(&awww_command(&path.display().to_string()));
    if !ok {
        warn(&format!(
            "failed to apply wallpaper {}: {message}",
            path.display()
        ));
    }
}

fn fallback_to_source(source: &Path, reason: &str) {
    warn(&format!("{reason}; using original wallpaper"));
    apply_wallpaper(source);
}

pub fn generate(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let commands = if state.filter_wallpaper {
        Vec::new()
    } else {
        vec![awww_command(&state.wallpaper)]
    };
    Ok(GeneratedContent::commands(commands))
}

pub fn on_apply(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    if !state.filter_wallpaper {
        return Ok(());
    }

    let source = PathBuf::from(&state.wallpaper).expanduser()?;
    if !source.is_file() {
        warn(&format!(
            "source wallpaper does not exist: {}",
            source.display()
        ));
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

                let (ok, message) = run_command(&{
                    let mut command = vec![
                        "lutgen".to_owned(),
                        "apply".to_owned(),
                        "--cache".to_owned(),
                        "-o".to_owned(),
                        filtered.display().to_string(),
                        source.display().to_string(),
                        "--".to_owned(),
                    ];
                    command.extend(colors.palette.iter().cloned());
                    command
                });
                if !ok {
                    let _ = fs::remove_file(&filtered);
                    fallback_to_source(
                        &source,
                        &format!("could not generate filtered wallpaper with lutgen: {message}"),
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

trait ExpandUserPath {
    fn expanduser(self) -> crate::Result<PathBuf>;
}

impl ExpandUserPath for PathBuf {
    fn expanduser(self) -> crate::Result<PathBuf> {
        let text = self.to_string_lossy().to_string();
        expand_user_path(&text)
    }
}
