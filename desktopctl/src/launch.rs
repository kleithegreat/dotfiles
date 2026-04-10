use crate::paths;
use std::{
    env,
    fs::File,
    io::{self, BufRead, BufReader},
    os::unix::process::CommandExt,
    path::Path,
    process::Command,
};

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

pub fn run(print_env: bool) -> Result<()> {
    let cursor_conf = paths::xdg_config_home()?.join("hypr/cursor.conf");
    let overrides = parse_cursor_conf(&cursor_conf)?;
    let env_state = CursorEnv::resolve(overrides);

    if print_env {
        println!("{}", env_state.printable());
        return Ok(());
    }

    let quickshell_path = paths::repo_root()?.join("config/quickshell");
    let mut command = Command::new("quickshell");
    command.arg("-p").arg(quickshell_path);
    command.env_remove("HYPRCURSOR_THEME");

    if let Some(value) = env_state.xcursor_theme.as_deref() {
        command.env("XCURSOR_THEME", value);
    }
    if let Some(value) = env_state.xcursor_size.as_deref() {
        command.env("XCURSOR_SIZE", value);
    }
    if let Some(value) = env_state.hyprcursor_theme.as_deref() {
        command.env("HYPRCURSOR_THEME", value);
    }

    Err(command.exec().into())
}

#[derive(Debug, Default)]
struct CursorEnvOverrides {
    xcursor_theme: Option<String>,
    hyprcursor_theme: Option<String>,
    xcursor_size: Option<String>,
}

#[derive(Debug, Default)]
struct CursorEnv {
    xcursor_theme: Option<String>,
    hyprcursor_theme: Option<String>,
    xcursor_size: Option<String>,
}

impl CursorEnv {
    fn resolve(overrides: CursorEnvOverrides) -> Self {
        let mut env_state = Self {
            xcursor_theme: env::var("XCURSOR_THEME").ok(),
            hyprcursor_theme: None,
            xcursor_size: env::var("XCURSOR_SIZE").ok(),
        };

        if let Some(value) = overrides.xcursor_theme {
            env_state.xcursor_theme = Some(value);
        }
        if let Some(value) = overrides.hyprcursor_theme {
            env_state.hyprcursor_theme = Some(value);
        }
        if let Some(value) = overrides.xcursor_size {
            env_state.xcursor_size = Some(value);
        }

        env_state
    }

    fn printable(&self) -> String {
        format!(
            "{}|{}|{}",
            self.xcursor_theme.as_deref().unwrap_or(""),
            self.hyprcursor_theme.as_deref().unwrap_or(""),
            self.xcursor_size.as_deref().unwrap_or("")
        )
    }
}

fn parse_cursor_conf(path: &Path) -> io::Result<CursorEnvOverrides> {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(CursorEnvOverrides::default());
        }
        Err(error) => return Err(error),
    };

    let mut overrides = CursorEnvOverrides::default();
    for line in BufReader::new(file).lines() {
        let line = line?;
        if let Some(value) = line.strip_prefix("env = XCURSOR_THEME,") {
            overrides.xcursor_theme = Some(value.to_owned());
        } else if let Some(value) = line.strip_prefix("env = XCURSOR_SIZE,") {
            overrides.xcursor_size = Some(value.to_owned());
        } else if let Some(value) = line.strip_prefix("env = HYPRCURSOR_THEME,") {
            overrides.hyprcursor_theme = Some(value.to_owned());
        }
    }

    Ok(overrides)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{ScopedEnvVar, TempDir, env_lock};
    use std::fs;

    #[test]
    fn parse_cursor_conf_reads_supported_env_overrides() {
        let temp_dir = TempDir::new("desktopctl-cursor-conf").expect("temp dir");
        let path = temp_dir.path().join("cursor.conf");
        fs::write(
            &path,
            concat!(
                "env = XCURSOR_THEME,Bibata-Modern-Ice\n",
                "env = XCURSOR_SIZE,24\n",
                "env = HYPRCURSOR_THEME,Bibata-Hypr\n",
                "env = OTHER_VAR,ignored\n",
            ),
        )
        .expect("write cursor.conf");

        let overrides = parse_cursor_conf(&path).expect("cursor.conf should parse");

        assert_eq!(
            overrides.xcursor_theme.as_deref(),
            Some("Bibata-Modern-Ice")
        );
        assert_eq!(overrides.xcursor_size.as_deref(), Some("24"));
        assert_eq!(overrides.hyprcursor_theme.as_deref(), Some("Bibata-Hypr"));
    }

    #[test]
    fn parse_cursor_conf_returns_empty_overrides_when_missing() {
        let temp_dir = TempDir::new("desktopctl-cursor-missing").expect("temp dir");
        let path = temp_dir.path().join("missing.conf");

        let overrides = parse_cursor_conf(&path).expect("missing file should be ignored");

        assert!(overrides.xcursor_theme.is_none());
        assert!(overrides.hyprcursor_theme.is_none());
        assert!(overrides.xcursor_size.is_none());
    }

    #[test]
    fn cursor_env_resolve_prefers_file_overrides_over_process_env() {
        let _lock = env_lock();
        let _xcursor_theme = ScopedEnvVar::set("XCURSOR_THEME", "EnvTheme");
        let _xcursor_size = ScopedEnvVar::set("XCURSOR_SIZE", "32");
        let _hyprcursor_theme = ScopedEnvVar::set("HYPRCURSOR_THEME", "IgnoredEnvTheme");

        let resolved = CursorEnv::resolve(CursorEnvOverrides {
            xcursor_theme: Some("FileTheme".to_owned()),
            hyprcursor_theme: Some("FileHyprTheme".to_owned()),
            xcursor_size: None,
        });

        assert_eq!(resolved.xcursor_theme.as_deref(), Some("FileTheme"));
        assert_eq!(resolved.hyprcursor_theme.as_deref(), Some("FileHyprTheme"));
        assert_eq!(resolved.xcursor_size.as_deref(), Some("32"));
        assert_eq!(resolved.printable(), "FileTheme|FileHyprTheme|32");
    }
}
