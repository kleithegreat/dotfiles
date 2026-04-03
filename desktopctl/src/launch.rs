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
