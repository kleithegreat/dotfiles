use crate::{paths, theme};
use serde::{Deserialize, Serialize};
use std::{
    env, fs,
    io::{self, Read},
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    process::{Command, Output},
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

const INPUT_CONF_RELATIVE_PATH: &str = "hypr/input-defaults.lua";
const INPUT_RUNTIME_RELATIVE_PATH: &str = "hypr/input-runtime.lua";
const ANIMATIONS_OVERRIDE_RELATIVE_PATH: &str = "hypr/animations-override-data.lua";
const KEYBINDS_OVERRIDE_RELATIVE_PATH: &str = "hypr/keybinds-override-data.lua";

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct WindowInfo {
    #[serde(default)]
    pub(crate) class: String,
    #[serde(rename = "initialClass", default)]
    pub(crate) initial_class: String,
    #[serde(default)]
    floating: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InputSetting {
    Sensitivity,
    AccelProfile,
    ScrollFactor,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum LidSwitchState {
    Open,
    Closed,
    Sync,
}

impl LidSwitchState {
    pub(crate) fn parse(value: &str) -> Result<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "open" => Ok(Self::Open),
            "closed" => Ok(Self::Closed),
            "sync" => Ok(Self::Sync),
            _ => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "lid switch state must be 'open', 'closed', or 'sync'",
            )
            .into()),
        }
    }
}

#[derive(Debug, Deserialize)]
struct MonitorInfo {
    #[serde(default)]
    name: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    make: String,
    #[serde(default)]
    model: String,
    #[serde(default)]
    serial: String,
    #[serde(default)]
    disabled: bool,
    #[serde(default)]
    focused: bool,
    #[serde(rename = "activeWorkspace", default)]
    active_workspace: WorkspaceRef,
}

impl MonitorInfo {
    /// Mirror of Hyprland's `CMonitor::matchesStaticSelector`: `desc:` selectors
    /// prefix-match either description form, anything else is a connector name.
    fn matches_selector(&self, selector: &str) -> bool {
        let Some(description) = selector.strip_prefix("desc:") else {
            return self.name == selector;
        };

        // Hyprland strips commas from descriptions so that monitor rules can
        // address displays whose EDID description contains one.
        let description = strip_commas(description.trim());
        !description.is_empty()
            && (strip_commas(&self.description).starts_with(&description)
                || strip_commas(&self.short_description()).starts_with(&description))
    }

    /// Hyprland's `m_shortDescription`: make, model, and serial joined by spaces.
    fn short_description(&self) -> String {
        [
            self.make.as_str(),
            self.model.as_str(),
            self.serial.as_str(),
        ]
        .join(" ")
        .trim()
        .to_owned()
    }
}

#[derive(Debug, Default, Deserialize)]
struct WorkspaceRef {
    #[serde(default)]
    id: i64,
}

#[derive(Debug, Deserialize)]
struct WorkspaceInfo {
    #[serde(default)]
    id: i64,
    #[serde(default)]
    windows: u32,
}

#[derive(Debug, Deserialize)]
struct WorkspaceRuleInfo {
    #[serde(rename = "workspaceString", default)]
    workspace_string: String,
    #[serde(default)]
    monitor: Option<String>,
}

impl InputSetting {
    pub(crate) fn parse(key: &str) -> Result<Self> {
        match key.trim() {
            "sensitivity" => Ok(Self::Sensitivity),
            "accel_profile" => Ok(Self::AccelProfile),
            "scroll_factor" => Ok(Self::ScrollFactor),
            _ => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("unsupported Hyprland input setting '{key}'"),
            )
            .into()),
        }
    }

    fn keyword(self) -> &'static str {
        match self {
            Self::Sensitivity => "input:sensitivity",
            Self::AccelProfile => "input:accel_profile",
            Self::ScrollFactor => "input:scroll_factor",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum AccelProfile {
    Adaptive,
    Flat,
}

impl AccelProfile {
    fn parse(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "adaptive" => Some(Self::Adaptive),
            "flat" => Some(Self::Flat),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Adaptive => "adaptive",
            Self::Flat => "flat",
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct InputState {
    pub(crate) sensitivity: f64,
    pub(crate) accel_profile: AccelProfile,
    pub(crate) scroll_factor: f64,
}

impl Default for InputState {
    fn default() -> Self {
        Self {
            sensitivity: 0.75,
            accel_profile: AccelProfile::Flat,
            scroll_factor: 1.0,
        }
    }
}

/// Print the effective Hyprland input state.
pub(crate) fn print_input_status(json: bool) -> Result<()> {
    let state = load_effective_input_state()?;

    if json {
        println!("{}", serde_json::to_string(&state)?);
    } else {
        println!("sensitivity = {}", format_decimal(state.sensitivity));
        println!("accel_profile = {}", state.accel_profile.as_str());
        println!("scroll_factor = {}", format_decimal(state.scroll_factor));
    }

    Ok(())
}

/// Persist and apply one managed Hyprland input setting.
pub(crate) fn set_input_value(setting: InputSetting, value: &str) -> Result<()> {
    let current = load_effective_input_state()?;
    let mut next = current.clone();

    match setting {
        InputSetting::Sensitivity => next.sensitivity = parse_sensitivity(value)?,
        InputSetting::AccelProfile => next.accel_profile = parse_accel_profile(value)?,
        InputSetting::ScrollFactor => next.scroll_factor = parse_scroll_factor(value)?,
    }

    if input_setting_value(&current, setting) == input_setting_value(&next, setting) {
        return Ok(());
    }

    persist_input_runtime_state(&next)?;

    if let Err(error) = keyword(setting.keyword(), &input_setting_value(&next, setting)) {
        let runtime_path = input_runtime_path()?;
        if let Err(revert_error) = persist_input_runtime_state(&current) {
            return Err(io::Error::other(format!(
                "{error}; additionally failed to revert {}: {revert_error}",
                runtime_path.display()
            ))
            .into());
        }

        return Err(error);
    }

    Ok(())
}

/// Query Hyprland for the currently active window.
pub(crate) fn active_window() -> Result<WindowInfo> {
    let output = hyprctl_output(&["activewindow", "-j"])?;
    Ok(serde_json::from_slice(&output.stdout)?)
}

/// Run `hyprctl dispatch ...`.
pub(crate) fn dispatch(args: &[&str]) -> Result<()> {
    let mut command_args = Vec::with_capacity(args.len() + 1);
    command_args.push("dispatch");
    command_args.extend(args.iter().copied());
    hyprctl_output(&command_args)?;
    Ok(())
}

/// Run `hyprctl keyword ...`.
pub(crate) fn keyword(key: &str, value: &str) -> Result<()> {
    hyprctl_output(&["keyword", key, value])?;
    Ok(())
}

/// Run `hyprctl --batch ...`.
fn batch(commands: &[&str]) -> Result<()> {
    if commands.is_empty() {
        return Ok(());
    }

    let batch = commands.join(" ; ");
    hyprctl_output(&["--batch", batch.as_str()])?;
    Ok(())
}

/// Toggle floating and resize/center windows when promoting from tiled mode.
pub(crate) fn toggle_float() -> Result<()> {
    let window = active_window()?;
    if window.floating {
        dispatch(&["togglefloating"])?;
    } else {
        batch(&[
            "dispatch togglefloating",
            "dispatch resizeactive exact 75% 75%",
            "dispatch centerwindow 1",
        ])?;
    }

    Ok(())
}

/// Apply the laptop lid-switch monitor policy.
pub(crate) fn handle_lid_switch(
    state: LidSwitchState,
    internal_monitor: &str,
    open_spec: &str,
) -> Result<()> {
    let internal_monitor = internal_monitor.trim();
    validate_non_empty_field("internal monitor", internal_monitor)?;
    if internal_monitor.contains(',') {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "internal monitor must not contain commas",
        )
        .into());
    }

    let open_spec = open_spec.trim();
    validate_non_empty_field("open monitor spec", open_spec)?;

    match state {
        LidSwitchState::Open => keyword("monitor", &format!("{internal_monitor},{open_spec}")),
        LidSwitchState::Closed => close_lid_monitor(internal_monitor),
        LidSwitchState::Sync => {
            if read_lid_state()?.is_some_and(|state| state == LidSwitchState::Closed) {
                close_lid_monitor(internal_monitor)?;
            }
            Ok(())
        }
    }
}

fn close_lid_monitor(internal_monitor: &str) -> Result<()> {
    if active_external_monitor_exists(internal_monitor)? {
        keyword("monitor", &format!("{internal_monitor},disable"))?;
    }

    Ok(())
}

fn active_external_monitor_exists(internal_monitor: &str) -> Result<bool> {
    Ok(query_monitors()?
        .iter()
        .any(|monitor| !monitor.disabled && monitor.name != internal_monitor))
}

/// Pull the focused output back onto the numbered workspace set when every
/// numbered workspace is pinned to a monitor that is not connected.
///
/// Hyprland's `CMonitor::findAvailableDefaultWS` skips any workspace ID bound to
/// a monitor the new output does not match, so a laptop-only login under the
/// `workspace = 1..10, monitor:desc:<external>` pins in
/// `hosts/laptop/monitors.lua` parks the internal panel on workspace 11: no
/// pill in the bar, and no keybind that can reach it again.
pub(crate) fn reclaim_workspaces() -> Result<()> {
    let target = reclaim_target(
        &query_monitors()?,
        &query_workspace_rules()?,
        &query_workspaces()?,
    );

    match target {
        Some(target) => dispatch(&["workspace", &target.to_string()]),
        None => Ok(()),
    }
}

/// The workspace the focused output should be pulled onto, if any.
fn reclaim_target(
    monitors: &[MonitorInfo],
    rules: &[WorkspaceRuleInfo],
    workspaces: &[WorkspaceInfo],
) -> Option<i64> {
    let orphaned = orphaned_pinned_workspaces(monitors, rules);
    let (&target, &highest) = (orphaned.first()?, orphaned.last()?);

    let focused = monitors
        .iter()
        .find(|monitor| monitor.focused && !monitor.disabled)?;

    // Only act on an output parked past the pinned block. Anything inside it is
    // a workspace the user can already see and reach.
    let parked = focused.active_workspace.id;
    if parked <= highest {
        return None;
    }

    // Never yank focus away from windows that are already open, and never steal
    // a workspace some other output is displaying.
    let parked_has_windows = workspaces
        .iter()
        .any(|workspace| workspace.id == parked && workspace.windows > 0);
    let target_is_shown = monitors
        .iter()
        .any(|monitor| !monitor.disabled && monitor.active_workspace.id == target);

    (!parked_has_windows && !target_is_shown).then_some(target)
}

/// Numbered workspaces pinned to a monitor selector that nothing connected
/// matches, lowest first.
fn orphaned_pinned_workspaces(monitors: &[MonitorInfo], rules: &[WorkspaceRuleInfo]) -> Vec<i64> {
    let mut ids: Vec<i64> = rules
        .iter()
        .filter_map(|rule| {
            let id = rule.workspace_string.trim().parse::<i64>().ok()?;
            if id <= 0 {
                return None;
            }

            let selector = rule.monitor.as_deref()?.trim();
            if selector.is_empty() {
                return None;
            }

            let connected = monitors
                .iter()
                .any(|monitor| !monitor.disabled && monitor.matches_selector(selector));
            (!connected).then_some(id)
        })
        .collect();

    ids.sort_unstable();
    ids.dedup();
    ids
}

fn query_monitors() -> Result<Vec<MonitorInfo>> {
    let output = hyprctl_output(&["monitors", "-j"])?;
    Ok(serde_json::from_slice(&output.stdout)?)
}

fn query_workspaces() -> Result<Vec<WorkspaceInfo>> {
    let output = hyprctl_output(&["workspaces", "-j"])?;
    Ok(serde_json::from_slice(&output.stdout)?)
}

fn query_workspace_rules() -> Result<Vec<WorkspaceRuleInfo>> {
    let output = hyprctl_output(&["workspacerules", "-j"])?;
    Ok(serde_json::from_slice(&output.stdout)?)
}

fn strip_commas(value: &str) -> String {
    value.replace(',', "")
}

fn read_lid_state() -> Result<Option<LidSwitchState>> {
    let root = Path::new("/proc/acpi/button/lid");
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };

    let mut saw_open = false;
    for entry in entries {
        let state_path = entry?.path().join("state");
        let contents = match fs::read_to_string(state_path) {
            Ok(contents) => contents.to_ascii_lowercase(),
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error.into()),
        };

        if contents.contains("closed") {
            return Ok(Some(LidSwitchState::Closed));
        }
        if contents.contains("open") {
            saw_open = true;
        }
    }

    Ok(saw_open.then_some(LidSwitchState::Open))
}

/// How long to wait for an unavailable event socket before retrying.
const EVENT_SOCKET_RETRY_DELAY: Duration = Duration::from_secs(2);
/// Read timeout, so a quiet socket still lets the loop observe `shutdown`.
const EVENT_SOCKET_READ_TIMEOUT: Duration = Duration::from_secs(5);

/// Stream Hyprland event-socket lines to `handler` until `shutdown` is set,
/// reconnecting whenever the compositor goes away. `on_connect` runs after every
/// successful connection so consumers can reseed state they may have missed.
pub(crate) fn watch_event_socket<C, H>(shutdown: &AtomicBool, mut on_connect: C, mut handler: H)
where
    C: FnMut(),
    H: FnMut(&str),
{
    while !shutdown.load(Ordering::SeqCst) {
        let Ok(socket_path) = socket2_path() else {
            if !shutdown.load(Ordering::SeqCst) {
                thread::sleep(EVENT_SOCKET_RETRY_DELAY);
            }
            continue;
        };

        if let Ok(mut socket) = UnixStream::connect(&socket_path) {
            on_connect();
            let _ = socket.set_read_timeout(Some(EVENT_SOCKET_READ_TIMEOUT));
            let mut buffer = Vec::new();
            let mut chunk = [0_u8; 4096];

            while !shutdown.load(Ordering::SeqCst) {
                match socket.read(&mut chunk) {
                    Ok(0) => break,
                    Ok(bytes_read) => {
                        buffer.extend_from_slice(&chunk[..bytes_read]);
                        consume_socket_lines(&mut buffer, &mut handler);
                    }
                    Err(error)
                        if error.kind() == io::ErrorKind::WouldBlock
                            || error.kind() == io::ErrorKind::TimedOut =>
                    {
                        continue;
                    }
                    Err(_) => break,
                }
            }
        }

        if !shutdown.load(Ordering::SeqCst) {
            thread::sleep(EVENT_SOCKET_RETRY_DELAY);
        }
    }
}

fn consume_socket_lines<H: FnMut(&str)>(buffer: &mut Vec<u8>, handler: &mut H) {
    while let Some(newline_index) = buffer.iter().position(|byte| *byte == b'\n') {
        let line = String::from_utf8_lossy(&buffer[..newline_index]).into_owned();
        buffer.drain(..=newline_index);
        handler(&line);
    }
}

/// Return the Hyprland event-socket path used by the daemon watchers.
pub(crate) fn socket2_path() -> Result<PathBuf> {
    let signature = hyprland_signature();
    if let Some(signature) = signature.as_deref() {
        let runtime_path = runtime_socket2_path(signature)?;
        if runtime_path.exists() {
            return Ok(runtime_path);
        }

        let tmp_path = tmp_socket2_path(signature);
        if tmp_path.exists() {
            return Ok(tmp_path);
        }
    }

    if let Some(path) = discover_socket2_path()? {
        return Ok(path);
    }

    if let Some(signature) = signature {
        return Ok(runtime_socket2_path(&signature)?);
    }

    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "unable to resolve Hyprland event socket path",
    )
    .into())
}

fn hyprland_signature() -> Option<String> {
    env::var("HYPRLAND_INSTANCE_SIGNATURE")
        .ok()
        .filter(|value| !value.is_empty())
}

fn runtime_socket2_path(signature: &str) -> io::Result<PathBuf> {
    Ok(paths::xdg_runtime_dir()?
        .join("hypr")
        .join(signature)
        .join(".socket2.sock"))
}

fn tmp_socket2_path(signature: &str) -> PathBuf {
    PathBuf::from("/tmp/hypr")
        .join(signature)
        .join(".socket2.sock")
}

fn discover_socket2_path() -> Result<Option<PathBuf>> {
    let mut candidates = Vec::new();
    candidates.extend(find_socket2_candidates(
        &paths::xdg_runtime_dir()?.join("hypr"),
    )?);
    candidates.extend(find_socket2_candidates(&PathBuf::from("/tmp/hypr"))?);

    Ok(candidates
        .into_iter()
        .max_by_key(|(modified, _)| *modified)
        .map(|(_, path)| path))
}

fn find_socket2_candidates(root: &PathBuf) -> io::Result<Vec<(SystemTime, PathBuf)>> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error),
    };

    let mut candidates = Vec::new();
    for entry in entries {
        let entry = entry?;
        let path = entry.path().join(".socket2.sock");
        if !path.exists() {
            continue;
        }

        let modified = fs::metadata(&path)
            .and_then(|metadata| metadata.modified())
            .unwrap_or(UNIX_EPOCH);
        candidates.push((modified, path));
    }

    Ok(candidates)
}

pub(crate) fn input_runtime_path() -> Result<PathBuf> {
    Ok(paths::xdg_config_home()?.join(INPUT_RUNTIME_RELATIVE_PATH))
}

fn load_effective_input_state() -> Result<InputState> {
    let mut state = load_default_input_state()?;
    apply_optional_input_state_file(&input_runtime_path()?, &mut state)?;
    Ok(state)
}

fn load_default_input_state() -> Result<InputState> {
    let mut state = InputState::default();
    apply_optional_input_state_file(
        &paths::xdg_config_home()?.join(INPUT_CONF_RELATIVE_PATH),
        &mut state,
    )?;
    Ok(state)
}

fn apply_optional_input_state_file(path: &Path, state: &mut InputState) -> Result<()> {
    let contents = match fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };

    parse_input_state_from_str(&contents, state);
    Ok(())
}

/// Read one `key = value,` field out of a flat generated Lua data table.
/// Values are returned with surrounding quotes stripped. The generators only
/// ever emit one scalar field per line, so a real Lua parser would be overkill.
fn parse_lua_table_field(line: &str) -> Option<(&str, &str)> {
    let line = line.split("--").next().unwrap_or("").trim();
    let (key, value) = line.split_once('=')?;

    let key = key.trim();
    if key.is_empty() || !key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return None;
    }

    let value = value.trim().trim_end_matches(',').trim();
    let value = value
        .strip_prefix('"')
        .and_then(|rest| rest.strip_suffix('"'))
        .unwrap_or(value);

    Some((key, value))
}

fn parse_input_state_from_str(contents: &str, state: &mut InputState) {
    for raw_line in contents.lines() {
        let Some((key, value)) = parse_lua_table_field(raw_line) else {
            continue;
        };

        match key {
            "sensitivity" => {
                if let Ok(parsed) = value.parse::<f64>() {
                    state.sensitivity = parsed;
                }
            }
            "accel_profile" => {
                if let Some(parsed) = AccelProfile::parse(value) {
                    state.accel_profile = parsed;
                }
            }
            "scroll_factor" => {
                if let Ok(parsed) = value.parse::<f64>()
                    && parsed.is_finite()
                    && parsed > 0.0
                {
                    state.scroll_factor = parsed;
                }
            }
            _ => {}
        }
    }
}

fn persist_input_runtime_state(state: &InputState) -> Result<()> {
    let contents = render_input_runtime_state(state);
    theme::atomic_write(&input_runtime_path()?, contents.as_bytes())
}

fn render_input_runtime_state(state: &InputState) -> String {
    format!(
        "-- Generated by desktopctl - do not edit\nreturn {{\n    sensitivity = {},\n    accel_profile = \"{}\",\n    scroll_factor = {},\n}}\n",
        format_decimal(state.sensitivity),
        state.accel_profile.as_str(),
        format_decimal(state.scroll_factor)
    )
}

fn input_setting_value(state: &InputState, setting: InputSetting) -> String {
    match setting {
        InputSetting::Sensitivity => format_decimal(state.sensitivity),
        InputSetting::AccelProfile => state.accel_profile.as_str().to_owned(),
        InputSetting::ScrollFactor => format_decimal(state.scroll_factor),
    }
}

fn parse_sensitivity(value: &str) -> Result<f64> {
    let parsed = parse_finite_decimal(value, "sensitivity")?;
    if !(-1.0..=1.0).contains(&parsed) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "sensitivity must be between -1.0 and 1.0",
        )
        .into());
    }

    Ok(round_decimal(parsed))
}

fn parse_accel_profile(value: &str) -> Result<AccelProfile> {
    AccelProfile::parse(value).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "accel_profile must be either 'adaptive' or 'flat'",
        )
        .into()
    })
}

fn parse_scroll_factor(value: &str) -> Result<f64> {
    let parsed = parse_finite_decimal(value, "scroll_factor")?;
    if parsed <= 0.0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "scroll_factor must be greater than 0",
        )
        .into());
    }

    Ok(round_decimal(parsed))
}

fn parse_finite_decimal(value: &str, label: &str) -> Result<f64> {
    let parsed = value.trim().parse::<f64>().map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("{label} must be a number"),
        )
    })?;

    if !parsed.is_finite() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("{label} must be finite"),
        )
        .into());
    }

    Ok(parsed)
}

fn round_decimal(value: f64) -> f64 {
    (value * 100.0).round() / 100.0
}

fn format_decimal(value: f64) -> String {
    let rounded = round_decimal(value);
    let mut rendered = format!("{rounded:.2}");

    while rendered.ends_with('0') && rendered.contains('.') {
        rendered.pop();
    }

    if rendered.ends_with('.') {
        rendered.push('0');
    }

    rendered
}

// ── Animation override persistence ──────────────────────────────

#[derive(Debug, Deserialize)]
struct AnimationsPayload {
    #[serde(default)]
    beziers: std::collections::BTreeMap<String, [f64; 4]>,
    #[serde(default)]
    animations: Vec<AnimationEntry>,
}

#[derive(Debug, Deserialize)]
struct AnimationEntry {
    name: String,
    enabled: bool,
    speed: f64,
    curve: String,
    #[serde(default)]
    style: String,
}

fn animations_override_path() -> Result<PathBuf> {
    Ok(paths::xdg_config_home()?.join(ANIMATIONS_OVERRIDE_RELATIVE_PATH))
}

fn validate_rendered_field(label: &str, value: &str) -> Result<()> {
    if value.contains('\n') || value.contains('\r') {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("{label} must not contain newlines"),
        )
        .into());
    }

    Ok(())
}

fn validate_non_empty_field(label: &str, value: &str) -> Result<()> {
    validate_rendered_field(label, value)?;
    if value.trim().is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("{label} must not be empty"),
        )
        .into());
    }

    Ok(())
}

fn validate_animations_payload(payload: &AnimationsPayload) -> Result<()> {
    for (name, points) in &payload.beziers {
        validate_non_empty_field("bezier name", name)?;
        for point in points {
            if !point.is_finite() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("bezier '{name}' contains a non-finite point"),
                )
                .into());
            }
        }
    }

    for animation in &payload.animations {
        validate_non_empty_field("animation name", &animation.name)?;
        validate_non_empty_field("animation curve", &animation.curve)?;
        validate_rendered_field("animation style", &animation.style)?;
        if !animation.speed.is_finite() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("animation '{}' speed must be finite", animation.name),
            )
            .into());
        }
    }

    Ok(())
}

/// Quote a value as a Lua string literal for the generated data tables.
fn lua_str(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r");
    format!("\"{escaped}\"")
}

fn render_animations_override(payload: &AnimationsPayload) -> String {
    let mut out = String::from("-- Managed by desktopctl — do not edit\nreturn {\n    beziers = {\n");

    for (name, points) in &payload.beziers {
        out.push_str(&format!(
            "        {{ name = {}, points = {{ {}, {}, {}, {} }} }},\n",
            lua_str(name),
            format_decimal(points[0]),
            format_decimal(points[1]),
            format_decimal(points[2]),
            format_decimal(points[3]),
        ));
    }

    out.push_str("    },\n    animations = {\n");

    for anim in &payload.animations {
        out.push_str(&format!(
            "        {{ name = {}, enabled = {}, speed = {}, curve = {}, style = {} }},\n",
            lua_str(&anim.name),
            anim.enabled,
            format_decimal(anim.speed),
            lua_str(&anim.curve),
            lua_str(&anim.style),
        ));
    }

    out.push_str("    },\n}\n");
    out
}

/// Write animation overrides to the managed config file.
pub(crate) fn save_animations(json: &str) -> Result<()> {
    let payload: AnimationsPayload = serde_json::from_str(json).map_err(|e| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("invalid animations JSON: {e}"),
        )
    })?;

    validate_animations_payload(&payload)?;
    let contents = render_animations_override(&payload);
    theme::atomic_write(&animations_override_path()?, contents.as_bytes())?;
    hyprctl_output(&["reload"])?;
    Ok(())
}

/// Clear all animation overrides and reload Hyprland.
pub(crate) fn clear_animations() -> Result<()> {
    theme::atomic_write(&animations_override_path()?, b"")?;
    hyprctl_output(&["reload"])?;
    Ok(())
}

// ── Keybind override persistence ────────────────────────────────

#[derive(Debug, Deserialize)]
struct KeybindsPayload {
    overrides: Vec<KeybindOverride>,
}

#[derive(Debug, Deserialize)]
struct KeybindOverride {
    original_mods: String,
    original_key: String,
    new_mods: String,
    new_key: String,
    flags: String,
    #[serde(default)]
    description: String,
    dispatcher: String,
    #[serde(default)]
    arg: String,
}

fn keybinds_override_path() -> Result<PathBuf> {
    Ok(paths::xdg_config_home()?.join(KEYBINDS_OVERRIDE_RELATIVE_PATH))
}

fn validate_keybind_flags(flags: &str) -> Result<()> {
    validate_rendered_field("keybind flags", flags)?;
    for flag in flags.chars() {
        if !matches!(
            flag,
            'd' | 'e' | 'i' | 'l' | 'm' | 'n' | 'p' | 'r' | 's' | 't'
        ) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("unsupported Hyprland keybind flag '{flag}'"),
            )
            .into());
        }
    }

    Ok(())
}

fn validate_keybinds_payload(payload: &KeybindsPayload) -> Result<()> {
    for keybind in &payload.overrides {
        validate_rendered_field("original modifiers", &keybind.original_mods)?;
        validate_non_empty_field("original key", &keybind.original_key)?;
        validate_rendered_field("new modifiers", &keybind.new_mods)?;
        validate_non_empty_field("new key", &keybind.new_key)?;
        validate_keybind_flags(&keybind.flags)?;
        if keybind.flags.contains('d') {
            // bindd renders the description as its own field; an empty one
            // would produce a malformed `bindd = MODS, key, , dispatcher, arg`.
            validate_non_empty_field("keybind description", &keybind.description)?;
        } else {
            validate_rendered_field("keybind description", &keybind.description)?;
        }
        validate_non_empty_field("keybind dispatcher", &keybind.dispatcher)?;
        validate_rendered_field("keybind argument", &keybind.arg)?;
    }

    Ok(())
}

fn render_keybinds_override(payload: &KeybindsPayload) -> String {
    let mut out = String::from("-- Managed by desktopctl — do not edit\nreturn {\n");

    for ovr in &payload.overrides {
        out.push_str("    {\n");
        out.push_str(&format!(
            "        original_mods = {}, original_key = {},\n",
            lua_str(&ovr.original_mods),
            lua_str(&ovr.original_key),
        ));
        out.push_str(&format!(
            "        new_mods = {}, new_key = {},\n",
            lua_str(&ovr.new_mods),
            lua_str(&ovr.new_key),
        ));
        out.push_str(&format!(
            "        flags = {}, description = {},\n",
            lua_str(&ovr.flags),
            lua_str(&ovr.description),
        ));
        out.push_str(&format!(
            "        dispatcher = {}, arg = {},\n",
            lua_str(&ovr.dispatcher),
            lua_str(&ovr.arg),
        ));
        out.push_str("    },\n");
    }

    out.push_str("}\n");
    out
}

/// Write keybind overrides to the managed config file.
pub(crate) fn save_keybinds(json: &str) -> Result<()> {
    let payload: KeybindsPayload = serde_json::from_str(json).map_err(|e| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("invalid keybinds JSON: {e}"),
        )
    })?;

    validate_keybinds_payload(&payload)?;
    let contents = render_keybinds_override(&payload);
    theme::atomic_write(&keybinds_override_path()?, contents.as_bytes())?;
    hyprctl_output(&["reload"])?;
    Ok(())
}

/// Clear all keybind overrides and reload Hyprland.
pub(crate) fn clear_keybinds() -> Result<()> {
    theme::atomic_write(&keybinds_override_path()?, b"")?;
    hyprctl_output(&["reload"])?;
    Ok(())
}

fn hyprctl_output(args: &[&str]) -> Result<Output> {
    let output = Command::new("hyprctl").args(args).output()?;
    if output.status.success() {
        return Ok(output);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let mut detail = if stderr.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    if detail.is_empty() {
        detail = "(no output)";
    }
    let message = format!("hyprctl {} failed: {detail}", args.join(" "));

    Err(io::Error::other(message).into())
}

#[cfg(test)]
mod tests {
    use super::{
        AccelProfile, AnimationsPayload, InputSetting, InputState, KeybindsPayload, LidSwitchState,
        MonitorInfo, WorkspaceInfo, WorkspaceRuleInfo, format_decimal, orphaned_pinned_workspaces,
        parse_input_state_from_str, parse_scroll_factor, parse_sensitivity, reclaim_target,
        render_animations_override, render_input_runtime_state, render_keybinds_override,
        validate_animations_payload, validate_keybinds_payload,
    };

    const EXTERNAL_SELECTOR: &str = "desc:BNQ ZOWIE XL LCD EB12M01465SL0";

    fn laptop_panel(active_workspace: i64) -> Vec<MonitorInfo> {
        vec![
            serde_json::from_value(serde_json::json!({
                "name": "eDP-1",
                "description": "LG Display 0x06B3",
                "make": "LG Display",
                "model": "0x06B3",
                "serial": "",
                "focused": true,
                "activeWorkspace": { "id": active_workspace, "name": active_workspace.to_string() },
            }))
            .expect("monitor fixture"),
        ]
    }

    fn external_pins() -> Vec<WorkspaceRuleInfo> {
        (1..=10)
            .map(|id| {
                serde_json::from_value(serde_json::json!({
                    "workspaceString": id.to_string(),
                    "monitor": EXTERNAL_SELECTOR,
                }))
                .expect("rule fixture")
            })
            .collect()
    }

    fn workspace(id: i64, windows: u32) -> WorkspaceInfo {
        serde_json::from_value(serde_json::json!({ "id": id, "windows": windows }))
            .expect("workspace fixture")
    }

    #[test]
    fn desc_selectors_prefix_match_either_description_form() {
        let monitor: MonitorInfo = serde_json::from_value(serde_json::json!({
            "name": "DP-2",
            "description": "BNQ ZOWIE XL LCD EB12M01465SL0",
            "make": "BNQ",
            "model": "ZOWIE XL LCD",
            "serial": "EB12M01465SL0",
        }))
        .expect("monitor fixture");

        assert!(monitor.matches_selector(EXTERNAL_SELECTOR));
        assert!(monitor.matches_selector("desc:BNQ ZOWIE"));
        assert!(monitor.matches_selector("DP-2"));
        assert!(!monitor.matches_selector("desc:LG Display"));
        assert!(!monitor.matches_selector("eDP-1"));
    }

    #[test]
    fn orphaned_pins_cover_only_numbered_rules_whose_monitor_is_absent() {
        let mut rules = external_pins();
        rules.push(
            serde_json::from_value(serde_json::json!({
                "workspaceString": "3",
                "monitor": "eDP-1",
            }))
            .expect("rule fixture"),
        );
        rules.push(
            serde_json::from_value(serde_json::json!({
                "workspaceString": "name:scratch",
                "monitor": EXTERNAL_SELECTOR,
            }))
            .expect("rule fixture"),
        );
        rules.push(
            serde_json::from_value(serde_json::json!({ "workspaceString": "11" }))
                .expect("rule fixture"),
        );

        // Workspace 3 is pinned to the connected panel too, so it stays reachable.
        assert_eq!(
            orphaned_pinned_workspaces(&laptop_panel(11), &rules),
            vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        );
    }

    #[test]
    fn a_panel_parked_past_the_pinned_block_is_pulled_back_to_the_first_pin() {
        assert_eq!(
            reclaim_target(&laptop_panel(11), &external_pins(), &[workspace(11, 0)]),
            Some(1),
        );
    }

    #[test]
    fn reclaim_leaves_reachable_and_occupied_workspaces_alone() {
        // Inside the pinned block: the user can already see and reach it.
        assert_eq!(
            reclaim_target(&laptop_panel(2), &external_pins(), &[workspace(2, 1)]),
            None,
        );
        // Parked past the block but holding windows: moving away would strand them.
        assert_eq!(
            reclaim_target(&laptop_panel(11), &external_pins(), &[workspace(11, 2)]),
            None,
        );
        // No orphaned pins at all, which is every host without monitor-pinned rules.
        assert_eq!(reclaim_target(&laptop_panel(11), &[], &[]), None);
    }

    #[test]
    fn reclaim_does_not_steal_a_workspace_another_output_is_showing() {
        let mut monitors = laptop_panel(11);
        monitors.push(
            serde_json::from_value(serde_json::json!({
                "name": "HDMI-A-1",
                "description": "Some Other Display",
                "activeWorkspace": { "id": 1, "name": "1" },
            }))
            .expect("monitor fixture"),
        );

        assert_eq!(
            reclaim_target(&monitors, &external_pins(), &[workspace(11, 0)]),
            None,
        );
    }

    #[test]
    fn parse_input_state_reads_managed_keys_from_a_lua_table() {
        let mut state = InputState::default();
        parse_input_state_from_str(
            r#"
-- Generated by desktopctl - do not edit
return {
    kb_layout = "us",
    sensitivity = 0.5,
    accel_profile = "adaptive",
    scroll_factor = 1.5,
}
"#,
            &mut state,
        );

        assert_eq!(state.sensitivity, 0.5);
        assert_eq!(state.accel_profile, AccelProfile::Adaptive);
        assert_eq!(state.scroll_factor, 1.5);
    }

    #[test]
    fn parse_input_state_ignores_comments_and_unmanaged_keys() {
        let mut state = InputState::default();
        parse_input_state_from_str(
            r#"
return {
    -- sensitivity = 0.1
    follow_mouse = 1,
    accel_profile = "flat",
}
"#,
            &mut state,
        );

        assert_eq!(state.accel_profile, AccelProfile::Flat);
        assert_eq!(state.sensitivity, InputState::default().sensitivity);
    }

    #[test]
    fn input_runtime_state_round_trips_through_the_rendered_table() {
        let rendered = render_input_runtime_state(&InputState {
            sensitivity: 0.755,
            accel_profile: AccelProfile::Flat,
            scroll_factor: 1.0,
        });

        assert!(rendered.contains("sensitivity = 0.76"));
        assert!(rendered.contains("accel_profile = \"flat\""));
        assert!(rendered.contains("scroll_factor = 1.0"));

        let mut state = InputState::default();
        parse_input_state_from_str(&rendered, &mut state);
        assert_eq!(state.sensitivity, 0.76);
        assert_eq!(state.accel_profile, AccelProfile::Flat);
        assert_eq!(state.scroll_factor, 1.0);
    }

    #[test]
    fn parse_input_value_helpers_validate_and_round() {
        assert_eq!(parse_sensitivity("0.755").expect("valid sensitivity"), 0.76);
        assert!(parse_sensitivity("1.5").is_err());
        assert!(parse_sensitivity("nan").is_err());

        assert_eq!(
            parse_scroll_factor("1.234").expect("valid scroll factor"),
            1.23
        );
        assert!(parse_scroll_factor("0").is_err());
        assert!(parse_scroll_factor("inf").is_err());
    }

    #[test]
    fn input_setting_parser_and_decimal_formatter_match_cli_output() {
        assert_eq!(
            InputSetting::parse(" scroll_factor ").expect("setting should parse"),
            InputSetting::ScrollFactor
        );
        assert!(InputSetting::parse("unknown").is_err());

        assert_eq!(format_decimal(1.0), "1.0");
        assert_eq!(format_decimal(0.755), "0.76");
        assert_eq!(format_decimal(-0.5), "-0.5");
    }

    #[test]
    fn lid_switch_state_parser_accepts_supported_states() {
        assert_eq!(
            LidSwitchState::parse("open").expect("open should parse"),
            LidSwitchState::Open
        );
        assert_eq!(
            LidSwitchState::parse("closed").expect("closed should parse"),
            LidSwitchState::Closed
        );
        assert_eq!(
            LidSwitchState::parse("sync").expect("sync should parse"),
            LidSwitchState::Sync
        );
        assert!(LidSwitchState::parse("half-open").is_err());
    }

    #[test]
    fn render_animations_override_produces_valid_hyprland_config() {
        let payload: AnimationsPayload = serde_json::from_str(
            r#"{
                "beziers": {
                    "custom1": [0.3, 0.5, 0.7, 1.0],
                    "myBezier": [0.05, 0.9, 0.1, 1.05]
                },
                "animations": [
                    {"name": "windows", "enabled": true, "speed": 6.0, "curve": "custom1", "style": ""},
                    {"name": "windowsOut", "enabled": true, "speed": 4.0, "curve": "myBezier", "style": "popin 80%"}
                ]
            }"#,
        )
        .expect("payload should parse");

        let rendered = render_animations_override(&payload);
        assert!(rendered.starts_with("-- Managed by desktopctl"));
        assert!(rendered.contains(r#"{ name = "custom1", points = { 0.3, 0.5, 0.7, 1.0 } }"#));
        assert!(rendered.contains(r#"{ name = "myBezier", points = { 0.05, 0.9, 0.1, 1.05 } }"#));
        assert!(rendered.contains(
            r#"{ name = "windows", enabled = true, speed = 6.0, curve = "custom1", style = "" }"#
        ));
        assert!(rendered.contains(
            r#"{ name = "windowsOut", enabled = true, speed = 4.0, curve = "myBezier", style = "popin 80%" }"#
        ));
    }

    #[test]
    fn render_animations_override_disabled_animation() {
        let payload: AnimationsPayload = serde_json::from_str(
            r#"{"beziers": {}, "animations": [{"name": "fade", "enabled": false, "speed": 4.0, "curve": "default", "style": ""}]}"#,
        )
        .expect("payload should parse");

        let rendered = render_animations_override(&payload);
        assert!(rendered.contains(
            r#"{ name = "fade", enabled = false, speed = 4.0, curve = "default", style = "" }"#
        ));
    }

    #[test]
    fn validate_animations_rejects_injected_lines_and_non_finite_numbers() {
        let payload: AnimationsPayload =
            serde_json::from_str(r#"{"beziers":{"bad\nname":[0.0,0.0,1.0,1.0]},"animations":[]}"#)
                .expect("payload should parse");
        assert!(validate_animations_payload(&payload).is_err());

        let payload = AnimationsPayload {
            beziers: std::collections::BTreeMap::from([(
                "custom".to_owned(),
                [0.0, f64::NAN, 1.0, 1.0],
            )]),
            animations: Vec::new(),
        };
        assert!(validate_animations_payload(&payload).is_err());
    }

    #[test]
    fn render_keybinds_override_produces_unbind_rebind_pairs() {
        let payload: KeybindsPayload = serde_json::from_str(
            r#"{
                "overrides": [{
                    "original_mods": "SUPER",
                    "original_key": "Q",
                    "new_mods": "SUPER SHIFT",
                    "new_key": "Q",
                    "flags": "d",
                    "description": "Open terminal",
                    "dispatcher": "exec",
                    "arg": "alacritty"
                }]
            }"#,
        )
        .expect("payload should parse");

        let rendered = render_keybinds_override(&payload);
        assert!(rendered.starts_with("-- Managed by desktopctl"));
        assert!(rendered.contains(r#"original_mods = "SUPER", original_key = "Q","#));
        assert!(rendered.contains(r#"new_mods = "SUPER SHIFT", new_key = "Q","#));
        assert!(rendered.contains(r#"flags = "d", description = "Open terminal","#));
        assert!(rendered.contains(r#"dispatcher = "exec", arg = "alacritty","#));
    }

    #[test]
    fn render_keybinds_override_mouse_bind_without_description() {
        let payload: KeybindsPayload = serde_json::from_str(
            r#"{
                "overrides": [{
                    "original_mods": "SUPER",
                    "original_key": "mouse:272",
                    "new_mods": "SUPER ALT",
                    "new_key": "mouse:272",
                    "flags": "m",
                    "dispatcher": "movewindow",
                    "arg": ""
                }]
            }"#,
        )
        .expect("payload should parse");

        let rendered = render_keybinds_override(&payload);
        assert!(rendered.contains(r#"original_mods = "SUPER", original_key = "mouse:272","#));
        assert!(rendered.contains(r#"new_mods = "SUPER ALT", new_key = "mouse:272","#));
        assert!(rendered.contains(r#"flags = "m", description = "","#));
        assert!(rendered.contains(r#"dispatcher = "movewindow", arg = "","#));
    }

    #[test]
    fn validate_keybinds_rejects_injected_lines_and_unknown_flags() {
        let payload: KeybindsPayload = serde_json::from_str(
            r#"{
                "overrides": [{
                    "original_mods": "SUPER",
                    "original_key": "Q\nunbind = SUPER, Return",
                    "new_mods": "SUPER",
                    "new_key": "Q",
                    "flags": "d",
                    "description": "Open terminal",
                    "dispatcher": "exec",
                    "arg": "alacritty"
                }]
            }"#,
        )
        .expect("payload should parse");
        assert!(validate_keybinds_payload(&payload).is_err());

        let payload: KeybindsPayload = serde_json::from_str(
            r#"{
                "overrides": [{
                    "original_mods": "SUPER",
                    "original_key": "Q",
                    "new_mods": "SUPER",
                    "new_key": "Q",
                    "flags": "=",
                    "description": "Open terminal",
                    "dispatcher": "exec",
                    "arg": "alacritty"
                }]
            }"#,
        )
        .expect("payload should parse");
        assert!(validate_keybinds_payload(&payload).is_err());
    }

    #[test]
    fn validate_keybinds_requires_a_description_for_the_d_flag() {
        let payload: KeybindsPayload = serde_json::from_str(
            r#"{
                "overrides": [{
                    "original_mods": "SUPER",
                    "original_key": "Q",
                    "new_mods": "SUPER",
                    "new_key": "Q",
                    "flags": "d",
                    "description": "",
                    "dispatcher": "exec",
                    "arg": "alacritty"
                }]
            }"#,
        )
        .expect("payload should parse");
        assert!(validate_keybinds_payload(&payload).is_err());
    }
}
