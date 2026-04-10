use std::{
    env, fs, io,
    path::{Path, PathBuf},
};

/// Return the repo root from the environment or the default dotfiles checkout.
pub(crate) fn repo_root() -> io::Result<PathBuf> {
    if let Some(path) = env_path("DESKTOPCTL_REPO").or_else(|| env_path("desktopctl_REPO")) {
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
    unsafe { geteuid() }
}

unsafe extern "C" {
    fn geteuid() -> u32;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{ScopedEnvVar, TempDir, env_lock};

    #[test]
    fn repo_root_prefers_uppercase_env_then_legacy_then_home_fallback() {
        let _lock = env_lock();
        let temp_dir = TempDir::new("desktopctl-paths-home").expect("temp dir");
        let _clear_upper = ScopedEnvVar::unset("DESKTOPCTL_REPO");
        let _clear_legacy = ScopedEnvVar::unset("desktopctl_REPO");
        let _home = ScopedEnvVar::set("HOME", temp_dir.path().as_os_str());
        assert_eq!(
            repo_root().expect("fallback repo root"),
            temp_dir.path().join("repos/dotfiles")
        );

        {
            let _legacy = ScopedEnvVar::set("desktopctl_REPO", "/legacy/repo");
            assert_eq!(
                repo_root().expect("legacy repo root"),
                PathBuf::from("/legacy/repo")
            );

            let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", "/preferred/repo");
            assert_eq!(
                repo_root().expect("repo root"),
                PathBuf::from("/preferred/repo")
            );
        }

        assert_eq!(
            repo_root().expect("restored fallback repo root"),
            temp_dir.path().join("repos/dotfiles")
        );
    }

    #[test]
    fn xdg_homes_fall_back_to_home_and_respect_explicit_overrides() {
        let _lock = env_lock();
        let temp_dir = TempDir::new("desktopctl-xdg-home").expect("temp dir");
        let _clear_config = ScopedEnvVar::unset("XDG_CONFIG_HOME");
        let _clear_data = ScopedEnvVar::unset("XDG_DATA_HOME");
        let _clear_cache = ScopedEnvVar::unset("XDG_CACHE_HOME");
        let _home = ScopedEnvVar::set("HOME", temp_dir.path().as_os_str());
        assert_eq!(
            xdg_config_home().expect("fallback config home"),
            temp_dir.path().join(".config")
        );
        assert_eq!(
            xdg_data_home().expect("fallback data home"),
            temp_dir.path().join(".local/share")
        );
        assert_eq!(
            xdg_cache_home().expect("fallback cache home"),
            temp_dir.path().join(".cache")
        );

        {
            let _config = ScopedEnvVar::set("XDG_CONFIG_HOME", "/config-root");
            let _data = ScopedEnvVar::set("XDG_DATA_HOME", "/data-root");
            let _cache = ScopedEnvVar::set("XDG_CACHE_HOME", "/cache-root");

            assert_eq!(
                xdg_config_home().expect("config home"),
                PathBuf::from("/config-root")
            );
            assert_eq!(
                xdg_data_home().expect("data home"),
                PathBuf::from("/data-root")
            );
            assert_eq!(
                xdg_cache_home().expect("cache home"),
                PathBuf::from("/cache-root")
            );
        }

        assert_eq!(
            xdg_config_home().expect("restored fallback config home"),
            temp_dir.path().join(".config")
        );
        assert_eq!(
            xdg_data_home().expect("restored fallback data home"),
            temp_dir.path().join(".local/share")
        );
        assert_eq!(
            xdg_cache_home().expect("restored fallback cache home"),
            temp_dir.path().join(".cache")
        );
    }

    #[test]
    fn xdg_runtime_dir_uses_env_or_uid_fallback() {
        let _lock = env_lock();
        let _clear_runtime = ScopedEnvVar::unset("XDG_RUNTIME_DIR");
        assert_eq!(
            xdg_runtime_dir().expect("fallback runtime dir"),
            PathBuf::from(format!("/run/user/{}", current_euid()))
        );

        {
            let _runtime = ScopedEnvVar::set("XDG_RUNTIME_DIR", "/tmp/runtime-dir");
            assert_eq!(
                xdg_runtime_dir().expect("runtime dir"),
                PathBuf::from("/tmp/runtime-dir")
            );
        }

        assert_eq!(
            xdg_runtime_dir().expect("restored fallback runtime dir"),
            PathBuf::from(format!("/run/user/{}", current_euid()))
        );
    }

    #[test]
    fn db_path_creates_parent_directory_under_xdg_data_home() {
        let _lock = env_lock();
        let temp_dir = TempDir::new("desktopctl-db-path").expect("temp dir");
        let _data = ScopedEnvVar::set("XDG_DATA_HOME", temp_dir.path().as_os_str());

        let path = db_path().expect("db path should resolve");

        assert_eq!(path, temp_dir.path().join("desktopctl/desktopctl.db"));
        assert!(path.parent().expect("db parent").is_dir());
    }
}
