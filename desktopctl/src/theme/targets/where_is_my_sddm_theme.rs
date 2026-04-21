use super::{Assembly, GeneratedContent, TargetMetadata, wallpaper::selected_wallpaper_path};
use crate::theme::{
    atomic_write,
    schema::{ColorScheme, ThemeState},
};
use std::{env, fs, path::PathBuf};

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "where_is_my_sddm_theme",
    Assembly::Command,
    &["color_scheme", "wallpaper", "filter_wallpaper"],
)
.managed_paths(&["/tmp/desktopctl-where-is-my-sddm-theme/background"]);

const STAGED_BACKGROUND_PATH: &str = "/tmp/desktopctl-where-is-my-sddm-theme/background";
const STAGED_BACKGROUND_ENV: &str = "DESKTOPCTL_SDDM_THEME_STAGE_PATH";

pub fn generate(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::commands(Vec::new()))
}

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

    if let Err(error) = atomic_write(&staged_background_path(), &bytes) {
        warn(&format!("could not stage SDDM background: {error}"));
    }

    Ok(())
}

fn staged_background_path() -> PathBuf {
    env::var_os(STAGED_BACKGROUND_ENV)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(STAGED_BACKGROUND_PATH))
}

fn warn(message: &str) {
    eprintln!("  where_is_my_sddm_theme warning: {message}");
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        test_support::{ScopedEnvVar, TempDir, env_lock},
        theme::targets::testsupport::{dummy_colors, dummy_state},
    };
    use std::fs;

    #[test]
    fn generate_returns_no_commands() {
        let GeneratedContent::Commands(commands) =
            generate(&dummy_colors(), &dummy_state()).expect("generate succeeds")
        else {
            panic!("expected command output");
        };

        assert!(commands.is_empty());
    }

    #[test]
    fn persist_stages_current_wallpaper_bytes() {
        let _env_guard = env_lock();
        let temp_dir = TempDir::new("where-is-my-sddm-theme").expect("temp dir");
        let staged_path = temp_dir.path().join("background");
        let _staged_override = ScopedEnvVar::set(STAGED_BACKGROUND_ENV, &staged_path);

        let wallpaper_path = temp_dir.path().join("wallpaper.jpg");
        fs::write(&wallpaper_path, b"test-wallpaper").expect("wallpaper write succeeds");

        let mut state = dummy_state();
        state.wallpaper = wallpaper_path.display().to_string();

        persist(&dummy_colors(), &state).expect("persist succeeds");

        assert_eq!(
            fs::read(&staged_path).expect("staged wallpaper exists"),
            b"test-wallpaper"
        );
    }
}
