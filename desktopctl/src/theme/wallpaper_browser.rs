use super::{atomic_write, fnv1a_fingerprint};
use crate::paths;
use image::ImageFormat;
use image::ImageReader;
use image::imageops::FilterType;
use serde_json::{Map, Value};
use std::collections::HashSet;
use std::ffi::OsStr;
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

const PREVIEW_MAX_WIDTH: u32 = 640;
const PREVIEW_MAX_HEIGHT: u32 = 400;

#[derive(Debug, Clone)]
pub(crate) struct WallpaperEntry {
    pub(crate) name: String,
    pub(crate) path: PathBuf,
    pub(crate) preview_path: Option<PathBuf>,
}

pub(crate) fn list_wallpapers(directory: &Path) -> crate::Result<Vec<WallpaperEntry>> {
    if !directory.is_dir() {
        return Ok(Vec::new());
    }

    let mut files = Vec::new();
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        if !entry.file_type()?.is_file() {
            continue;
        }

        let path = entry.path();
        if !is_supported_wallpaper(&path) {
            continue;
        }

        files.push(path);
    }

    files.sort_by(|left, right| {
        lower_file_name(left)
            .cmp(&lower_file_name(right))
            .then_with(|| left.file_name().cmp(&right.file_name()))
    });

    let mut items = Vec::with_capacity(files.len());
    for path in files {
        let name = path
            .file_name()
            .and_then(OsStr::to_str)
            .unwrap_or_default()
            .to_owned();
        let preview_path = match ensure_preview(&path) {
            Ok(preview_path) => Some(preview_path),
            Err(error) => {
                eprintln!(
                    "warning: failed to generate wallpaper preview for {}: {error}",
                    path.display()
                );
                None
            }
        };

        items.push(WallpaperEntry {
            name,
            path,
            preview_path,
        });
    }

    evict_stale_previews(&items);

    Ok(items)
}

// Previews are keyed by source path, size, and mtime, so renamed or edited
// wallpapers leave orphaned cache files behind; drop everything the current
// listing does not reference. Best-effort: eviction errors are ignored.
fn evict_stale_previews(entries: &[WallpaperEntry]) {
    let expected = entries
        .iter()
        .filter_map(|entry| entry.preview_path.clone())
        .collect::<HashSet<_>>();

    let Ok(cache_dir) = preview_cache_dir() else {
        return;
    };
    let Ok(cache_entries) = fs::read_dir(&cache_dir) else {
        return;
    };

    for cache_entry in cache_entries.flatten() {
        let path = cache_entry.path();
        if !expected.contains(&path) {
            let _ = fs::remove_file(&path);
        }
    }
}

pub(crate) fn json_value(entries: &[WallpaperEntry]) -> Value {
    let mut items = Vec::with_capacity(entries.len());

    for entry in entries {
        let mut item = Map::new();
        item.insert("name".to_owned(), Value::String(entry.name.clone()));
        item.insert(
            "path".to_owned(),
            Value::String(entry.path.to_string_lossy().into_owned()),
        );
        item.insert(
            "preview_path".to_owned(),
            match &entry.preview_path {
                Some(path) => Value::String(path.to_string_lossy().into_owned()),
                None => Value::Null,
            },
        );
        items.push(Value::Object(item));
    }

    Value::Array(items)
}

fn ensure_preview(source: &Path) -> crate::Result<PathBuf> {
    let preview_path = preview_path(source)?;
    if preview_path.is_file() {
        return Ok(preview_path);
    }

    let image = ImageReader::open(source)?.decode()?;
    let preview = image.resize(PREVIEW_MAX_WIDTH, PREVIEW_MAX_HEIGHT, FilterType::Lanczos3);
    let mut output = Cursor::new(Vec::new());
    preview.write_to(&mut output, ImageFormat::Png)?;
    atomic_write(&preview_path, &output.into_inner())?;
    Ok(preview_path)
}

fn preview_path(source: &Path) -> crate::Result<PathBuf> {
    let metadata = fs::metadata(source)?;
    let modified = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .unwrap_or_default();
    let fingerprint = fnv1a_fingerprint(&format!(
        "{}:{}:{}:{}:{}:{}",
        source.to_string_lossy(),
        metadata.len(),
        modified.as_secs(),
        modified.subsec_nanos(),
        PREVIEW_MAX_WIDTH,
        PREVIEW_MAX_HEIGHT
    ));
    let stem = sanitize_stem(
        source
            .file_stem()
            .and_then(OsStr::to_str)
            .unwrap_or("wallpaper"),
    );
    Ok(preview_cache_dir()?.join(format!(
        "{stem}-{fingerprint}-{}x{}.png",
        PREVIEW_MAX_WIDTH, PREVIEW_MAX_HEIGHT
    )))
}

fn preview_cache_dir() -> crate::Result<PathBuf> {
    Ok(paths::xdg_cache_home()?.join("desktopctl/wallpaper-previews"))
}

fn is_supported_wallpaper(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(OsStr::to_str)
            .map(|ext| ext.to_ascii_lowercase()),
        Some(ext) if matches!(ext.as_str(), "jpg" | "jpeg" | "png" | "webp")
    )
}

fn lower_file_name(path: &Path) -> String {
    path.file_name()
        .and_then(OsStr::to_str)
        .unwrap_or_default()
        .to_ascii_lowercase()
}

fn sanitize_stem(stem: &str) -> String {
    let mut output = String::with_capacity(stem.len());
    for character in stem.chars() {
        if character.is_ascii_alphanumeric() {
            output.push(character.to_ascii_lowercase());
        } else {
            output.push('-');
        }
    }

    let sanitized = output.trim_matches('-');
    if sanitized.is_empty() {
        "wallpaper".to_owned()
    } else {
        sanitized.to_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{ScopedEnvVar, TempDir, env_lock};
    use image::{Rgb, RgbImage};

    fn write_test_image(path: &Path, width: u32, height: u32) -> crate::Result<()> {
        let image = RgbImage::from_fn(width, height, |x, y| {
            Rgb([(x % 255) as u8, (y % 255) as u8, ((x + y) % 255) as u8])
        });
        image.save(path)?;
        Ok(())
    }

    #[test]
    fn list_wallpapers_generates_cached_previews_for_supported_images() -> crate::Result<()> {
        let _lock = env_lock();
        let wallpapers_dir = TempDir::new("desktopctl-wallpapers").expect("temp dir");
        let cache_dir = TempDir::new("desktopctl-wallpaper-cache").expect("temp dir");
        let _cache = ScopedEnvVar::set("XDG_CACHE_HOME", cache_dir.path().as_os_str());

        write_test_image(&wallpapers_dir.path().join("sample.png"), 1600, 900)?;
        fs::write(wallpapers_dir.path().join("notes.txt"), b"ignore")?;

        let entries = list_wallpapers(wallpapers_dir.path())?;
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].name, "sample.png");

        let preview_path = entries[0]
            .preview_path
            .as_ref()
            .expect("preview path should be generated");
        assert!(preview_path.is_file());

        let preview = ImageReader::open(preview_path)?.decode()?;
        assert!(preview.width() <= PREVIEW_MAX_WIDTH);
        assert!(preview.height() <= PREVIEW_MAX_HEIGHT);
        Ok(())
    }

    #[test]
    fn list_wallpapers_keeps_supported_files_even_if_preview_generation_fails() -> crate::Result<()>
    {
        let _lock = env_lock();
        let wallpapers_dir = TempDir::new("desktopctl-wallpapers-invalid").expect("temp dir");
        let cache_dir = TempDir::new("desktopctl-wallpaper-cache-invalid").expect("temp dir");
        let _cache = ScopedEnvVar::set("XDG_CACHE_HOME", cache_dir.path().as_os_str());

        fs::write(wallpapers_dir.path().join("broken.jpg"), b"not-an-image")?;

        let entries = list_wallpapers(wallpapers_dir.path())?;
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].name, "broken.jpg");
        assert!(entries[0].preview_path.is_none());
        Ok(())
    }

    #[test]
    fn list_wallpapers_evicts_stale_previews() -> crate::Result<()> {
        let _lock = env_lock();
        let wallpapers_dir = TempDir::new("desktopctl-wallpapers-evict").expect("temp dir");
        let cache_dir = TempDir::new("desktopctl-wallpaper-cache-evict").expect("temp dir");
        let _cache = ScopedEnvVar::set("XDG_CACHE_HOME", cache_dir.path().as_os_str());

        write_test_image(&wallpapers_dir.path().join("sample.png"), 800, 600)?;

        let preview_dir = cache_dir.path().join("desktopctl/wallpaper-previews");
        fs::create_dir_all(&preview_dir)?;
        let stale = preview_dir.join("stale-0000000000000000-640x400.png");
        fs::write(&stale, b"stale preview")?;

        let entries = list_wallpapers(wallpapers_dir.path())?;
        assert_eq!(entries.len(), 1);
        let preview_path = entries[0]
            .preview_path
            .as_ref()
            .expect("preview path should be generated");

        assert!(preview_path.is_file(), "live preview must be kept");
        assert!(!stale.exists(), "stale preview must be evicted");
        Ok(())
    }

    #[test]
    fn list_wallpapers_returns_empty_for_missing_directory() -> crate::Result<()> {
        let _lock = env_lock();
        let cache_dir = TempDir::new("desktopctl-wallpaper-cache-empty").expect("temp dir");
        let _cache = ScopedEnvVar::set("XDG_CACHE_HOME", cache_dir.path().as_os_str());

        let entries = list_wallpapers(Path::new("/definitely/not/a/real/wallpaper-directory"))?;
        assert!(entries.is_empty());
        Ok(())
    }
}
