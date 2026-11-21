use super::{Target, wallpaper::selected_wallpaper_path};
use crate::{
    fs_util::atomic_write,
    theme::schema::{ColorScheme, ThemeState},
};
use std::{fs, path::Path};

pub const TARGET: Target = Target::hooks(
    "where_is_my_sddm_theme",
    &["color_scheme", "wallpaper", "filter_wallpaper"],
)
.persist(persist);

const STAGED_BACKGROUND_PATH: &str = "/tmp/desktopctl-where-is-my-sddm-theme/background";

pub fn persist(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let source = match selected_wallpaper_path(colors, state) {
        Ok(path) => path,
        Err(error) => {
            warn(&format!("could not resolve current wallpaper: {error}"));
            return Ok(());
        }
    };

    if !source.is_file() {
        warn(&format!(
            "source wallpaper does not exist: {}",
            source.display()
        ));
        return Ok(());
    }

    let bytes = match fs::read(&source) {
        Ok(bytes) => bytes,
        Err(error) => {
            warn(&format!(
                "could not read staged wallpaper source {}: {error}",
                source.display()
            ));
            return Ok(());
        }
    };

    if let Err(error) = atomic_write(Path::new(STAGED_BACKGROUND_PATH), &bytes) {
        warn(&format!("could not stage SDDM background: {error}"));
    }

    Ok(())
}

fn warn(message: &str) {
    eprintln!("  where_is_my_sddm_theme warning: {message}");
}
