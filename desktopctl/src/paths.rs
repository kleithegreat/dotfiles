use std::{
    env, fs, io,
    path::{Path, PathBuf},
};

/// Return the versioned theming data directory: color schemes, concat bases
/// and the state seed.
///
/// The package wraps the binary with `DESKTOPCTL_DATA` pointing at its own
/// store copy, so a deployed desktop never depends on the working tree — a
/// `git checkout` in the dotfiles repo must not change what a running session
/// renders. The checkout fallback is the authoring path: it is what makes a
/// new scheme visible to `theme set color_scheme` before a rebuild.
pub(crate) fn data_dir() -> io::Result<PathBuf> {
    if let Some(path) = env_path("DESKTOPCTL_DATA") {
        return Ok(path);
    }

    Ok(repo_root()?.join(Path::new("styling")))
}

/// Return a path rooted at the theming data directory.
pub(crate) fn data_path(relative: impl AsRef<Path>) -> io::Result<PathBuf> {
    Ok(data_dir()?.join(relative))
}

/// Return the repo root from the environment or the default dotfiles checkout.
///
/// Only wallpapers resolve through this: they are gitignored user assets that
/// live in the checkout, not versioned data the closure can pin. Everything
/// else goes through [`data_dir`].
pub(crate) fn repo_root() -> io::Result<PathBuf> {
    if let Some(path) = env_path("DESKTOPCTL_REPO") {
        return Ok(path);
    }

    Ok(home_dir()?.join(Path::new("repos/dotfiles")))
}

/// Return a path rooted at the dotfiles checkout.
pub(crate) fn repo_path(relative: impl AsRef<Path>) -> io::Result<PathBuf> {
    Ok(repo_root()?.join(relative))
}

/// Return the user's home directory.
pub(crate) fn home_dir() -> io::Result<PathBuf> {
    env_path("HOME").ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HOME is not set"))
}

/// Return the XDG config home directory.
pub(crate) fn xdg_config_home() -> io::Result<PathBuf> {
    if let Some(path) = env_path("XDG_CONFIG_HOME") {
        return Ok(path);
    }

    Ok(home_dir()?.join(Path::new(".config")))
}

/// Return the XDG data home directory.
pub(crate) fn xdg_data_home() -> io::Result<PathBuf> {
    if let Some(path) = env_path("XDG_DATA_HOME") {
        return Ok(path);
    }

    Ok(home_dir()?.join(Path::new(".local/share")))
}

/// Return the shared desktopctl database path, creating its parent directory.
pub(crate) fn db_path() -> io::Result<PathBuf> {
    let data_dir = xdg_data_home()?.join("desktopctl");
    fs::create_dir_all(&data_dir)?;
    Ok(data_dir.join("desktopctl.db"))
}

/// Return the XDG cache home directory.
pub(crate) fn xdg_cache_home() -> io::Result<PathBuf> {
    if let Some(path) = env_path("XDG_CACHE_HOME") {
        return Ok(path);
    }

    Ok(home_dir()?.join(Path::new(".cache")))
}

/// Return the XDG runtime directory.
pub(crate) fn xdg_runtime_dir() -> io::Result<PathBuf> {
    if let Some(path) = env_path("XDG_RUNTIME_DIR") {
        return Ok(path);
    }

    Ok(PathBuf::from(format!("/run/user/{}", current_euid())))
}

fn env_path(name: &str) -> Option<PathBuf> {
    let value = env::var_os(name)?;
    if value.is_empty() {
        return None;
    }

    Some(PathBuf::from(value))
}

fn current_euid() -> u32 {
    unsafe { libc::geteuid() }
}
