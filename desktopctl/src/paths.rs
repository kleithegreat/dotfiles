#![allow(dead_code)]

use std::{
    env,
    io,
    path::{Path, PathBuf},
};

/// Return the repo root from the environment or the default dotfiles checkout.
pub fn repo_root() -> io::Result<PathBuf> {
    if let Some(path) = env_path("DESKTOPCTL_REPO").or_else(|| env_path("desktopctl_REPO")) {
        return Ok(path);
    }

    Ok(home_dir()?.join(Path::new("repos/dotfiles")))
}

/// Return the user's home directory.
pub fn home_dir() -> io::Result<PathBuf> {
    env_path("HOME")
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HOME is not set"))
}

/// Return the XDG config home directory.
pub fn xdg_config_home() -> io::Result<PathBuf> {
    if let Some(path) = env_path("XDG_CONFIG_HOME") {
        return Ok(path);
    }

    Ok(home_dir()?.join(Path::new(".config")))
}

/// Return the XDG data home directory.
pub fn xdg_data_home() -> io::Result<PathBuf> {
    if let Some(path) = env_path("XDG_DATA_HOME") {
        return Ok(path);
    }

    Ok(home_dir()?.join(Path::new(".local/share")))
}

/// Return the XDG cache home directory.
pub fn xdg_cache_home() -> io::Result<PathBuf> {
    if let Some(path) = env_path("XDG_CACHE_HOME") {
        return Ok(path);
    }

    Ok(home_dir()?.join(Path::new(".cache")))
}

/// Return the XDG runtime directory.
pub fn xdg_runtime_dir() -> io::Result<PathBuf> {
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
    unsafe { geteuid() }
}

unsafe extern "C" {
    fn geteuid() -> u32;
}
