use crate::paths;
use serde_json::error::Category as JsonErrorCategory;
use serde_json::{Map, Value};
use std::io::Write;
use std::{
    env,
    fs::{self, OpenOptions},
    io,
    path::{Path, PathBuf},
    process::{self, Command},
    time::{SystemTime, UNIX_EPOCH},
};

pub mod json;
pub mod orchestrator;
pub mod resolve;
pub mod schema;
pub mod targets;
pub mod wallpaper_browser;

const BASE_COLOR_TARGETS: [&str; 18] = [
    "alacritty",
    "ghostty",
    "gtksourceview",
    "hyprland",
    "zathura",
    "quickshell",
    "neovim",
    "opencode",
    "starship",
    "tmux",
    "gtk",
    "qt",
    "vicinae",
    "bat",
    "snappy_switcher",
    "spicetify",
    "vscode",
    "zsh",
];

const FONT_TARGETS: [&str; 10] = [
    "alacritty",
    "chromium",
    "ghostty",
    "neovide",
    "quickshell",
    "gtk",
    "qt",
    "vicinae",
    "snappy_switcher",
    "vscode",
];

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

pub fn set_dark_hint(enabled: bool) -> crate::Result<()> {
    let outcome = set_state_key_internal("dark_hint", Value::Bool(enabled))?;
    if !outcome.changed {
        return Ok(());
    }

    let colors_dir = resolve::colors_dir()?;
    let colors = resolve::load_colors(&outcome.new_state.color_scheme, &colors_dir)?;
    let registry = targets::build_registry()?;
    orchestrator::apply_targets_quiet(
        &registry,
        outcome.affected_targets.iter(),
        &colors,
        &outcome.new_state,
        true,
    )
    .map_err(|error| {
        io::Error::other(format!(
            "failed to apply affected theme targets for dark_hint: {error}"
        ))
    })?;
    resolve::save_state(&outcome.new_state)?;
    Ok(())
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

pub(crate) fn run_command(command: &[&str]) -> crate::Result<()> {
    if command.is_empty() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "Command cannot be empty").into());
    }

    let output = Command::new(command[0]).args(&command[1..]).output();
    command_result(output, command[0])
}

pub(crate) fn run_owned_command(command: &[String]) -> crate::Result<()> {
    if command.is_empty() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "Command cannot be empty").into());
    }

    let output = Command::new(&command[0]).args(&command[1..]).output();
    command_result(output, &command[0])
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

fn run_cli(args: crate::ThemeArgs) -> CliResult<()> {
    match args.command {
        crate::ThemeCommand::All => cmd_all(),
        crate::ThemeCommand::Sync => cmd_sync(),
        crate::ThemeCommand::Colors => cmd_colors(),
        crate::ThemeCommand::Wallpaper => cmd_wallpaper(),
        crate::ThemeCommand::Cursor => cmd_cursor(),
        crate::ThemeCommand::Fonts => cmd_fonts(),
        crate::ThemeCommand::Target(args) => cmd_target(args),
        crate::ThemeCommand::Set(args) => cmd_set(args),
        crate::ThemeCommand::Preset(args) => cmd_preset(args),
        crate::ThemeCommand::SavePreset(args) => cmd_save_preset(args),
        crate::ThemeCommand::DeletePreset(args) => cmd_delete_preset(args),
        crate::ThemeCommand::ListSchemes(args) => cmd_list_schemes(args.json),
        crate::ThemeCommand::ListWallpapers(args) => cmd_list_wallpapers(args),
        crate::ThemeCommand::ListPresets(args) => cmd_list_presets(args.json),
        crate::ThemeCommand::Status(args) => cmd_status(args.json),
    }
}

fn cmd_all() -> CliResult<()> {
    let registry = map_user_err(targets::build_registry())?;
    let (state, colors) = load_state_and_colors()?;
    println!(
        "Applying all targets ({}-{})...",
        colors.family, colors.variant
    );
    if orchestrator::apply_all(&registry, &colors, &state, true, false) {
        Ok(())
    } else {
        Err(CliFailure::Reported)
    }
}

fn cmd_sync() -> CliResult<()> {
    let registry = map_user_err(targets::build_registry())?;
    let (state, colors) = load_state_and_colors()?;
    println!(
        "Syncing theme-managed config ({}-{})...",
        colors.family, colors.variant
    );
    if orchestrator::apply_all(&registry, &colors, &state, false, true) {
        Ok(())
    } else {
        Err(CliFailure::Reported)
    }
}

fn cmd_colors() -> CliResult<()> {
    let registry = map_user_err(targets::build_registry())?;
    let (state, colors) = load_state_and_colors()?;
    println!(
        "Applying color targets ({}-{})...",
        colors.family, colors.variant
    );
    if orchestrator::apply_targets(
        &registry,
        color_targets_for_state(&state).iter(),
        &colors,
        &state,
        true,
    ) {
        Ok(())
    } else {
        Err(CliFailure::Reported)
    }
}

fn cmd_wallpaper() -> CliResult<()> {
    let registry = map_user_err(targets::build_registry())?;
    let (state, colors) = load_state_and_colors()?;
    println!("Applying wallpaper ({})...", state.wallpaper);
    if orchestrator::apply_targets(&registry, ["wallpaper"], &colors, &state, true) {
        Ok(())
    } else {
        Err(CliFailure::Reported)
    }
}

fn cmd_cursor() -> CliResult<()> {
    let registry = map_user_err(targets::build_registry())?;
    let (state, colors) = load_state_and_colors()?;
    println!(
        "Applying cursor ({} {})...",
        state.cursor_theme, state.cursor_size
    );
    if orchestrator::apply_targets(&registry, ["cursor"], &colors, &state, true) {
        Ok(())
    } else {
        Err(CliFailure::Reported)
    }
}

fn cmd_fonts() -> CliResult<()> {
    let registry = map_user_err(targets::build_registry())?;
    let (state, colors) = load_state_and_colors()?;
    println!(
        "Applying font targets ({}, {})...",
        state.mono_font, state.system_font
    );
    if orchestrator::apply_targets(&registry, FONT_TARGETS, &colors, &state, true) {
        Ok(())
    } else {
        Err(CliFailure::Reported)
    }
}

fn cmd_target(args: crate::TargetArgs) -> CliResult<()> {
    let registry = map_user_err(targets::build_registry())?;
    let (state, colors) = load_state_and_colors()?;
    println!("Applying target: {}...", args.name);
    if orchestrator::apply_target(&registry, &args.name, &colors, &state, true) {
        Ok(())
    } else {
        Err(CliFailure::Reported)
    }
}

fn cmd_set(args: crate::SetArgs) -> CliResult<()> {
    let crate::SetArgs { key, value } = args;
    if key == "dark_hint" {
        let enabled = match map_user_err(coerce_theme_value(&key, Value::String(value.clone())))? {
            Value::Bool(enabled) => enabled,
            _ => unreachable!("dark_hint is validated as a bool"),
        };
        map_user_err(set_dark_hint(enabled))?;
        println!("Set {} = {}", key, python_repr_value(&Value::Bool(enabled)));
        return Ok(());
    }

    let outcome = map_user_err(set_state_key_internal(&key, Value::String(value)))?;

    if !outcome.changed {
        println!(
            "{} is already '{}', nothing to do.",
            key,
            python_display_value(&outcome.value)
        );
        return Ok(());
    }

    println!("Set {} = {}", key, python_repr_value(&outcome.value));
    apply_affected_targets(&outcome.new_state, &outcome.affected_targets)?;
    map_user_err(resolve::save_state(&outcome.new_state))?;
    Ok(())
}

fn cmd_preset(args: crate::NamedArg) -> CliResult<()> {
    let (preset_name, preset_path) = map_user_err(preset_path(&args.name))?;
    if !preset_path.is_file() {
        return missing_preset(&preset_name);
    }

    let preset_value = map_user_err(read_json_file(&preset_path))?;
    let mut preset = map_user_err(normalize_theme_patch(
        preset_value,
        &format!("preset '{}'", preset_name),
    ))?;
    let requested_dark_hint = preset.remove("dark_hint").and_then(|value| value.as_bool());

    let has_theme_changes = !preset.is_empty();

    if has_theme_changes {
        let state = map_user_err(resolve::load_state())?;
        let mut state_map = state.to_ordered_json_map();
        for (key, value) in &preset {
            state_map.insert(key.clone(), value.clone());
        }
        let new_state = map_user_err(validated_theme_state(state_map, "theme state"))?;

        println!("Loaded preset '{}', applying all targets...", preset_name);
        let colors_dir = map_user_err(resolve::colors_dir())?;
        let colors = map_user_err(resolve::load_colors(&new_state.color_scheme, &colors_dir))?;
        let registry = map_user_err(targets::build_registry())?;
        if !orchestrator::apply_all(&registry, &colors, &new_state, true, false) {
            return Err(CliFailure::Reported);
        }
        map_user_err(resolve::save_state(&new_state))?;
    }

    if let Some(enabled) = requested_dark_hint {
        map_user_err(set_dark_hint(enabled))?;
        if !has_theme_changes {
            println!("Loaded preset '{}'.", preset_name);
        }
    }

    Ok(())
}

fn cmd_save_preset(args: crate::SavePresetArgs) -> CliResult<()> {
    let (preset_name, preset_path) = map_user_err(preset_path(&args.name))?;
    let payload = map_user_err(parse_json_value(&args.payload))?;
    let preset = map_user_err(normalize_theme_patch(
        payload,
        &format!("preset '{}'", preset_name),
    ))?;

    if preset.is_empty() {
        return Err(CliFailure::Message(
            "error: preset must include at least one field".to_owned(),
        ));
    }

    if let Some(parent) = preset_path.parent() {
        map_user_err(fs::create_dir_all(parent))?;
    }

    let ordered = ordered_theme_mapping(&preset);
    let rendered = format!("{}\n", json::format_pretty_value(&Value::Object(ordered)));
    map_user_err(atomic_write(&preset_path, rendered.as_bytes()))?;

    let count = preset.len();
    let noun = if count == 1 { "field" } else { "fields" };
    println!("Saved preset '{}' ({} {}).", preset_name, count, noun);
    Ok(())
}

fn cmd_delete_preset(args: crate::NamedArg) -> CliResult<()> {
    let (preset_name, preset_path) = map_user_err(preset_path(&args.name))?;
    if !preset_path.is_file() {
        return missing_preset(&preset_name);
    }

    map_user_err(fs::remove_file(&preset_path))?;
    println!("Deleted preset '{}'.", preset_name);
    Ok(())
}

fn cmd_list_schemes(json_output: bool) -> CliResult<()> {
    let colors_dir = map_user_err(resolve::colors_dir())?;
    let schemes = if json_output {
        map_user_err(json_file_stems_by_filename(&colors_dir))?
    } else {
        map_user_err(json_file_stems(&colors_dir))?
    };

    if !json_output {
        if schemes.is_empty() {
            println!("No color schemes found.");
            return Ok(());
        }

        for scheme in schemes {
            println!("  {scheme}");
        }
        return Ok(());
    }

    let mut items = Vec::new();
    for scheme_name in schemes {
        let colors = map_user_err(resolve::load_colors(&scheme_name, &colors_dir))?;
        let appearance = if colors.is_light() { "light" } else { "dark" }.to_owned();
        let mut item = Map::new();
        item.insert("schemeName".to_owned(), Value::String(scheme_name));
        item.insert("family".to_owned(), Value::String(colors.family));
        item.insert("variant".to_owned(), Value::String(colors.variant));
        item.insert("appearance".to_owned(), Value::String(appearance));
        item.insert("bg".to_owned(), Value::String(colors.bg));
        item.insert("bg_dim".to_owned(), Value::String(colors.bg_dim));
        item.insert("bg1".to_owned(), Value::String(colors.bg1));
        item.insert("bg2".to_owned(), Value::String(colors.bg2));
        item.insert("bg3".to_owned(), Value::String(colors.bg3));
        item.insert("fg".to_owned(), Value::String(colors.fg));
        item.insert("fg2".to_owned(), Value::String(colors.fg2));
        item.insert("fg3".to_owned(), Value::String(colors.fg3));
        item.insert("fg4".to_owned(), Value::String(colors.fg4));
        item.insert("accent".to_owned(), Value::String(colors.accent));
        item.insert("red".to_owned(), Value::String(colors.red));
        item.insert("green".to_owned(), Value::String(colors.green));
        item.insert("orange".to_owned(), Value::String(colors.orange));
        item.insert("blue".to_owned(), Value::String(colors.blue));
        item.insert("yellow".to_owned(), Value::String(colors.yellow));
        item.insert("purple".to_owned(), Value::String(colors.purple));
        item.insert("cyan".to_owned(), Value::String(colors.cyan));
        item.insert("red_bright".to_owned(), Value::String(colors.red_bright));
        item.insert(
            "green_bright".to_owned(),
            Value::String(colors.green_bright),
        );
        item.insert(
            "yellow_bright".to_owned(),
            Value::String(colors.yellow_bright),
        );
        item.insert("blue_bright".to_owned(), Value::String(colors.blue_bright));
        item.insert(
            "purple_bright".to_owned(),
            Value::String(colors.purple_bright),
        );
        item.insert("cyan_bright".to_owned(), Value::String(colors.cyan_bright));
        item.insert(
            "orange_bright".to_owned(),
            Value::String(colors.orange_bright),
        );
        item.insert(
            "palette".to_owned(),
            Value::Array(colors.palette.into_iter().map(Value::String).collect()),
        );
        items.push(Value::Object(item));
    }

    print_json_value(&Value::Array(items));
    Ok(())
}

fn cmd_list_presets(json_output: bool) -> CliResult<()> {
    let presets_dir = map_user_err(presets_dir())?;
    let presets = if json_output {
        map_user_err(json_file_stems_by_filename(&presets_dir))?
    } else {
        map_user_err(json_file_stems(&presets_dir))?
    };

    if !json_output {
        if presets.is_empty() {
            println!("No presets found.");
            return Ok(());
        }

        for preset in presets {
            println!("  {preset}");
        }
        return Ok(());
    }

    let mut items = Vec::new();
    for preset_name in presets {
        let value = map_user_err(read_json_file(
            &presets_dir.join(format!("{preset_name}.json")),
        ))?;
        let object = value.as_object().ok_or_else(|| {
            CliFailure::Message(format!(
                "error: preset '{}' must be a JSON object",
                preset_name
            ))
        })?;

        let mut item = Map::new();
        item.insert("name".to_owned(), Value::String(preset_name));
        for (key, value) in object {
            item.insert(key.clone(), value.clone());
        }
        items.push(Value::Object(item));
    }

    print_json_value(&Value::Array(items));
    Ok(())
}

fn cmd_list_wallpapers(args: crate::ListWallpapersArgs) -> CliResult<()> {
    let directory = if let Some(path) = args.directory.as_deref() {
        map_user_err(expand_user_path(path))?
    } else {
        let state = map_user_err(resolve::load_state())?;
        let current = PathBuf::from(state.wallpaper);
        current
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or(map_user_err(paths::repo_path("wallpapers"))?)
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

fn cmd_status(json_output: bool) -> CliResult<()> {
    let state = map_user_err(resolve::load_state())?;

    if json_output {
        print!("{}", map_user_err(resolve::serialize_state(&state))?);
        return Ok(());
    }

    let state_map = state.to_ordered_json_map();
    for key in schema::ThemeState::known_field_names() {
        if let Some(value) = state_map.get(*key) {
            println!("  {}: {}", key, python_display_value(value));
        }
    }
    Ok(())
}

fn load_state_and_colors() -> CliResult<(schema::ThemeState, schema::ColorScheme)> {
    let colors_dir = map_user_err(resolve::colors_dir())?;
    let state = map_user_err(resolve::load_state())?;
    let colors = map_user_err(resolve::load_colors(&state.color_scheme, &colors_dir))?;
    Ok((state, colors))
}

fn apply_affected_targets(
    state: &schema::ThemeState,
    affected_targets: &std::collections::BTreeSet<String>,
) -> CliResult<()> {
    let colors_dir = map_user_err(resolve::colors_dir())?;
    let colors = map_user_err(resolve::load_colors(&state.color_scheme, &colors_dir))?;
    if affected_targets.is_empty() {
        return Ok(());
    }

    println!("Applying affected targets...");
    let registry = map_user_err(targets::build_registry())?;
    if orchestrator::apply_targets(&registry, affected_targets.iter(), &colors, state, true) {
        Ok(())
    } else {
        Err(CliFailure::Reported)
    }
}

fn color_targets_for_state(state: &schema::ThemeState) -> std::collections::BTreeSet<String> {
    let mut targets = BASE_COLOR_TARGETS
        .iter()
        .map(|name| (*name).to_owned())
        .collect::<std::collections::BTreeSet<_>>();

    if state.filter_wallpaper {
        targets.insert("wallpaper".to_owned());
    }

    targets
}

fn set_state_key_internal(key: &str, raw_value: Value) -> crate::Result<StateUpdateOutcome> {
    let state = resolve::load_state()?;
    let mut state_map = state.to_ordered_json_map();
    let value = coerce_theme_value(key, raw_value)?;

    let Some(current) = state_map.get(key).cloned() else {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "unknown key '{}'. Valid: {}",
                key,
                valid_theme_keys().join(", ")
            ),
        )
        .into());
    };

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
                    format!(
                        "'{}' must be an integer, got {}",
                        key,
                        python_repr_value(&Value::String(text))
                    ),
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
                format!(
                    "'{}' must be an integer, got {}",
                    key,
                    python_repr_value(&other)
                ),
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
                            python_repr_value(&Value::String(text))
                        ),
                    )
                    .into())
                }
            }
            other => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!(
                    "'{}' must be a boolean (true/false, on/off, dark/light), got {}",
                    key,
                    python_repr_value(&other)
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
    Ok(paths::repo_root()?.join("themes/presets"))
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
            format!("invalid preset name {}", python_string_repr(name)),
        )
        .into());
    }

    Ok(normalized)
}

fn missing_preset(preset_name: &str) -> CliResult<()> {
    let available = map_user_err(available_presets())?;
    Err(CliFailure::Message(format!(
        "error: preset '{}' not found. Available: {}",
        preset_name,
        if available.is_empty() {
            "(none)".to_owned()
        } else {
            available.join(", ")
        }
    )))
}

fn available_presets() -> crate::Result<Vec<String>> {
    json_file_stems(&presets_dir()?).map_err(Into::into)
}

fn json_file_stems(dir: &Path) -> io::Result<Vec<String>> {
    json_file_stems_with(dir, |path| {
        path.file_stem()
            .and_then(|stem| stem.to_str())
            .unwrap_or_default()
            .to_owned()
    })
}

fn json_file_stems_by_filename(dir: &Path) -> io::Result<Vec<String>> {
    json_file_stems_with(dir, |path| {
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or_default()
            .to_owned()
    })
}

fn json_file_stems_with<F>(dir: &Path, sort_key: F) -> io::Result<Vec<String>>
where
    F: Fn(&Path) -> String,
{
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
            stems.push((sort_key(&path), stem.to_owned()));
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

fn python_display_value(value: &Value) -> String {
    match value {
        Value::Bool(value) => python_bool(*value).to_owned(),
        Value::String(value) => value.clone(),
        other => other.to_string(),
    }
}

fn python_repr_value(value: &Value) -> String {
    match value {
        Value::String(value) => python_string_repr(value),
        Value::Bool(value) => python_bool(*value).to_owned(),
        other => other.to_string(),
    }
}

fn python_string_repr(value: &str) -> String {
    let mut output = String::from("'");
    for character in value.chars() {
        match character {
            '\\' => output.push_str("\\\\"),
            '\'' => output.push_str("\\'"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            character if character.is_control() => {
                output.push_str(&format!("\\x{:02x}", character as u32));
            }
            character => output.push(character),
        }
    }
    output.push('\'');
    output
}

fn python_bool(value: bool) -> &'static str {
    if value { "True" } else { "False" }
}

fn parse_json_value(text: &str) -> crate::Result<Value> {
    serde_json::from_str(text).map_err(|error| {
        io::Error::new(io::ErrorKind::InvalidData, python_json_error(text, &error)).into()
    })
}

fn python_json_error(text: &str, error: &serde_json::Error) -> String {
    if let Some(message) = leading_value_error(text) {
        return message;
    }

    let line = error.line();
    let column = error.column();
    let offset = json_char_offset(text, line, column);

    let message = match error.classify() {
        JsonErrorCategory::Syntax | JsonErrorCategory::Eof => {
            if error.to_string().starts_with("expected value") {
                "Expecting value".to_owned()
            } else {
                error.to_string()
            }
        }
        _ => error.to_string(),
    };

    format!("{message}: line {line} column {column} (char {offset})")
}

fn leading_value_error(text: &str) -> Option<String> {
    let (offset, first) = text
        .char_indices()
        .find(|(_, character)| !character.is_whitespace())?;
    let invalid = match first {
        't' => !text[offset..].starts_with("true"),
        'f' => !text[offset..].starts_with("false"),
        'n' => !text[offset..].starts_with("null"),
        _ => false,
    };

    if !invalid {
        return None;
    }

    let (line, column) = line_column_for_offset(text, offset);
    Some(format!(
        "Expecting value: line {line} column {column} (char {offset})"
    ))
}

fn json_char_offset(text: &str, line: usize, column: usize) -> usize {
    if line == 0 || column == 0 {
        return 0;
    }

    let mut current_line = 1;
    let mut current_column = 1;

    for (offset, character) in text.char_indices() {
        if current_line == line && current_column == column {
            return offset;
        }

        if character == '\n' {
            current_line += 1;
            current_column = 1;
        } else {
            current_column += 1;
        }
    }

    text.len()
}

fn line_column_for_offset(text: &str, offset: usize) -> (usize, usize) {
    let mut line = 1;
    let mut column = 1;

    for character in text[..offset].chars() {
        if character == '\n' {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    (line, column)
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

fn is_executable(path: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        match path.metadata() {
            Ok(metadata) => metadata.is_file() && metadata.permissions().mode() & 0o111 != 0,
            Err(_) => false,
        }
    }

    #[cfg(not(unix))]
    {
        path.is_file()
    }
}

fn command_result(output: io::Result<std::process::Output>, program: &str) -> crate::Result<()> {
    let output = match output {
        Ok(output) => output,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Err(
                io::Error::new(io::ErrorKind::NotFound, format!("{program:?} not found")).into(),
            );
        }
        Err(error) => return Err(error.into()),
    };

    if output.status.success() {
        return Ok(());
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{ScopedEnvVar, TempDir, env_lock};
    use std::path::{Path, PathBuf};

    fn repo_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("desktopctl lives under the repo root")
            .to_path_buf()
    }

    fn repo_scheme_is_dark(scheme_name: &str) -> crate::Result<bool> {
        Ok(resolve::load_colors(scheme_name, &repo_root().join("themes/colors"))?.is_dark())
    }

    #[test]
    fn bool_aliases_match_python_cli() {
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
    fn python_style_value_rendering_matches_cli_messages() {
        assert_eq!(python_display_value(&Value::Bool(true)), "True");
        assert_eq!(python_repr_value(&Value::Bool(false)), "False");
        assert_eq!(
            python_repr_value(&Value::String("O'Reilly".to_owned())),
            "'O\\'Reilly'"
        );
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
        resolve::save_state(&dark_hint_outcome.new_state).expect("persist explicit dark hint");

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
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        let outcome =
            set_state_key_internal("color_scheme", Value::String("gruvbox-light".to_owned()))
                .expect("set color scheme");

        assert_eq!(outcome.value, Value::String("gruvbox-light".to_owned()));
        assert!(outcome.new_state.dark_hint);
    }

    #[test]
    fn color_targets_include_zsh() {
        let state = schema::ThemeState::default_state_for_repo_root(&repo_root());
        assert!(color_targets_for_state(&state).contains("zsh"));
    }

    #[test]
    fn color_targets_include_opencode() {
        let state = schema::ThemeState::default_state_for_repo_root(&repo_root());
        assert!(color_targets_for_state(&state).contains("opencode"));
    }

    #[test]
    fn font_targets_do_not_include_tmux() {
        assert!(!FONT_TARGETS.contains(&"tmux"));
    }
}
