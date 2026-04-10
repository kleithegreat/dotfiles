use std::{
    env,
    ffi::{OsStr, OsString},
    fs, io,
    path::{Path, PathBuf},
    process,
    sync::{Mutex, MutexGuard, OnceLock},
    time::{SystemTime, UNIX_EPOCH},
};

static ENV_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

pub(crate) fn env_lock() -> MutexGuard<'static, ()> {
    ENV_LOCK
        .get_or_init(|| Mutex::new(()))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

pub(crate) struct ScopedEnvVar {
    name: &'static str,
    previous: Option<OsString>,
}

impl ScopedEnvVar {
    pub(crate) fn set(name: &'static str, value: impl AsRef<OsStr>) -> Self {
        let previous = env::var_os(name);
        unsafe { env::set_var(name, value) };
        Self { name, previous }
    }

    pub(crate) fn unset(name: &'static str) -> Self {
        let previous = env::var_os(name);
        unsafe { env::remove_var(name) };
        Self { name, previous }
    }
}

impl Drop for ScopedEnvVar {
    fn drop(&mut self) {
        match self.previous.as_ref() {
            Some(value) => unsafe { env::set_var(self.name, value) },
            None => unsafe { env::remove_var(self.name) },
        }
    }
}

pub(crate) struct TempDir {
    path: PathBuf,
}

impl TempDir {
    pub(crate) fn new(prefix: &str) -> io::Result<Self> {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let path = env::temp_dir().join(format!("{prefix}-{}-{timestamp}", process::id()));
        fs::create_dir_all(&path)?;
        Ok(Self { path })
    }

    pub(crate) fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}
