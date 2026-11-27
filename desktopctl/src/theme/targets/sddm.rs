use super::{Target, wallpaper::selected_wallpaper_path};
use crate::{
    fs_util::atomic_write,
    theme::{
        color,
        schema::{ColorScheme, ThemeState},
    },
};
use std::{fs, io, path::Path, time::UNIX_EPOCH};

pub const TARGET: Target = Target::hooks(
    "sddm",
    &[
        "color_scheme",
        "wallpaper",
        "filter_wallpaper",
        "system_font",
        "mono_font",
        "font_size",
    ],
)
.persist(persist);

const STAGED_BACKGROUND_PATH: &str = "/tmp/desktopctl-sddm/background";
const STAGED_CONFIG_PATH: &str = "/tmp/desktopctl-sddm/theme.conf";
const INSTALLED_BACKGROUND_PATH: &str = "/var/lib/desktopctl/sddm/background";
const INSTALLED_CONFIG_PATH: &str = "/var/lib/desktopctl/sddm/theme.conf";

pub fn render_theme_conf(colors: &ColorScheme, state: &ThemeState, wallpaper: &str) -> String {
    let on_accent = color::readable_on_ends(&colors.accent, &colors.bg, &colors.fg);
    let font_size = state.font_size.max(1);
    format!(
        "[General]\n\
         background={INSTALLED_BACKGROUND_PATH}\n\
         wallpaper={wallpaper}\n\
         bg={bg}\n\
         bg1={bg1}\n\
         bg2={bg2}\n\
         fg={fg}\n\
         fg2={fg2}\n\
         fg3={fg3}\n\
         accent={accent}\n\
         onAccent={on_accent}\n\
         red={red}\n\
         yellow={yellow}\n\
         systemFont={system_font}\n\
         monoFont={mono_font}\n\
         fontSize={font_size}\n",
        bg = colors.bg,
        bg1 = colors.bg1,
        bg2 = colors.bg2,
        fg = colors.fg,
        fg2 = colors.fg2,
        fg3 = colors.fg3,
        accent = colors.accent,
        red = colors.red_bright,
        yellow = colors.yellow_bright,
        system_font = state.system_font,
        mono_font = state.mono_font,
    )
}

/// Names the wallpaper in `theme.conf`, so an installed config equal to the
/// rendered one means SDDM already has both and nothing is staged.
fn wallpaper_identity(source: &Path) -> io::Result<String> {
    let meta = source.metadata()?;
    let modified = meta
        .modified()?
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_nanos();
    Ok(format!("{} {} {modified}", source.display(), meta.len()))
}

pub fn persist(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let source = selected_wallpaper_path(colors, state)?;
    let identity = wallpaper_identity(&source);
    let conf = render_theme_conf(colors, state, identity.as_deref().unwrap_or_default());
    if fs::read(INSTALLED_CONFIG_PATH).is_ok_and(|installed| installed == conf.as_bytes()) {
        return Ok(());
    }

    match identity {
        Ok(_) => {
            let staged: crate::Result<()> = fs::read(&source)
                .map_err(Into::into)
                .and_then(|bytes| atomic_write(Path::new(STAGED_BACKGROUND_PATH), &bytes));
            if let Err(error) = staged {
                warn(&format!(
                    "could not stage SDDM background from {}: {error}",
                    source.display()
                ));
                return Ok(());
            }
        }
        Err(error) => warn(&format!("wallpaper {}: {error}", source.display())),
    }

    // Written last so the path unit copies the updated wallpaper and config together.
    if let Err(error) = atomic_write(Path::new(STAGED_CONFIG_PATH), conf.as_bytes()) {
        warn(&format!("could not stage SDDM config: {error}"));
    }

    Ok(())
}

fn warn(message: &str) {
    eprintln!("  sddm warning: {message}");
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::targets::testsupport::{
        dummy_colors, dummy_state, load_repo_colors, repo_schemes,
    };

    #[test]
    fn render_theme_conf_emits_general_section_and_fonts() {
        let colors = dummy_colors();
        let state = dummy_state();
        let rendered = render_theme_conf(&colors, &state, "");
        assert!(rendered.starts_with("[General]\n"));
        assert!(rendered.contains(&format!("background={INSTALLED_BACKGROUND_PATH}\n")));
        assert!(rendered.contains(&format!("bg={}\n", colors.bg)));
        assert!(rendered.contains(&format!("accent={}\n", colors.accent)));
        assert!(rendered.contains(&format!("systemFont={}\n", state.system_font)));
        assert!(rendered.contains(&format!("monoFont={}\n", state.mono_font)));
        assert!(rendered.contains(&format!("fontSize={}\n", state.font_size)));
    }

    #[test]
    fn on_accent_maintains_aa_contrast_across_all_repo_schemes() {
        let state = dummy_state();
        for name in repo_schemes() {
            let colors = load_repo_colors(&name);
            let rendered = render_theme_conf(&colors, &state, "");
            let on_accent = rendered
                .lines()
                .find_map(|line| line.strip_prefix("onAccent="))
                .expect("onAccent line");
            assert_eq!(
                on_accent,
                color::readable_on_ends(&colors.accent, &colors.bg, &colors.fg)
            );
            assert!(
                color::contrast_ratio(on_accent, &colors.accent) >= 4.5,
                "{name}: onAccent {on_accent} contrast against accent {} < 4.5",
                colors.accent
            );
        }
    }
}
