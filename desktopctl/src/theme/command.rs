//! Subprocess helpers; every failure carries stderr, else stdout, else the exit status.

use std::{
    collections::BTreeMap,
    env,
    ffi::OsStr,
    io,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
};

pub(crate) fn run<S: AsRef<OsStr>>(command: &[S]) -> crate::Result<()> {
    run_with_env(command, &BTreeMap::new())
}

pub(crate) fn run_with_env<S: AsRef<OsStr>>(
    command: &[S],
    env: &BTreeMap<String, String>,
) -> crate::Result<()> {
    capture(command, env).map(drop)
}

/// Stdout of a command that exited successfully.
pub(crate) fn output<S: AsRef<OsStr>>(command: &[S]) -> crate::Result<String> {
    capture(command, &BTreeMap::new())
}

fn capture<S: AsRef<OsStr>>(
    command: &[S],
    env: &BTreeMap<String, String>,
) -> crate::Result<String> {
    let Some((program, args)) = command.split_first() else {
        return Err(crate::invalid_input("Command cannot be empty").into());
    };
    let program = program.as_ref();

    let output = match Command::new(program).args(args).envs(env).output() {
        Ok(output) => output,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Err(
                io::Error::new(io::ErrorKind::NotFound, format!("{program:?} not found")).into(),
            );
        }
        Err(error) => return Err(error.into()),
    };
    if output.status.success() {
        return Ok(String::from_utf8_lossy(&output.stdout).into_owned());
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    let message = if !stderr.is_empty() {
        stderr
    } else if !stdout.is_empty() {
        stdout
    } else {
        format!("command exited with status {}", output.status)
    };
    Err(io::Error::other(message).into())
}

pub(crate) const GNOME_INTERFACE_DCONF_DIR: &str = "/org/gnome/desktop/interface";

pub(crate) fn dconf_write(path: &str, value: &str) -> crate::Result<()> {
    run(&["dconf", "write", path, value])
}

pub(crate) fn find_command(program: &str) -> Option<PathBuf> {
    if program.contains(std::path::MAIN_SEPARATOR) {
        let path = PathBuf::from(program);
        return is_executable(&path).then_some(path);
    }

    let path_var = env::var_os("PATH")?;
    env::split_paths(&path_var)
        .map(|dir| dir.join(program))
        .find(|candidate| is_executable(candidate))
}

fn is_executable(path: &Path) -> bool {
    match path.metadata() {
        Ok(metadata) => metadata.is_file() && metadata.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}
