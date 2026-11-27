use crate::paths;
use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    os::unix::fs::symlink,
    path::{Path, PathBuf},
    process,
    sync::atomic::{AtomicU64, Ordering},
};

static TEMP_SEQ: AtomicU64 = AtomicU64::new(0);

pub(crate) fn expand_user_path(path: &str) -> crate::Result<PathBuf> {
    if path == "~" {
        return Ok(paths::home_dir()?);
    }
    if let Some(rest) = path.strip_prefix("~/") {
        return Ok(paths::home_dir()?.join(rest));
    }
    Ok(PathBuf::from(path))
}

pub(crate) fn unique_temp_path(path: &Path, tag: &str) -> io::Result<PathBuf> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .unwrap_or("file");
    let seq = TEMP_SEQ.fetch_add(1, Ordering::Relaxed);
    Ok(parent.join(format!(".{tag}.{}.{seq}.{name}", process::id())))
}

/// Unchanged content is left in place: watchers such as Hyprland's config
/// reload fire on every replace.
pub(crate) fn atomic_write(path: &Path, content: &[u8]) -> crate::Result<()> {
    let existing = fs::symlink_metadata(path)
        .ok()
        .filter(|meta| meta.is_file());
    if existing.is_some() && fs::read(path).is_ok_and(|bytes| bytes == content) {
        return Ok(());
    }

    let temp_path = unique_temp_path(path, "tmp")?;
    if let Some(parent) = temp_path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent)?;
    }

    let existing_perms = existing.map(|meta| meta.permissions());

    let write_result = (|| -> io::Result<()> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp_path)?;
        file.write_all(content)?;
        file.sync_all()?;
        if let Some(perms) = existing_perms {
            let _ = file.set_permissions(perms);
        }
        drop(file);
        fs::rename(&temp_path, path)
    })();

    if let Err(error) = write_result {
        let _ = fs::remove_file(&temp_path);
        return Err(error.into());
    }
    Ok(())
}

/// Atomically replace `link_path` with a symlink to `target`.
pub(crate) fn replace_with_symlink(link_path: &Path, target: &Path) -> crate::Result<()> {
    let temp_link = unique_temp_path(link_path, "lnk")?;
    if let Some(parent) = temp_link
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent)?;
    }

    let link_result = (|| -> io::Result<()> {
        symlink(target, &temp_link)?;
        fs::rename(&temp_link, link_path)
    })();

    if let Err(error) = link_result {
        let _ = fs::remove_file(&temp_link);
        return Err(error.into());
    }
    Ok(())
}

/// Unescape a single Lua string literal body (matching `hypr::lua_str`).
pub(crate) fn unescape_lua_str(quoted: &str) -> Option<String> {
    let mut value = String::with_capacity(quoted.len());
    let mut chars = quoted.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            value.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => value.push('\n'),
            Some('r') => value.push('\r'),
            Some(escaped) => value.push(escaped),
            None => return None,
        }
    }
    Some(value)
}

#[cfg(test)]
mod tests {
    use super::atomic_write;
    use crate::test_support::TempDir;
    use std::{fs, os::unix::fs::MetadataExt};

    #[test]
    fn atomic_write_leaves_unchanged_content_in_place() -> crate::Result<()> {
        let dir = TempDir::new("desktopctl-atomic-write")?;
        let path = dir.path().join("out");
        atomic_write(&path, b"same")?;
        let inode = fs::metadata(&path)?.ino();

        atomic_write(&path, b"same")?;
        assert_eq!(fs::metadata(&path)?.ino(), inode);

        atomic_write(&path, b"changed")?;
        assert_ne!(fs::metadata(&path)?.ino(), inode);
        assert_eq!(fs::read(&path)?, b"changed");
        Ok(())
    }
}
