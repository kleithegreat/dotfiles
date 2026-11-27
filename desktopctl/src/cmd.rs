use std::{
    env,
    ffi::OsStr,
    fs,
    io::{self, Write as _},
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output, Stdio},
    thread,
};

pub(crate) const GNOME_INTERFACE_DCONF_DIR: &str = "/org/gnome/desktop/interface";

pub(crate) fn command_error(label: &str, output: &Output) -> io::Error {
    let stderr = String::from_utf8_lossy(&output.stderr);
    let stdout = String::from_utf8_lossy(&output.stdout);
    let detail = if stderr.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    let detail = if detail.is_empty() {
        format!("exited with status {}", output.status)
    } else {
        detail.to_owned()
    };
    io::Error::other(format!("{label} failed: {detail}"))
}

pub(crate) fn find_command(name: &str) -> Option<PathBuf> {
    let path_var = env::var_os("PATH")?;
    env::split_paths(&path_var)
        .map(|dir| dir.join(name))
        .find(|candidate| {
            fs::metadata(candidate)
                .map(|meta| meta.is_file() && (meta.permissions().mode() & 0o111) != 0)
                .unwrap_or(false)
        })
}

pub(crate) fn run<I, S>(command: I) -> crate::Result<()>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    run_with_env(command, std::iter::empty::<(&str, &str)>())?;
    Ok(())
}

pub(crate) fn output<I, S>(command: I) -> crate::Result<String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let out = run_with_env(command, std::iter::empty::<(&str, &str)>())?;
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

pub(crate) fn run_with_env<I, S, E, K, V>(command: I, env_vars: E) -> crate::Result<Output>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
    E: IntoIterator<Item = (K, V)>,
    K: AsRef<OsStr>,
    V: AsRef<OsStr>,
{
    let args: Vec<_> = command
        .into_iter()
        .map(|arg| arg.as_ref().to_os_string())
        .collect();
    let Some((program, rest)) = args.split_first() else {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "empty command").into());
    };

    let mut proc_cmd = Command::new(program);
    proc_cmd.args(rest);
    for (key, value) in env_vars {
        proc_cmd.env(key, value);
    }

    let output = proc_cmd.output()?;
    if output.status.success() {
        return Ok(output);
    }

    let label = args
        .iter()
        .map(|arg| arg.to_string_lossy())
        .collect::<Vec<_>>()
        .join(" ");
    Err(command_error(&label, &output).into())
}

pub(crate) fn dconf_string(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('\'', "\\'")
        .replace('\n', "\\n")
        .replace('\r', "\\r");
    format!("'{escaped}'")
}

/// Writes `(key, GVariant text)` pairs under `dir` in one `dconf load`.
pub(crate) fn dconf_load(dir: &str, entries: &[(&str, String)]) -> crate::Result<()> {
    let mut keyfile = String::from("[/]\n");
    for (key, value) in entries {
        keyfile.push_str(&format!("{key}={value}\n"));
    }
    let mut child = Command::new("dconf")
        .args(["load", &format!("{dir}/")])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    child
        .stdin
        .take()
        .expect("piped stdin")
        .write_all(keyfile.as_bytes())?;
    let output = child.wait_with_output()?;
    if !output.status.success() {
        return Err(command_error("dconf load", &output).into());
    }
    Ok(())
}

/// Spawn a detached background process with null stdio and reap its exit status
/// on a helper thread so daemon workers never leave zombies behind.
pub(crate) fn spawn_detached<I, S>(command: I) -> crate::Result<()>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let args: Vec<_> = command
        .into_iter()
        .map(|arg| arg.as_ref().to_os_string())
        .collect();
    let Some((program, rest)) = args.split_first() else {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "empty command").into());
    };

    let name = PathBuf::from(program)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("child")
        .to_owned();
    let mut child = Command::new(program)
        .args(rest)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    thread::Builder::new()
        .name(format!("reap-{name}"))
        .spawn(move || {
            let _ = child.wait();
        })?;
    Ok(())
}
