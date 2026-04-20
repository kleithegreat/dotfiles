#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use anyhow::{anyhow, Context, Result};
use reqwest::blocking::Client;
use serde_json::{json, Value};
use std::env;
use std::fs;
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
use url::Url;

const DEFAULT_DESKTOP_PORT: u16 = 57_123;
const STARTUP_TIMEOUT: Duration = Duration::from_secs(20);
const HEALTH_TIMEOUT: Duration = Duration::from_millis(1200);
const POLL_INTERVAL: Duration = Duration::from_millis(250);
const WINDOW_LABEL: &str = "main";
const WINDOW_TITLE: &str = "OpenChamber";

#[derive(Default)]
struct ServerState {
    port: Mutex<Option<u16>>,
    stopping: AtomicBool,
}

fn main() {
    let builder = tauri::Builder::default()
        .manage(ServerState::default())
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            focus_main_window(app);
        }))
        .setup(|app| {
            let (port, url) = ensure_local_server().context("failed to start OpenChamber")?;

            if let Some(state) = app.try_state::<ServerState>() {
                *state.port.lock().expect("server state mutex") = Some(port);
            }

            create_main_window(&app.handle(), &url)?;
            Ok(())
        });

    let app = builder
        .build(tauri::generate_context!())
        .expect("failed to build Tauri application");

    app.run(|app_handle, event| match event {
        tauri::RunEvent::ExitRequested { .. } | tauri::RunEvent::Exit => {
            stop_local_server(app_handle);
        }
        _ => {}
    });
}

fn focus_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window(WINDOW_LABEL) {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn create_main_window(app: &tauri::AppHandle, url: &str) -> Result<()> {
    let parsed = Url::parse(url).with_context(|| format!("invalid OpenChamber URL: {url}"))?;

    if let Some(window) = app.get_webview_window(WINDOW_LABEL) {
        window
            .navigate(parsed)
            .map_err(|err| anyhow!(err.to_string()))?;
        focus_main_window(app);
        return Ok(());
    }

    WebviewWindowBuilder::new(app, WINDOW_LABEL, WebviewUrl::External(parsed))
        .title(WINDOW_TITLE)
        .inner_size(1280.0, 800.0)
        .min_inner_size(960.0, 640.0)
        .decorations(false)
        .resizable(true)
        .build()
        .map(|_| ())
        .map_err(|err| anyhow!(err.to_string()))
}

fn ensure_local_server() -> Result<(u16, String)> {
    let openchamber = resolve_openchamber_binary()?;

    let mut candidates = Vec::new();
    if let Some(port) = read_desktop_local_port() {
        candidates.push(port);
    }
    if !candidates.contains(&DEFAULT_DESKTOP_PORT) {
        candidates.push(DEFAULT_DESKTOP_PORT);
    }
    candidates.push(pick_unused_port()?);

    let mut last_error: Option<anyhow::Error> = None;

    for port in candidates {
        match ensure_server_on_port(&openchamber, port) {
            Ok(url) => {
                write_desktop_local_port(port)?;
                return Ok((port, url));
            }
            Err(err) => last_error = Some(err),
        }
    }

    Err(last_error.unwrap_or_else(|| anyhow!("failed to find a usable OpenChamber desktop port")))
}

fn ensure_server_on_port(openchamber: &Path, port: u16) -> Result<String> {
    let url = build_local_url(port);
    let runtime = fetch_runtime(port)?;

    if let Some(runtime) = runtime {
        if runtime == "desktop" {
            if wait_for_health(port, Duration::from_secs(2)) {
                return Ok(url);
            }

            return Err(anyhow!(
                "port {port} is already used by an unresponsive OpenChamber desktop runtime"
            ));
        }

        return Err(anyhow!("port {port} is already used by OpenChamber {runtime} runtime"));
    }

    start_server(openchamber, port)?;

    if !wait_for_health(port, STARTUP_TIMEOUT) {
        let _ = stop_server(openchamber, port);
        return Err(anyhow!("OpenChamber did not become healthy on port {port}"));
    }

    match fetch_runtime(port)? {
        Some(runtime) if runtime == "desktop" => Ok(url),
        Some(runtime) => {
            let _ = stop_server(openchamber, port);
            Err(anyhow!(
                "OpenChamber on port {port} reported runtime '{runtime}' instead of desktop"
            ))
        }
        None => {
            let _ = stop_server(openchamber, port);
            Err(anyhow!("OpenChamber on port {port} never exposed system info"))
        }
    }
}

fn start_server(openchamber: &Path, port: u16) -> Result<()> {
    let output = Command::new(openchamber)
        .args([
            "serve",
            "--port",
            &port.to_string(),
            "--host",
            "127.0.0.1",
            "--quiet",
        ])
        .env("OPENCHAMBER_RUNTIME", "desktop")
        .output()
        .with_context(|| format!("failed to launch {}", openchamber.display()))?;

    if output.status.success() {
        return Ok(());
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let detail = match (stdout.is_empty(), stderr.is_empty()) {
        (false, false) => format!("stdout: {stdout}; stderr: {stderr}"),
        (false, true) => format!("stdout: {stdout}"),
        (true, false) => format!("stderr: {stderr}"),
        (true, true) => "no output".to_string(),
    };

    Err(anyhow!("OpenChamber failed to start on port {port}: {detail}"))
}

fn stop_local_server(app: &tauri::AppHandle) {
    let Some(state) = app.try_state::<ServerState>() else {
        return;
    };

    if state.stopping.swap(true, Ordering::SeqCst) {
        return;
    }

    let port = state.port.lock().expect("server state mutex").take();
    if let Some(port) = port {
        if let Ok(openchamber) = resolve_openchamber_binary() {
            let _ = request_stop_server(&openchamber, port);
        }
    }
}

fn request_stop_server(openchamber: &Path, port: u16) -> Result<()> {
    // Let the window close immediately while the CLI drains its own shutdown path.
    Command::new(openchamber)
        .args(["stop", "--port", &port.to_string(), "--quiet"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .with_context(|| format!("failed to request stop for {} on port {port}", openchamber.display()))?;

    Ok(())
}

fn stop_server(openchamber: &Path, port: u16) -> Result<()> {
    let output = Command::new(openchamber)
        .args(["stop", "--port", &port.to_string(), "--quiet"])
        .output()
        .with_context(|| format!("failed to stop {} on port {port}", openchamber.display()))?;

    if output.status.success() {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if stderr.is_empty() {
        Err(anyhow!("OpenChamber stop failed on port {port}"))
    } else {
        Err(anyhow!("OpenChamber stop failed on port {port}: {stderr}"))
    }
}

fn wait_for_health(port: u16, timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if is_healthy(port) {
            return true;
        }
        std::thread::sleep(POLL_INTERVAL);
    }
    false
}

fn is_healthy(port: u16) -> bool {
    let client = match http_client() {
        Ok(client) => client,
        Err(_) => return false,
    };

    match client.get(health_url(port)).send() {
        Ok(response) => response.status().is_success(),
        Err(_) => false,
    }
}

fn fetch_runtime(port: u16) -> Result<Option<String>> {
    let client = http_client()?;
    let response = match client.get(system_info_url(port)).send() {
        Ok(response) => response,
        Err(_) => return Ok(None),
    };

    if !response.status().is_success() {
        return Ok(None);
    }

    let payload: Value = response.json().context("failed to decode /api/system/info response")?;
    Ok(payload
        .get("runtime")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned))
}

fn http_client() -> Result<Client> {
    Client::builder()
        .timeout(HEALTH_TIMEOUT)
        .no_proxy()
        .build()
        .context("failed to build HTTP client")
}

fn resolve_openchamber_binary() -> Result<PathBuf> {
    if let Ok(value) = env::var("OPENCHAMBER_BINARY") {
        let trimmed = value.trim();
        if !trimmed.is_empty() {
            let candidate = PathBuf::from(trimmed);
            if candidate.exists() {
                return Ok(candidate);
            }
        }
    }

    let path_value = env::var_os("PATH").ok_or_else(|| anyhow!("PATH is not set"))?;
    for segment in env::split_paths(&path_value) {
        let candidate = segment.join("openchamber");
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    Err(anyhow!("unable to locate the OpenChamber CLI"))
}

fn pick_unused_port() -> Result<u16> {
    let listener = TcpListener::bind(("127.0.0.1", 0)).context("failed to allocate a local port")?;
    listener
        .local_addr()
        .map(|address| address.port())
        .context("failed to read allocated port")
}

fn build_local_url(port: u16) -> String {
    format!("http://127.0.0.1:{port}")
}

fn health_url(port: u16) -> String {
    format!("{}/health", build_local_url(port))
}

fn system_info_url(port: u16) -> String {
    format!("{}/api/system/info", build_local_url(port))
}

fn settings_file_path() -> PathBuf {
    if let Ok(dir) = env::var("OPENCHAMBER_DATA_DIR") {
        let trimmed = dir.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed).join("settings.json");
        }
    }

    if let Ok(dir) = env::var("XDG_CONFIG_HOME") {
        let trimmed = dir.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed)
                .join("openchamber")
                .join("settings.json");
        }
    }

    let home = env::var("HOME").unwrap_or_default();
    PathBuf::from(home)
        .join(".config")
        .join("openchamber")
        .join("settings.json")
}

fn read_desktop_local_port() -> Option<u16> {
    let raw = fs::read_to_string(settings_file_path()).ok()?;
    let parsed: Value = serde_json::from_str(&raw).ok()?;
    parsed
        .get("desktopLocalPort")
        .and_then(Value::as_u64)
        .and_then(|value| u16::try_from(value).ok())
        .filter(|value| *value > 0)
}

fn write_desktop_local_port(port: u16) -> Result<()> {
    let path = settings_file_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }

    let mut root = match fs::read_to_string(&path) {
        Ok(raw) => serde_json::from_str(&raw).unwrap_or_else(|_| json!({})),
        Err(_) => json!({}),
    };

    if !root.is_object() {
        root = json!({});
    }

    root["desktopLocalPort"] = Value::Number(serde_json::Number::from(port));

    fs::write(&path, serde_json::to_string_pretty(&root)?)
        .with_context(|| format!("failed to write {}", path.display()))
}
