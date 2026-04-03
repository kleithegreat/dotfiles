use std::{
    io::{self, BufRead, BufReader},
    process::{Child, Command, Output, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

const BUSCTL_TIMEOUT: Duration = Duration::from_secs(5);
const PORTAL_TIMEOUT: Duration = Duration::from_secs(120);

pub fn pick_directory() -> Result<Option<String>> {
    let mut monitor = Command::new("dbus-monitor")
        .args([
            "--session",
            "type='signal',interface='org.freedesktop.portal.Request',member='Response'",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;

    let stdout = monitor
        .stdout
        .take()
        .ok_or_else(|| io::Error::other("dbus-monitor stdout was not piped"))?;

    let (sender, receiver) = mpsc::channel();
    let reader_handle = thread::spawn(move || {
        for line in BufReader::new(stdout).lines() {
            match line {
                Ok(line) => {
                    if sender.send(line).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });

    let mut busctl = Command::new("busctl");
    busctl.args([
        "--user",
        "call",
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.FileChooser",
        "OpenFile",
        "ssa{sv}",
        "",
        "Select Wallpaper Directory",
        "2",
        "directory",
        "b",
        "true",
        "modal",
        "b",
        "true",
    ]);

    let output = run_with_timeout(busctl, BUSCTL_TIMEOUT)?;
    if !output.status.success() {
        cleanup_monitor(&mut monitor);
        let _ = reader_handle.join();
        return Err(command_error("busctl", &output).into());
    }

    let start = Instant::now();
    let mut buffer = String::new();
    let mut selected = None;

    while start.elapsed() < PORTAL_TIMEOUT {
        let remaining = PORTAL_TIMEOUT.saturating_sub(start.elapsed());
        match receiver.recv_timeout(remaining) {
            Ok(line) => {
                buffer.push_str(&line);
                buffer.push('\n');

                if let Some(path) = extract_selected_path(&buffer)? {
                    selected = Some(path);
                    break;
                }

                if buffer.contains("uint32 1") || buffer.contains("uint32 2") {
                    break;
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => break,
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }

    cleanup_monitor(&mut monitor);
    let _ = reader_handle.join();

    Ok(selected)
}

fn run_with_timeout(mut command: Command, timeout: Duration) -> Result<Output> {
    let mut child = command.stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()?;
    let start = Instant::now();

    loop {
        if child.try_wait()?.is_some() {
            return Ok(child.wait_with_output()?);
        }

        if start.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            return Err(io::Error::new(io::ErrorKind::TimedOut, "busctl call timed out").into());
        }

        thread::sleep(Duration::from_millis(10));
    }
}

fn cleanup_monitor(monitor: &mut Child) {
    let _ = monitor.kill();
    let _ = monitor.wait();
}

fn extract_selected_path(buffer: &str) -> Result<Option<String>> {
    let uri = match extract_file_uri(buffer) {
        Some(uri) => uri,
        None => return Ok(None),
    };

    Ok(Some(percent_decode(uri)?))
}

fn extract_file_uri(buffer: &str) -> Option<&str> {
    let marker = "file://";
    let start = buffer.find(marker)?;
    let tail = &buffer[start + marker.len()..];
    let end = tail
        .find(|ch: char| ch.is_whitespace() || ch == '"')
        .unwrap_or(tail.len());

    Some(&tail[..end])
}

fn percent_decode(value: &str) -> Result<String> {
    let bytes = value.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;

    while index < bytes.len() {
        if bytes[index] == b'%' {
            if index + 2 >= bytes.len() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "invalid percent-encoding in portal response",
                )
                .into());
            }

            let high = decode_hex(bytes[index + 1])?;
            let low = decode_hex(bytes[index + 2])?;
            decoded.push((high << 4) | low);
            index += 3;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }

    Ok(String::from_utf8(decoded)?)
}

fn decode_hex(byte: u8) -> Result<u8> {
    match byte {
        b'0'..=b'9' => Ok(byte - b'0'),
        b'a'..=b'f' => Ok(byte - b'a' + 10),
        b'A'..=b'F' => Ok(byte - b'A' + 10),
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid percent-encoding in portal response",
        )
        .into()),
    }
}

fn command_error(binary: &str, output: &Output) -> io::Error {
    let stderr = String::from_utf8_lossy(&output.stderr);
    let detail = if stderr.trim().is_empty() {
        "(no stderr)".to_owned()
    } else {
        stderr.trim().to_owned()
    };

    io::Error::other(format!("{binary} failed: {detail}"))
}
