use crate::{paths, theme};
use serde::{Deserialize, Serialize};
use std::{
    env, fs, io,
    path::{Path, PathBuf},
    process::{Command, Output},
    time::{SystemTime, UNIX_EPOCH},
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

const INPUT_CONF_RELATIVE_PATH: &str = "hypr/input.conf";
const INPUT_RUNTIME_RELATIVE_PATH: &str = "hypr/input-runtime.conf";
const ANIMATIONS_OVERRIDE_RELATIVE_PATH: &str = "hypr/animations-override.conf";
const KEYBINDS_OVERRIDE_RELATIVE_PATH: &str = "hypr/keybinds-override.conf";

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

/// Return the Hyprland event-socket path used by the focus daemon.
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

fn parse_input_state_from_str(contents: &str, state: &mut InputState) {
    let mut block_stack: Vec<&str> = Vec::new();

    for raw_line in contents.lines() {
        let line = raw_line.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }

        if let Some(prefix) = line.strip_suffix('{') {
            block_stack.push(prefix.trim());
            continue;
        }

        if line == "}" {
            let _ = block_stack.pop();
            continue;
        }

        if block_stack.as_slice() != ["input"] {
            continue;
        }

        let Some((key, value)) = line.split_once('=') else {
            continue;
        };

        match key.trim() {
            "sensitivity" => {
                if let Ok(parsed) = value.trim().parse::<f64>() {
                    state.sensitivity = parsed;
                }
            }
            "accel_profile" => {
                if let Some(parsed) = AccelProfile::parse(value) {
                    state.accel_profile = parsed;
                }
            }
            "scroll_factor" => {
                if let Ok(parsed) = value.trim().parse::<f64>()
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
        "# Generated by desktopctl - do not edit\ninput {{\n    sensitivity = {}\n    accel_profile = {}\n    scroll_factor = {}\n}}\n",
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

fn render_animations_override(payload: &AnimationsPayload) -> String {
    let mut out = String::from("# Managed by desktopctl — do not edit\nanimations {\n");

    for (name, points) in &payload.beziers {
        out.push_str(&format!(
            "    bezier = {}, {}, {}, {}, {}\n",
            name,
            format_decimal(points[0]),
            format_decimal(points[1]),
            format_decimal(points[2]),
            format_decimal(points[3]),
        ));
    }

    if !payload.beziers.is_empty() && !payload.animations.is_empty() {
        out.push('\n');
    }

    for anim in &payload.animations {
        let enabled = if anim.enabled { "1" } else { "0" };
        let speed = format_decimal(anim.speed);
        if anim.style.is_empty() {
            out.push_str(&format!(
                "    animation = {}, {}, {}, {}\n",
                anim.name, enabled, speed, anim.curve,
            ));
        } else {
            out.push_str(&format!(
                "    animation = {}, {}, {}, {}, {}\n",
                anim.name, enabled, speed, anim.curve, anim.style,
            ));
        }
    }

    out.push_str("}\n");
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
        validate_rendered_field("keybind description", &keybind.description)?;
        validate_non_empty_field("keybind dispatcher", &keybind.dispatcher)?;
        validate_rendered_field("keybind argument", &keybind.arg)?;
    }

    Ok(())
}

fn render_keybinds_override(payload: &KeybindsPayload) -> String {
    let mut out = String::from("# Managed by desktopctl — do not edit\n");

    for ovr in &payload.overrides {
        out.push_str(&format!(
            "unbind = {}, {}\n",
            ovr.original_mods, ovr.original_key
        ));

        let bind_keyword = format!("bind{}", ovr.flags);
        let has_desc = ovr.flags.contains('d');

        if has_desc {
            out.push_str(&format!(
                "{} = {}, {}, {}, {}, {}\n\n",
                bind_keyword, ovr.new_mods, ovr.new_key, ovr.description, ovr.dispatcher, ovr.arg,
            ));
        } else {
            out.push_str(&format!(
                "{} = {}, {}, {}, {}\n\n",
                bind_keyword, ovr.new_mods, ovr.new_key, ovr.dispatcher, ovr.arg,
            ));
        }
    }

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
    let detail = if stderr.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    let message = format!(
        "hyprctl {} failed: {}",
        args.join(" "),
        detail.if_empty("(no output)")
    );

    Err(io::Error::other(message).into())
}

trait IfEmpty {
    fn if_empty(self, fallback: &str) -> String;
}

impl IfEmpty for &str {
    fn if_empty(self, fallback: &str) -> String {
        if self.is_empty() {
            fallback.to_owned()
        } else {
            self.to_owned()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AccelProfile, AnimationsPayload, InputSetting, InputState, KeybindsPayload, format_decimal,
        parse_input_state_from_str, parse_scroll_factor, parse_sensitivity,
        render_animations_override, render_input_runtime_state, render_keybinds_override,
        validate_animations_payload, validate_keybinds_payload,
    };

    #[test]
    fn parse_input_state_only_reads_top_level_input_keys() {
        let mut state = InputState::default();
        parse_input_state_from_str(
            r#"
input {
    sensitivity = 0.5
    touchpad {
        scroll_factor = 0.25
    }
    accel_profile = adaptive
    scroll_factor = 1.5
}
"#,
            &mut state,
        );

        assert_eq!(state.sensitivity, 0.5);
        assert_eq!(state.accel_profile, AccelProfile::Adaptive);
        assert_eq!(state.scroll_factor, 1.5);
    }

    #[test]
    fn render_input_runtime_state_keeps_managed_keys_and_rounding() {
        let rendered = render_input_runtime_state(&InputState {
            sensitivity: 0.755,
            accel_profile: AccelProfile::Flat,
            scroll_factor: 1.0,
        });

        assert!(rendered.contains("sensitivity = 0.76"));
        assert!(rendered.contains("accel_profile = flat"));
        assert!(rendered.contains("scroll_factor = 1.0"));
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
        assert!(rendered.starts_with("# Managed by desktopctl"));
        assert!(rendered.contains("bezier = custom1, 0.3, 0.5, 0.7, 1.0"));
        assert!(rendered.contains("bezier = myBezier, 0.05, 0.9, 0.1, 1.05"));
        assert!(rendered.contains("animation = windows, 1, 6.0, custom1"));
        assert!(rendered.contains("animation = windowsOut, 1, 4.0, myBezier, popin 80%"));
    }

    #[test]
    fn render_animations_override_disabled_animation() {
        let payload: AnimationsPayload = serde_json::from_str(
            r#"{"beziers": {}, "animations": [{"name": "fade", "enabled": false, "speed": 4.0, "curve": "default", "style": ""}]}"#,
        )
        .expect("payload should parse");

        let rendered = render_animations_override(&payload);
        assert!(rendered.contains("animation = fade, 0, 4.0, default"));
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
        assert!(rendered.contains("unbind = SUPER, Q"));
        assert!(rendered.contains("bindd = SUPER SHIFT, Q, Open terminal, exec, alacritty"));
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
        assert!(rendered.contains("unbind = SUPER, mouse:272"));
        assert!(rendered.contains("bindm = SUPER ALT, mouse:272, movewindow, "));
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
}
