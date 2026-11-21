use std::{fs, io, path::Path};

pub(crate) struct ProcessInfo {
    pub(crate) pid: u32,
    pub(crate) args: Vec<String>,
}

pub(crate) fn find_processes(exact_name: &str) -> Vec<ProcessInfo> {
    let Ok(entries) = fs::read_dir("/proc") else {
        return Vec::new();
    };

    entries
        .flatten()
        .filter_map(|entry| {
            let pid = entry.file_name().to_str()?.parse::<u32>().ok()?;
            read_matching_process(pid, &entry.path(), exact_name)
        })
        .collect()
}

pub(crate) fn is_process_running(exact_name: &str) -> bool {
    !find_processes(exact_name).is_empty()
}

pub(crate) fn signal_processes(exact_name: &str, signal: libc::c_int) -> crate::Result<usize> {
    let mut signaled = 0usize;
    for proc_info in find_processes(exact_name) {
        let rc = unsafe { libc::kill(proc_info.pid as libc::pid_t, signal) };
        if rc == 0 {
            signaled += 1;
            continue;
        }
        let error = io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ESRCH) {
            continue;
        }
        return Err(io::Error::new(
            error.kind(),
            format!("failed to signal {exact_name} ({}): {error}", proc_info.pid),
        )
        .into());
    }
    Ok(signaled)
}

fn read_matching_process(pid: u32, proc_dir: &Path, exact_name: &str) -> Option<ProcessInfo> {
    let stat = fs::read_to_string(proc_dir.join("stat")).ok()?;
    let open = stat.find('(')?;
    let close = stat.rfind(')')?;
    let comm = &stat[open + 1..close];
    let state = stat.get(close + 2..close + 3)?;
    // Zombie/dead tasks are not alive for lock or daemon presence checks.
    if matches!(state, "Z" | "X") {
        return None;
    }

    let truncated_match = exact_name.len() > 15 && comm == &exact_name[..15];
    if comm != exact_name && !truncated_match {
        return None;
    }

    let args = read_cmdline(proc_dir);
    if truncated_match {
        let exe_name = args
            .first()
            .and_then(|arg0| Path::new(arg0).file_name())
            .and_then(|name| name.to_str());
        if exe_name != Some(exact_name) {
            return None;
        }
    }

    Some(ProcessInfo { pid, args })
}

fn read_cmdline(proc_dir: &Path) -> Vec<String> {
    let Ok(bytes) = fs::read(proc_dir.join("cmdline")) else {
        return Vec::new();
    };
    bytes
        .split(|byte| *byte == 0)
        .filter(|slice| !slice.is_empty())
        .map(|slice| String::from_utf8_lossy(slice).into_owned())
        .collect()
}
