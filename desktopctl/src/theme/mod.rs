use crate::paths;
use serde_json::{Map, Value};
use std::io::Write;
use std::{
    fs::{self, OpenOptions},
    io,
    path::{Path, PathBuf},
    process,
    time::{SystemTime, UNIX_EPOCH},
};

pub mod color;
mod command;
pub mod json;
pub mod orchestrator;
pub mod resolve;
pub mod schema;
pub mod targets;
pub mod wallpaper_browser;

enum CliFailure {
    Message(String),
    Reported,
}

type CliResult<T> = Result<T, CliFailure>;

struct StateUpdateOutcome {
    changed: bool,
    value: Value,
    new_state: schema::ThemeState,
    affected_targets: std::collections::BTreeSet<String>,
}

pub fn run(args: crate::ThemeArgs) -> crate::Result<()> {
    match run_cli(args) {
        Ok(()) => Ok(()),
        Err(CliFailure::Message(message)) => Err(io::Error::other(message).into()),
        Err(CliFailure::Reported) => Err(io::Error::other("").into()),
    }
}

/// Who initiated a dark_hint write. Manual writes win until the next
/// 23:00/06:00 schedule edge; the daemon's boot catch-up skips the schedule
/// value while the recorded manual write falls inside the current window.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DarkHintOrigin {
    Manual,
    Scheduled,
}

/// theme_state row recording when a manual dark_hint write last happened.
/// Rides the schema's unknown-key passthrough (`ThemeState.extra`).
pub(crate) const DARK_HINT_MANUAL_AT_KEY: &str = "dark_hint_manual_at";

fn set_dark_hint_internal(enabled: bool, origin: DarkHintOrigin) -> crate::Result<bool> {
    let outcome = set_state_key_internal("dark_hint", Value::Bool(enabled))?;
    let manual_at = Value::String(manual_write_timestamp());
    if !outcome.changed {
        if origin == DarkHintOrigin::Manual {
            resolve::save_state_keys(&[(DARK_HINT_MANUAL_AT_KEY, &manual_at)])?;
        }
        return Ok(false);
    }

    let colors_dir = resolve::colors_dir()?;
    let colors = resolve::load_colors(&outcome.new_state.color_scheme, &colors_dir)?;
    orchestrator::apply(
        outcome.affected_targets.iter(),
        &colors,
        &outcome.new_state,
        true,
    )
    .into_result()
    .map_err(|error| {
        io::Error::other(format!(
            "failed to apply affected theme targets for dark_hint: {error}"
        ))
    })?;
    let mut pairs = vec![("dark_hint", &outcome.value)];
    if origin == DarkHintOrigin::Manual {
        pairs.push((DARK_HINT_MANUAL_AT_KEY, &manual_at));
    }
    resolve::save_state_keys(&pairs)?;
    Ok(true)
}

fn manual_write_timestamp() -> String {
    chrono::Local::now().to_rfc3339()
}

pub(crate) fn expand_user_path(path: &str) -> crate::Result<PathBuf> {
    if path == "~" {
        return Ok(paths::home_dir()?);
    }

    if let Some(rest) = path.strip_prefix("~/") {
        return Ok(paths::home_dir()?.join(rest));
    }

    Ok(PathBuf::from(path))
}

pub(crate) fn atomic_write(path: &Path, content: &[u8]) -> crate::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let existing_permissions = fs::metadata(path)
        .ok()
        .map(|metadata| metadata.permissions());
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("output");
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let mut last_exists_error = None;

    for attempt in 0..16 {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let temp_path = parent.join(format!(
            ".{file_name}.desktopctl-{}-{nanos}-{attempt}.tmp",
            process::id()
        ));

        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp_path)
        {
            Ok(mut file) => {
                if let Some(permissions) = &existing_permissions {
                    file.set_permissions(permissions.clone())?;
                }

                if let Err(error) = (|| -> io::Result<()> {
                    file.write_all(content)?;
                    file.sync_all()?;
                    Ok(())
                })() {
                    let _ = fs::remove_file(&temp_path);
                    return Err(error.into());
                }

                if let Err(error) = fs::rename(&temp_path, path) {
                    let _ = fs::remove_file(&temp_path);
                    return Err(error.into());
                }

                return Ok(());
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                last_exists_error = Some(error);
            }
            Err(error) => return Err(error.into()),
        }
    }

    Err(last_exists_error
        .unwrap_or_else(|| io::Error::other("failed to allocate a temporary file"))
        .into())
}

/// Atomically replace `link_path` with a symlink to `target` (symlink under a
/// temporary name, then rename over the destination) so live consumers never
/// observe a missing file.
pub(crate) fn replace_with_symlink(link_path: &Path, target: &Path) -> crate::Result<()> {
    use std::os::unix::fs::symlink;

    let parent = link_path.parent().unwrap_or_else(|| Path::new("."));
    let file_name = link_path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("link");
    let mut last_exists_error = None;

    for attempt in 0..16 {
        let temp_path = parent.join(format!(
            ".{file_name}.desktopctl-{}-{attempt}.tmp",
            process::id()
        ));
        match symlink(target, &temp_path) {
            Ok(()) => {
                if let Err(error) = fs::rename(&temp_path, link_path) {
                    let _ = fs::remove_file(&temp_path);
                    return Err(error.into());
                }
                return Ok(());
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                last_exists_error = Some(error);
            }
            Err(error) => return Err(error.into()),
        }
    }

    Err(last_exists_error
        .unwrap_or_else(|| io::Error::other("failed to allocate a temporary symlink"))
        .into())
}

/// 64-bit FNV-1a fingerprint shared by cache-key derivation (wallpaper
/// previews, lutgen output). Not cryptographic; cache keys do not need to be.
pub(crate) fn fnv1a_fingerprint(text: &str) -> String {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in text.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

// Writes go through the daemon, the single writer; `sync` is the exception (activation has no session).
fn run_cli(args: crate::ThemeArgs) -> CliResult<()> {
    match args.command {
        crate::ThemeCommand::All(wait) => remote_apply("all", None, wait.wait_daemon),
        crate::ThemeCommand::Sync => cmd_sync(),
        crate::ThemeCommand::Colors(wait) => remote_apply("colors", None, wait.wait_daemon),
        crate::ThemeCommand::Wallpaper(wait) => remote_apply("wallpaper", None, wait.wait_daemon),
        crate::ThemeCommand::Cursor(wait) => remote_apply("cursor", None, wait.wait_daemon),
        crate::ThemeCommand::Fonts(wait) => remote_apply("fonts", None, wait.wait_daemon),
        crate::ThemeCommand::Target(args) => {
            remote_apply("target", Some(args.name), args.wait.wait_daemon)
        }
        crate::ThemeCommand::Set(args) => remote_set(args),
        crate::ThemeCommand::Preset(args) => remote_preset_apply(args),
        crate::ThemeCommand::SavePreset(args) => remote_preset_save(args),
        crate::ThemeCommand::DeletePreset(args) => remote_preset_delete(args),
        crate::ThemeCommand::ListSchemes => cmd_list_schemes(),
        crate::ThemeCommand::ListWallpapers(args) => cmd_list_wallpapers(args),
        crate::ThemeCommand::ListPresets => cmd_list_presets(),
        crate::ThemeCommand::Status(args) => cmd_status(args.json),
        crate::ThemeCommand::Export => cmd_export(),
    }
}

fn remote_request<P: serde::Serialize + Clone>(
    method: &str,
    params: Option<P>,
    wait_secs: u64,
    timeout: std::time::Duration,
) -> CliResult<Value> {
    let result = if wait_secs > 0 {
        crate::ipc::send_request_with_retry(
            method,
            params,
            timeout,
            std::time::Duration::from_secs(wait_secs),
        )
    } else {
        crate::ipc::send_request(method, params, timeout)
    };

    result.map_err(|error| {
        if crate::ipc::socket_unavailable(error.as_ref()) {
            CliFailure::Message(crate::ipc::daemon_unavailable_message(&error))
        } else {
            CliFailure::from_error(error)
        }
    })
}

fn remote_apply(scope: &str, target: Option<String>, wait_secs: u64) -> CliResult<()> {
    let params = serde_json::json!({ "scope": scope, "target": target });
    let report = remote_request(
        crate::ipc::methods::THEME_APPLY,
        Some(params),
        wait_secs,
        crate::ipc::APPLY_TIMEOUT,
    )?;

    finish_apply(serde_json::from_value(report).map_err(CliFailure::from_error)?)
}

fn finish_apply(report: orchestrator::ApplyReport) -> CliResult<()> {
    report.print();
    if report.ok() {
        Ok(())
    } else {
        Err(CliFailure::Reported)
    }
}

fn remote_set(args: crate::SetArgs) -> CliResult<()> {
    let params = serde_json::json!({ "key": args.key, "value": args.value });
    let response = remote_request(
        crate::ipc::methods::THEME_SET,
        Some(params),
        args.wait.wait_daemon,
        crate::ipc::APPLY_TIMEOUT,
    )?;

    let committed = response["state"][&args.key].clone();
    if response["changed"].as_bool() == Some(false) {
        println!(
            "{} is already '{}', nothing to do.",
            args.key,
            display_value(&committed)
        );
    } else {
        println!("Set {} = {}", args.key, committed);
    }
    Ok(())
}

fn remote_preset_apply(args: crate::NamedArg) -> CliResult<()> {
    let params = serde_json::json!({ "name": args.name });
    remote_request(
        crate::ipc::methods::THEME_PRESET_APPLY,
        Some(params),
        args.wait.wait_daemon,
        crate::ipc::APPLY_TIMEOUT,
    )?;
    println!("Loaded preset '{}'.", args.name);
    Ok(())
}

fn remote_preset_save(args: crate::SavePresetArgs) -> CliResult<()> {
    let payload = map_user_err(parse_json_value(&args.payload))?;
    let params = serde_json::json!({ "name": args.name, "payload": payload });
    let response = remote_request(
        crate::ipc::methods::THEME_PRESET_SAVE,
        Some(params),
        args.wait.wait_daemon,
        crate::ipc::DEFAULT_TIMEOUT,
    )?;

    let count = response["fields"].as_u64().unwrap_or(0);
    let noun = if count == 1 { "field" } else { "fields" };
    println!("Saved preset '{}' ({} {}).", args.name, count, noun);
    Ok(())
}

fn remote_preset_delete(args: crate::NamedArg) -> CliResult<()> {
    let params = serde_json::json!({ "name": args.name });
    remote_request(
        crate::ipc::methods::THEME_PRESET_DELETE,
        Some(params),
        args.wait.wait_daemon,
        crate::ipc::DEFAULT_TIMEOUT,
    )?;
    println!("Deleted preset '{}'.", args.name);
    Ok(())
}

fn cmd_sync() -> CliResult<()> {
    let (state, colors) = load_state_and_colors()?;
    println!(
        "Syncing theme-managed config ({}-{})...",
        colors.family, colors.variant
    );
    finish_apply(orchestrator::apply_all(&colors, &state, false, true))
}

fn cmd_list_schemes() -> CliResult<()> {
    let colors_dir = map_user_err(resolve::colors_dir())?;
    let schemes = map_user_err(json_file_stems_by_filename(&colors_dir))?;
    if schemes.is_empty() {
        println!("No color schemes found.");
        return Ok(());
    }
    for scheme in schemes {
        println!("{}", colors_dir.join(format!("{scheme}.json")).display());
    }
    Ok(())
}

fn cmd_list_presets() -> CliResult<()> {
    let presets_dir = map_user_err(presets_dir())?;
    let presets = map_user_err(json_file_stems_by_filename(&presets_dir))?;
    if presets.is_empty() {
        println!("No presets found.");
        return Ok(());
    }
    for preset in presets {
        println!("  {preset}");
    }
    Ok(())
}

fn cmd_list_wallpapers(args: crate::ListWallpapersArgs) -> CliResult<()> {
    let directory = if let Some(path) = args.directory.as_deref() {
        map_user_err(expand_user_path(path))?
    } else {
        let state = map_user_err(resolve::load_state())?;
        let current = PathBuf::from(state.wallpaper);
        match current.parent() {
            Some(parent) => parent.to_path_buf(),
            None => map_user_err(paths::repo_path("styling/wallpapers"))?,
        }
    };

    let items = map_user_err(wallpaper_browser::list_wallpapers(&directory))?;

    if !args.json {
        if items.is_empty() {
            println!("No wallpapers found.");
            return Ok(());
        }

        for item in items {
            println!("  {}", item.name);
        }
        return Ok(());
    }

    print_json_value(&wallpaper_browser::json_value(&items));
    Ok(())
}

// Daemon first for a consistent snapshot; the DB directly when it is dead.
fn read_state_map() -> CliResult<Value> {
    match crate::ipc::send_request::<(), Value>(
        crate::ipc::methods::THEME_STATUS,
        None,
        crate::ipc::DEFAULT_TIMEOUT,
    ) {
        Ok(value) => Ok(value),
        Err(error) if crate::ipc::socket_unavailable(error.as_ref()) => {
            Ok(state_json(&map_user_err(resolve::load_state())?))
        }
        Err(error) => Err(CliFailure::from_error(error)),
    }
}

/// Print the current state in seed format, for committing as `styling/state.json`.
fn cmd_export() -> CliResult<()> {
    let Value::Object(state_map) = read_state_map()? else {
        return Err(CliFailure::Message(
            "theme state did not deserialize to an object".to_owned(),
        ));
    };

    println!(
        "{}",
        json::format_pretty_value(&Value::Object(schema::seed_json_map(&state_map)))
    );
    Ok(())
}

fn cmd_status(json_output: bool) -> CliResult<()> {
    let state_map = read_state_map()?;

    if json_output {
        println!("{}", json::format_pretty_value(&state_map));
        return Ok(());
    }

    for key in schema::ThemeState::known_field_names() {
        if let Some(value) = state_map.get(*key) {
            println!("  {}: {}", key, display_value(value));
        }
    }
    Ok(())
}

// ── Daemon cores: state persists only after the apply succeeds ──────────────

#[derive(Debug, Clone)]
pub(crate) enum ApplyScope {
    All,
    Colors,
    Wallpaper,
    Cursor,
    Fonts,
    Target(String),
}

impl ApplyScope {
    pub(crate) fn parse(scope: &str, target: Option<String>) -> crate::Result<Self> {
        match scope {
            "all" => Ok(Self::All),
            "colors" => Ok(Self::Colors),
            "wallpaper" => Ok(Self::Wallpaper),
            "cursor" => Ok(Self::Cursor),
            "fonts" => Ok(Self::Fonts),
            "target" => target.map(Self::Target).ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "apply scope 'target' requires a target name",
                )
                .into()
            }),
            other => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("unknown apply scope '{other}'"),
            )
            .into()),
        }
    }
}

pub(crate) struct SetKeyOutcome {
    pub changed: bool,
    pub state: schema::ThemeState,
}

pub(crate) struct PresetOutcome {
    pub state: schema::ThemeState,
    pub changed_keys: Vec<String>,
}

pub(crate) fn state_json(state: &schema::ThemeState) -> Value {
    Value::Object(state.to_ordered_json_map())
}

pub(crate) fn set_theme_key_core(
    key: &str,
    raw_value: Value,
    origin: DarkHintOrigin,
) -> crate::Result<SetKeyOutcome> {
    if key == "dark_hint" {
        let enabled = match coerce_theme_value(key, raw_value)? {
            Value::Bool(enabled) => enabled,
            _ => unreachable!("dark_hint is validated as a bool"),
        };
        let changed = set_dark_hint_internal(enabled, origin)?;
        return Ok(SetKeyOutcome {
            changed,
            state: resolve::load_state()?,
        });
    }

    let outcome = set_state_key_internal(key, raw_value)?;
    if !outcome.changed {
        return Ok(SetKeyOutcome {
            changed: false,
            state: outcome.new_state,
        });
    }

    let colors_dir = resolve::colors_dir()?;
    let colors = resolve::load_colors(&outcome.new_state.color_scheme, &colors_dir)?;
    orchestrator::apply(
        outcome.affected_targets.iter(),
        &colors,
        &outcome.new_state,
        true,
    )
    .into_result()?;
    resolve::save_state_keys(&[(key, &outcome.value)])?;
    Ok(SetKeyOutcome {
        changed: true,
        state: outcome.new_state,
    })
}

pub(crate) fn apply_scope_core(scope: &ApplyScope) -> crate::Result<orchestrator::ApplyReport> {
    let colors_dir = resolve::colors_dir()?;
    let state = resolve::load_state()?;
    let colors = resolve::load_colors(&state.color_scheme, &colors_dir)?;
    let run = |names: Vec<&str>| orchestrator::apply(names, &colors, &state, true);

    Ok(match scope {
        ApplyScope::All => orchestrator::apply_all(&colors, &state, true, false),
        ApplyScope::Colors => {
            orchestrator::apply(orchestrator::color_targets(&state), &colors, &state, true)
        }
        ApplyScope::Wallpaper => run(vec!["wallpaper"]),
        ApplyScope::Cursor => run(vec!["cursor"]),
        ApplyScope::Fonts => {
            orchestrator::apply(orchestrator::font_targets(), &colors, &state, true)
        }
        ApplyScope::Target(name) => run(vec![name.as_str()]),
    })
}

/// Apply a preset in a single pass: merge every preset key, dark_hint included,
/// into one snapshot, apply the targets those keys feed, then persist them together.
pub(crate) fn apply_preset_core(name: &str) -> crate::Result<PresetOutcome> {
    let (preset_name, preset_path) = preset_path(name)?;
    if !preset_path.is_file() {
        let available = available_presets()?;
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!(
                "preset '{}' not found. Available: {}",
                preset_name,
                if available.is_empty() {
                    "(none)".to_owned()
                } else {
                    available.join(", ")
                }
            ),
        )
        .into());
    }

    let preset_value = read_json_file(&preset_path)?;
    let preset = normalize_theme_patch(preset_value, &format!("preset '{}'", preset_name))?;
    if preset.is_empty() {
        return Ok(PresetOutcome {
            state: resolve::load_state()?,
            changed_keys: Vec::new(),
        });
    }

    let state = resolve::load_state()?;
    let mut state_map = state.to_ordered_json_map();
    for (key, value) in &preset {
        state_map.insert(key.clone(), value.clone());
    }
    let new_state = validated_theme_state(state_map, "theme state")?;

    let colors_dir = resolve::colors_dir()?;
    let colors = resolve::load_colors(&new_state.color_scheme, &colors_dir)?;
    let affected =
        orchestrator::targets_for_keys(preset.keys().map(String::as_str), Some(&new_state));
    orchestrator::apply(affected, &colors, &new_state, true).into_result()?;

    let manual_at = Value::String(manual_write_timestamp());
    let mut pairs = preset
        .iter()
        .map(|(key, value)| (key.as_str(), value))
        .collect::<Vec<_>>();
    // A preset's dark_hint is a manual write.
    if preset.contains_key("dark_hint") {
        pairs.push((DARK_HINT_MANUAL_AT_KEY, &manual_at));
    }
    resolve::save_state_keys(&pairs)?;

    Ok(PresetOutcome {
        state: new_state,
        changed_keys: preset.keys().cloned().collect(),
    })
}

pub(crate) fn save_preset_core(name: &str, payload: Value) -> crate::Result<usize> {
    let (preset_name, preset_path) = preset_path(name)?;
    let preset = normalize_theme_patch(payload, &format!("preset '{}'", preset_name))?;

    if preset.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "preset must include at least one field",
        )
        .into());
    }

    if let Some(parent) = preset_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let ordered = ordered_theme_mapping(&preset);
    let rendered = format!("{}\n", json::format_pretty_value(&Value::Object(ordered)));
    atomic_write(&preset_path, rendered.as_bytes())?;
    Ok(preset.len())
}

pub(crate) fn delete_preset_core(name: &str) -> crate::Result<String> {
    let (preset_name, preset_path) = preset_path(name)?;
    if !preset_path.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("preset '{}' not found", preset_name),
        )
        .into());
    }

    fs::remove_file(&preset_path)?;
    Ok(preset_name)
}

pub(crate) fn preset_names() -> crate::Result<Vec<String>> {
    available_presets()
}

fn load_state_and_colors() -> CliResult<(schema::ThemeState, schema::ColorScheme)> {
    let colors_dir = map_user_err(resolve::colors_dir())?;
    let state = map_user_err(resolve::load_state())?;
    let colors = map_user_err(resolve::load_colors(&state.color_scheme, &colors_dir))?;
    Ok((state, colors))
}

fn set_state_key_internal(key: &str, raw_value: Value) -> crate::Result<StateUpdateOutcome> {
    let state = resolve::load_state()?;
    let mut state_map = state.to_ordered_json_map();
    let value = coerce_theme_value(key, raw_value)?;

    let current = state_map
        .get(key)
        .cloned()
        .expect("coerce_theme_value rejects unknown keys");

    state_map.insert(key.to_owned(), value.clone());
    let new_state = validated_theme_state(state_map, "theme state")?;
    if current == value && new_state == state {
        return Ok(StateUpdateOutcome {
            changed: false,
            value,
            new_state: state,
            affected_targets: std::collections::BTreeSet::new(),
        });
    }
    let affected_targets = orchestrator::targets_for_key(key, Some(&new_state));

    Ok(StateUpdateOutcome {
        changed: true,
        value,
        new_state,
        affected_targets,
    })
}

fn normalize_theme_patch(value: Value, label: &str) -> crate::Result<Map<String, Value>> {
    let object = value.as_object().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("{label} must be a JSON object"),
        )
    })?;

    let mut normalized = Map::new();
    for (key, value) in object {
        normalized.insert(key.clone(), coerce_theme_value(key, value.clone())?);
    }

    Ok(ordered_theme_mapping(&normalized))
}

fn validated_theme_state(
    data: Map<String, Value>,
    label: &str,
) -> crate::Result<schema::ThemeState> {
    let missing = schema::ThemeState::known_field_names()
        .iter()
        .copied()
        .filter(|name| !data.contains_key(*name))
        .collect::<Vec<_>>();

    if !missing.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("{label}: missing required keys: {}", missing.join(", ")),
        )
        .into());
    }

    let mut remaining = data;
    let mut normalized = Map::new();
    for key in schema::ThemeState::known_field_names() {
        let value = remaining
            .remove(*key)
            .expect("validated_theme_state checked missing known keys");
        normalized.insert((*key).to_owned(), coerce_theme_value(key, value)?);
    }

    for (key, value) in remaining {
        normalized.insert(key, value);
    }

    serde_json::from_value(Value::Object(normalized)).map_err(|error| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("Invalid theme state in memory: {error}"),
        )
        .into()
    })
}

fn ordered_theme_mapping(data: &Map<String, Value>) -> Map<String, Value> {
    let mut ordered = Map::new();
    for key in schema::ThemeState::known_field_names() {
        if let Some(value) = data.get(*key) {
            ordered.insert((*key).to_owned(), value.clone());
        }
    }
    ordered
}

fn coerce_theme_value(key: &str, value: Value) -> crate::Result<Value> {
    if !schema::ThemeState::known_field_names().contains(&key) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "unknown key '{}'. Valid: {}",
                key,
                valid_theme_keys().join(", ")
            ),
        )
        .into());
    }

    if schema::ThemeState::int_field_names().contains(&key) {
        return match value {
            Value::Number(number) if number.as_i64().is_some() => Ok(Value::Number(number)),
            Value::String(text) => match text.parse::<i64>() {
                Ok(number) => Ok(Value::from(number)),
                Err(_) => Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("'{}' must be an integer, got {}", key, Value::String(text)),
                )
                .into()),
            },
            Value::Bool(_) => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("'{}' must be an integer", key),
            )
            .into()),
            other => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("'{}' must be an integer, got {}", key, other),
            )
            .into()),
        };
    }

    if schema::ThemeState::bool_field_names().contains(&key) {
        return match value {
            Value::Bool(value) => Ok(Value::Bool(value)),
            Value::String(text) => {
                let lowered = text.to_ascii_lowercase();
                if matches!(lowered.as_str(), "true" | "on" | "dark" | "yes" | "1") {
                    Ok(Value::Bool(true))
                } else if matches!(lowered.as_str(), "false" | "off" | "light" | "no" | "0") {
                    Ok(Value::Bool(false))
                } else {
                    Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        format!(
                            "'{}' must be a boolean (true/false, on/off, dark/light), got {}",
                            key,
                            Value::String(text)
                        ),
                    )
                    .into())
                }
            }
            other => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!(
                    "'{}' must be a boolean (true/false, on/off, dark/light), got {}",
                    key, other
                ),
            )
            .into()),
        };
    }

    if schema::ThemeState::string_field_names().contains(&key) {
        return match value {
            Value::String(text) if !text.is_empty() => Ok(Value::String(
                schema::canonicalize_theme_string_value(key, &text).into_owned(),
            )),
            _ => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("'{}' must be a non-empty string", key),
            )
            .into()),
        };
    }

    Ok(value)
}

fn presets_dir() -> io::Result<PathBuf> {
    paths::data_path("presets")
}

fn preset_path(name: &str) -> crate::Result<(String, PathBuf)> {
    let preset_name = normalize_preset_name(name)?;
    Ok((
        preset_name.clone(),
        presets_dir()?.join(format!("{preset_name}.json")),
    ))
}

fn normalize_preset_name(name: &str) -> crate::Result<String> {
    let mut normalized = name.trim().to_owned();
    if normalized.to_ascii_lowercase().ends_with(".json") {
        normalized.truncate(normalized.len() - 5);
    }

    if normalized.is_empty() {
        return Err(
            io::Error::new(io::ErrorKind::InvalidInput, "preset name must not be empty").into(),
        );
    }

    if normalized == "."
        || normalized == ".."
        || normalized.contains('/')
        || normalized.contains('\\')
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("invalid preset name {}", Value::String(name.to_owned())),
        )
        .into());
    }

    Ok(normalized)
}

fn available_presets() -> crate::Result<Vec<String>> {
    json_file_stems_by_filename(&presets_dir()?).map_err(Into::into)
}

pub(crate) fn json_file_stems_by_filename(dir: &Path) -> io::Result<Vec<String>> {
    let mut stems: Vec<(String, String)> = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error),
    };

    for entry in entries {
        let path = entry?.path();
        if path
            .extension()
            .is_some_and(|extension| extension == "json")
            && let Some(stem) = path.file_stem().and_then(|stem| stem.to_str())
        {
            let file_name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or_default()
                .to_owned();
            stems.push((file_name, stem.to_owned()));
        }
    }

    stems.sort_by(|left, right| left.0.cmp(&right.0));
    Ok(stems.into_iter().map(|(_, stem)| stem).collect())
}

fn read_json_file(path: &Path) -> crate::Result<Value> {
    let text = fs::read_to_string(path)?;
    parse_json_value(&text)
}

fn print_json_value(value: &Value) {
    println!("{}", json::format_pretty_value(value));
}

fn valid_theme_keys() -> Vec<&'static str> {
    let mut keys = schema::ThemeState::known_field_names().to_vec();
    keys.sort_unstable();
    keys
}

fn display_value(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        other => other.to_string(),
    }
}

fn parse_json_value(text: &str) -> crate::Result<Value> {
    serde_json::from_str(text).map_err(|error| {
        io::Error::new(io::ErrorKind::InvalidData, format!("invalid JSON: {error}")).into()
    })
}

fn map_user_err<T, E>(result: Result<T, E>) -> CliResult<T>
where
    E: std::fmt::Display,
{
    result.map_err(CliFailure::from_error)
}

impl CliFailure {
    fn from_error(error: impl std::fmt::Display) -> Self {
        Self::Message(format!("error: {error}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{ScopedEnvVar, TempDir, env_lock, repo_root, scoped_repo_paths};

    fn repo_scheme_is_dark(scheme_name: &str) -> crate::Result<bool> {
        Ok(resolve::load_colors(scheme_name, &repo_root().join("styling/colors"))?.is_dark())
    }

    #[test]
    fn bool_aliases_are_coerced() {
        assert_eq!(
            coerce_theme_value("dark_hint", Value::String("on".to_owned()))
                .expect("valid bool alias"),
            Value::Bool(true)
        );
        assert_eq!(
            coerce_theme_value("dark_hint", Value::String("light".to_owned()))
                .expect("valid bool alias"),
            Value::Bool(false)
        );
    }

    #[test]
    fn mono_font_aliases_are_canonicalized() {
        assert_eq!(
            coerce_theme_value(
                "mono_font",
                Value::String("JetBrains Mono Nerd Font".to_owned())
            )
            .expect("valid mono font alias"),
            Value::String("JetBrainsMono Nerd Font".to_owned())
        );
        assert_eq!(
            coerce_theme_value("mono_font", Value::String("Commit Mono".to_owned()))
                .expect("valid mono font alias"),
            Value::String("CommitMono".to_owned())
        );
    }

    #[test]
    fn value_rendering_matches_cli_messages() {
        assert_eq!(display_value(&Value::Bool(true)), "true");
        assert_eq!(display_value(&Value::String("Mono".to_owned())), "Mono");
    }

    #[test]
    fn ordered_theme_mapping_uses_schema_field_order() {
        let mut data = Map::new();
        data.insert("mono_font".to_owned(), Value::String("Mono".to_owned()));
        data.insert(
            "color_scheme".to_owned(),
            Value::String("scheme".to_owned()),
        );
        data.insert(
            "wallpaper".to_owned(),
            Value::String("/tmp/wall.png".to_owned()),
        );

        let keys = ordered_theme_mapping(&data)
            .into_iter()
            .map(|(key, _)| key)
            .collect::<Vec<_>>();
        assert_eq!(keys, vec!["color_scheme", "wallpaper", "mono_font"]);
    }

    #[test]
    fn repo_scheme_appearance_metadata_is_available() {
        assert!(repo_scheme_is_dark("gruvbox-dark").expect("dark scheme should load"));
        assert!(!repo_scheme_is_dark("gruvbox-light").expect("light scheme should load"));
    }

    #[test]
    fn color_scheme_changes_preserve_explicit_dark_hint() {
        let _lock = env_lock();
        let data_home = TempDir::new("desktopctl-theme-state").expect("temp dir");
        let _data = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path().as_os_str());
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        let dark_hint_outcome =
            set_state_key_internal("dark_hint", Value::Bool(false)).expect("set dark hint");
        resolve::save_state_keys(&[("dark_hint", &dark_hint_outcome.value)])
            .expect("persist explicit dark hint");

        let outcome =
            set_state_key_internal("color_scheme", Value::String("catppuccin-mocha".to_owned()))
                .expect("set color scheme");

        assert_eq!(outcome.value, Value::String("catppuccin-mocha".to_owned()));
        assert!(!outcome.new_state.dark_hint);
    }

    #[test]
    fn light_scheme_changes_do_not_clear_dark_hint() {
        let _lock = env_lock();
        let data_home = TempDir::new("desktopctl-theme-state").expect("temp dir");
        let _data = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path().as_os_str());
        let _paths = scoped_repo_paths();

        // State the precondition instead of inheriting it: dark_hint's seeded
        // value is user data and may legitimately be either.
        resolve::save_state_keys(&[("dark_hint", &Value::Bool(true))]).expect("seed dark_hint");

        let outcome =
            set_state_key_internal("color_scheme", Value::String("gruvbox-light".to_owned()))
                .expect("set color scheme");

        assert_eq!(outcome.value, Value::String("gruvbox-light".to_owned()));
        assert!(outcome.new_state.dark_hint);
    }

    #[test]
    fn font_targets_do_not_include_tmux() {
        assert!(!orchestrator::font_targets().contains("tmux"));
    }

    #[test]
    fn manual_dark_hint_write_records_its_time_even_when_unchanged() {
        let _lock = env_lock();
        let data_home = TempDir::new("desktopctl-theme-state").expect("temp dir");
        let _data = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path().as_os_str());
        let _paths = scoped_repo_paths();

        resolve::save_state_keys(&[("dark_hint", &Value::Bool(true))]).expect("seed dark_hint");
        let manual_at = || resolve::load_state().expect("state loads").extra;

        assert!(!manual_at().contains_key(DARK_HINT_MANUAL_AT_KEY));
        assert!(!set_dark_hint_internal(true, DarkHintOrigin::Scheduled).expect("scheduled write"));
        assert!(!manual_at().contains_key(DARK_HINT_MANUAL_AT_KEY));
        assert!(!set_dark_hint_internal(true, DarkHintOrigin::Manual).expect("manual write"));
        assert!(manual_at().contains_key(DARK_HINT_MANUAL_AT_KEY));
    }
}
