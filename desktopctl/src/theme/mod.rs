use crate::paths;
use serde_json::{Map, Value};
use std::{
    fs, io,
    path::{Path, PathBuf},
};

pub mod color;
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

pub fn run(command: crate::ThemeCommand) -> crate::Result<()> {
    match run_cli(command) {
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

fn manual_write_timestamp() -> String {
    chrono::Local::now().to_rfc3339()
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
fn run_cli(command: crate::ThemeCommand) -> CliResult<()> {
    match command {
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

fn remote_apply(scope: &str, target: Option<String>, wait_secs: u64) -> CliResult<()> {
    let report = crate::ipc::mutate(
        crate::ipc::RpcRequest::ThemeApply {
            scope: scope.to_owned(),
            target,
        },
        crate::ipc::APPLY_TIMEOUT,
        std::time::Duration::from_secs(wait_secs),
    )
    .map_err(CliFailure::from_error)?;

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
    let response: Value = crate::ipc::mutate(
        crate::ipc::RpcRequest::ThemeSet {
            key: args.key.clone(),
            value: Value::String(args.value),
        },
        crate::ipc::APPLY_TIMEOUT,
        std::time::Duration::from_secs(args.wait.wait_daemon),
    )
    .map_err(CliFailure::from_error)?;

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
    crate::ipc::mutate::<Value>(
        crate::ipc::RpcRequest::ThemePresetApply {
            name: args.name.clone(),
        },
        crate::ipc::APPLY_TIMEOUT,
        std::time::Duration::from_secs(args.wait.wait_daemon),
    )
    .map_err(CliFailure::from_error)?;
    println!("Loaded preset '{}'.", args.name);
    Ok(())
}

fn remote_preset_save(args: crate::SavePresetArgs) -> CliResult<()> {
    let payload = map_user_err(parse_json_value(&args.payload))?;
    let response: Value = crate::ipc::mutate(
        crate::ipc::RpcRequest::ThemePresetSave {
            name: args.name.clone(),
            payload,
        },
        crate::ipc::DEFAULT_TIMEOUT,
        std::time::Duration::from_secs(args.wait.wait_daemon),
    )
    .map_err(CliFailure::from_error)?;

    let count = response["fields"].as_u64().unwrap_or(0);
    let noun = if count == 1 { "field" } else { "fields" };
    println!("Saved preset '{}' ({} {}).", args.name, count, noun);
    Ok(())
}

fn remote_preset_delete(args: crate::NamedArg) -> CliResult<()> {
    crate::ipc::mutate::<Value>(
        crate::ipc::RpcRequest::ThemePresetDelete {
            name: args.name.clone(),
        },
        crate::ipc::DEFAULT_TIMEOUT,
        std::time::Duration::from_secs(args.wait.wait_daemon),
    )
    .map_err(CliFailure::from_error)?;
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
    for preset in map_user_err(resolve::preset_names())? {
        println!("{preset}");
    }
    Ok(())
}

fn cmd_list_wallpapers(args: crate::ListWallpapersArgs) -> CliResult<()> {
    let directory = if let Some(path) = args.directory.as_deref() {
        map_user_err(crate::fs_util::expand_user_path(path))?
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
    match crate::ipc::send::<Value>(
        crate::ipc::RpcRequest::ThemeStatus,
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

    let rendered = map_user_err(serde_json::to_string_pretty(&Value::Object(
        schema::seed_json_map(&state_map),
    )))?;
    println!("{rendered}");
    Ok(())
}

fn cmd_status(json_output: bool) -> CliResult<()> {
    let state_map = read_state_map()?;

    if json_output {
        println!(
            "{}",
            map_user_err(serde_json::to_string_pretty(&state_map))?
        );
        return Ok(());
    }

    for key in schema::field_names() {
        if let Some(value) = state_map.get(key) {
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
                crate::invalid_input("apply scope 'target' requires a target name").into()
            }),
            other => Err(crate::invalid_input(format!("unknown apply scope '{other}'")).into()),
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

struct PreparedPatch {
    new_state: schema::ThemeState,
    changed_keys: Vec<String>,
}

fn prepare_state_patch(
    state: &schema::ThemeState,
    patch: &Map<String, Value>,
) -> crate::Result<PreparedPatch> {
    let mut state_map = state.to_ordered_json_map();
    let mut changed_keys = Vec::new();
    for (key, value) in patch {
        if state_map.get(key) != Some(value) {
            changed_keys.push(key.clone());
        }
        state_map.insert(key.clone(), value.clone());
    }

    let new_state = validated_theme_state(state_map, "theme state")?;
    Ok(PreparedPatch {
        new_state,
        changed_keys,
    })
}

fn apply_state_patch(
    patch: Map<String, Value>,
    origin: DarkHintOrigin,
) -> crate::Result<PresetOutcome> {
    let state = resolve::load_state()?;
    let prepared = prepare_state_patch(&state, &patch)?;
    let manual_dark_hint = origin == DarkHintOrigin::Manual && patch.contains_key("dark_hint");
    let manual_at = Value::String(manual_write_timestamp());

    if prepared.changed_keys.is_empty() && prepared.new_state == state {
        if manual_dark_hint {
            resolve::save_state_keys(&[(DARK_HINT_MANUAL_AT_KEY, &manual_at)])?;
        }
        return Ok(PresetOutcome {
            state,
            changed_keys: Vec::new(),
        });
    }

    let colors_dir = resolve::colors_dir()?;
    let colors = resolve::load_colors(&prepared.new_state.color_scheme, &colors_dir)?;
    let affected = orchestrator::targets_for_keys(
        prepared.changed_keys.iter().map(String::as_str),
        Some(&prepared.new_state),
    );
    orchestrator::apply(affected, &colors, &prepared.new_state, true).into_result()?;

    let mut pairs = patch
        .iter()
        .map(|(key, value)| (key.as_str(), value))
        .collect::<Vec<_>>();
    if manual_dark_hint {
        pairs.push((DARK_HINT_MANUAL_AT_KEY, &manual_at));
    }
    resolve::save_state_keys(&pairs)?;

    Ok(PresetOutcome {
        state: prepared.new_state,
        changed_keys: prepared.changed_keys,
    })
}

pub(crate) fn set_theme_key_core(
    key: &str,
    raw_value: Value,
    origin: DarkHintOrigin,
) -> crate::Result<SetKeyOutcome> {
    let value = coerce_theme_value(key, raw_value)?;
    let mut patch = Map::new();
    patch.insert(key.to_owned(), value);
    let outcome = apply_state_patch(patch, origin)?;
    Ok(SetKeyOutcome {
        changed: !outcome.changed_keys.is_empty(),
        state: outcome.state,
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
    let preset_name = normalize_preset_name(name)?;
    let Some(preset_value) = resolve::load_preset(&preset_name)? else {
        let available = resolve::preset_names()?;
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
    };

    let preset = normalize_theme_patch(preset_value, &format!("preset '{}'", preset_name))?;
    if preset.is_empty() {
        return Ok(PresetOutcome {
            state: resolve::load_state()?,
            changed_keys: Vec::new(),
        });
    }

    // A preset's dark_hint is a manual write.
    apply_state_patch(preset, DarkHintOrigin::Manual)
}

pub(crate) fn save_preset_core(name: &str, payload: Value) -> crate::Result<usize> {
    let preset_name = normalize_preset_name(name)?;
    let preset = normalize_theme_patch(payload, &format!("preset '{}'", preset_name))?;

    if preset.is_empty() {
        return Err(crate::invalid_input("preset must include at least one field").into());
    }

    let fields = preset.len();
    resolve::save_preset(&preset_name, &Value::Object(preset))?;
    Ok(fields)
}

pub(crate) fn delete_preset_core(name: &str) -> crate::Result<()> {
    let preset_name = normalize_preset_name(name)?;
    if !resolve::delete_preset(&preset_name)? {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("preset '{}' not found", preset_name),
        )
        .into());
    }
    Ok(())
}

pub(crate) fn preset_names() -> crate::Result<Vec<String>> {
    resolve::preset_names()
}

fn load_state_and_colors() -> CliResult<(schema::ThemeState, schema::ColorScheme)> {
    let colors_dir = map_user_err(resolve::colors_dir())?;
    let state = map_user_err(resolve::load_state())?;
    let colors = map_user_err(resolve::load_colors(&state.color_scheme, &colors_dir))?;
    Ok((state, colors))
}

fn normalize_theme_patch(value: Value, label: &str) -> crate::Result<Map<String, Value>> {
    let object = value
        .as_object()
        .ok_or_else(|| crate::invalid_input(format!("{label} must be a JSON object")))?;

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
    let missing = schema::field_names()
        .filter(|name| !data.contains_key(*name))
        .collect::<Vec<_>>();

    if !missing.is_empty() {
        return Err(crate::invalid_input(format!(
            "{label}: missing required keys: {}",
            missing.join(", ")
        ))
        .into());
    }

    let mut remaining = data;
    let mut normalized = Map::new();
    for key in schema::field_names() {
        let value = remaining
            .remove(key)
            .expect("validated_theme_state checked missing known keys");
        normalized.insert(key.to_owned(), coerce_theme_value(key, value)?);
    }

    for (key, value) in remaining {
        normalized.insert(key, value);
    }

    serde_json::from_value(Value::Object(normalized)).map_err(|error| {
        crate::invalid_data(format!("Invalid theme state in memory: {error}")).into()
    })
}

fn ordered_theme_mapping(data: &Map<String, Value>) -> Map<String, Value> {
    let mut ordered = Map::new();
    for key in schema::field_names() {
        if let Some(value) = data.get(key) {
            ordered.insert(key.to_owned(), value.clone());
        }
    }
    ordered
}

fn coerce_theme_value(key: &str, value: Value) -> crate::Result<Value> {
    let Some(spec) = schema::find_field(key) else {
        return Err(crate::invalid_input(format!(
            "unknown key '{}'. Valid: {}",
            key,
            valid_theme_keys().join(", ")
        ))
        .into());
    };

    match spec.kind {
        schema::FieldKind::Int => {
            let parsed = match value {
                Value::Number(ref number) => number.as_i64(),
                Value::String(ref text) => text.parse::<i64>().ok(),
                Value::Bool(_) => {
                    return Err(
                        crate::invalid_input(format!("'{}' must be an integer", key)).into(),
                    );
                }
                _ => None,
            };
            let Some(number) = parsed else {
                return Err(crate::invalid_input(format!(
                    "'{}' must be an integer, got {}",
                    key, value
                ))
                .into());
            };
            if let Some(min) = spec.min
                && number < min
            {
                return Err(crate::invalid_input(format!(
                    "'{}' must be at least {min}, got {number}",
                    key
                ))
                .into());
            }
            Ok(Value::from(number))
        }
        schema::FieldKind::Bool => match value {
            Value::Bool(value) => Ok(Value::Bool(value)),
            Value::String(text) => {
                let lowered = text.to_ascii_lowercase();
                if matches!(lowered.as_str(), "true" | "on" | "dark" | "yes" | "1") {
                    Ok(Value::Bool(true))
                } else if matches!(lowered.as_str(), "false" | "off" | "light" | "no" | "0") {
                    Ok(Value::Bool(false))
                } else {
                    Err(crate::invalid_input(format!(
                        "'{}' must be a boolean (true/false, on/off, dark/light), got {}",
                        key,
                        Value::String(text)
                    ))
                    .into())
                }
            }
            other => Err(crate::invalid_input(format!(
                "'{}' must be a boolean (true/false, on/off, dark/light), got {}",
                key, other
            ))
            .into()),
        },
        schema::FieldKind::String => match value {
            Value::String(text) if !text.is_empty() => Ok(Value::String(text)),
            _ => Err(crate::invalid_input(format!("'{}' must be a non-empty string", key)).into()),
        },
    }
}

fn normalize_preset_name(name: &str) -> crate::Result<String> {
    let normalized = name.trim();
    if normalized.is_empty() {
        return Err(crate::invalid_input("preset name must not be empty").into());
    }
    Ok(normalized.to_owned())
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

fn print_json_value(value: &Value) {
    println!(
        "{}",
        serde_json::to_string_pretty(value).expect("serializing JSON value succeeds")
    );
}

fn valid_theme_keys() -> Vec<&'static str> {
    let mut keys: Vec<_> = schema::field_names().collect();
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
    serde_json::from_str(text)
        .map_err(|error| crate::invalid_data(format!("invalid JSON: {error}")).into())
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
    use crate::test_support::{ScopedEnvVar, TempDir, env_lock, scoped_repo_paths};

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
    fn coerce_theme_value_enforces_field_minimums_and_parses_ints() {
        assert_eq!(
            coerce_theme_value("font_size", Value::String("12".to_owned()))
                .expect("positive integer string should parse"),
            Value::from(12)
        );
        assert!(coerce_theme_value("font_size", Value::from(0)).is_err());
        assert!(coerce_theme_value("mono_font_size", Value::from(-2)).is_err());
        assert_eq!(
            coerce_theme_value("quickshell_font_size_offset", Value::from(-2))
                .expect("signed offsets allow negative values"),
            Value::from(-2)
        );
    }

    #[test]
    fn color_scheme_changes_preserve_explicit_dark_hint() {
        let _lock = env_lock();
        let data_home = TempDir::new("desktopctl-theme-state").expect("temp dir");
        let _data = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path().as_os_str());
        let _paths = scoped_repo_paths();
        let seed = resolve::load_state().expect("seed loads");

        for (dark_hint, scheme) in [(false, "catppuccin-mocha"), (true, "gruvbox-light")] {
            let mut patch = Map::new();
            patch.insert("dark_hint".to_owned(), Value::Bool(dark_hint));
            let after_hint = prepare_state_patch(&seed, &patch).expect("set dark_hint");

            let mut scheme_patch = Map::new();
            scheme_patch.insert("color_scheme".to_owned(), Value::String(scheme.to_owned()));
            let outcome = prepare_state_patch(&after_hint.new_state, &scheme_patch)
                .expect("set color scheme");

            assert_eq!(outcome.new_state.color_scheme, scheme);
            assert_eq!(outcome.new_state.dark_hint, dark_hint);
        }
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
        assert!(
            !set_theme_key_core("dark_hint", Value::Bool(true), DarkHintOrigin::Scheduled)
                .expect("scheduled write")
                .changed
        );
        assert!(!manual_at().contains_key(DARK_HINT_MANUAL_AT_KEY));
        assert!(
            !set_theme_key_core("dark_hint", Value::Bool(true), DarkHintOrigin::Manual)
                .expect("manual write")
                .changed
        );
        assert!(manual_at().contains_key(DARK_HINT_MANUAL_AT_KEY));
    }
}
