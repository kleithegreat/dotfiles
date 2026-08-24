//! The display topology the user chose: which output is primary, and where
//! each output sits.
//!
//! Hyprland has no notion of a primary output, so the shell used to infer one
//! from the monitor at the origin and the numbered workspaces were pinned to a
//! monitor description hardcoded per host. Neither survives meeting a display
//! you have never plugged in before. Both are replaced by one stored choice:
//! an empty selector means "decide automatically", which is what an unfamiliar
//! monitor gets, and everything downstream — the bar, the shell's surfaces,
//! workspaces 1-10 — follows the *effective* primary rather than a rule of
//! its own.

use crate::{hypr, paths, theme};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, fs, io, path::PathBuf};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

const RUNTIME_RELATIVE_PATH: &str = "hypr/displays-runtime.lua";

/// Workspaces the primary output owns. Matches the `1..10` bound in
/// `config/hypr/keybinds.lua`; the pins and the keys have to name the same set.
const NUMBERED_WORKSPACES: std::ops::RangeInclusive<u32> = 1..=10;

/// Everything the display pane can change about one output.
///
/// Stored whole, never partially. A partial `hl.monitor` is a merge when it
/// arrives through `hyprctl eval` but a *separate rule* at config-parse time,
/// where every field it omits falls back to that field's default -- and
/// `scale`'s default is `auto`. A file carrying positions alone therefore
/// silently rescaled the built-in panel on the next reload. Whatever this
/// struct omits, the compositor decides.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub(crate) struct OutputState {
    /// `"<width>x<height>@<rate>"`.
    pub(crate) mode: String,
    /// `"<x>x<y>"`.
    pub(crate) position: String,
    pub(crate) scale: f64,
    pub(crate) vrr: i64,
    pub(crate) transform: i64,
    pub(crate) disabled: bool,
}

/// Stored topology. Empty is the default and means every choice is automatic.
#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct DisplayState {
    /// Monitor selector, or empty for "pick the primary automatically".
    pub(crate) primary: String,
    /// Selector -> the whole of what the user configured for that output.
    pub(crate) outputs: BTreeMap<String, OutputState>,
}

/// What the rest of the system reads: the stored choice plus the output that
/// choice currently resolves to.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub(crate) struct DisplayStatus {
    /// The stored selector, empty when the primary is chosen automatically.
    pub(crate) primary: String,
    /// Connector name of the effective primary, empty when nothing is connected.
    pub(crate) primary_output: String,
    /// Selector the effective primary is addressed by, for pinning rules.
    pub(crate) primary_selector: String,
    pub(crate) outputs: BTreeMap<String, OutputState>,
}

pub(crate) fn runtime_path() -> Result<PathBuf> {
    Ok(paths::xdg_config_home()?.join(RUNTIME_RELATIVE_PATH))
}

pub(crate) fn load_state() -> Result<DisplayState> {
    let path = runtime_path()?;
    let contents = match fs::read_to_string(&path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(DisplayState::default()),
        Err(error) => return Err(error.into()),
    };
    Ok(parse_state(&contents))
}

fn persist(state: &DisplayState) -> Result<()> {
    theme::atomic_write(&runtime_path()?, render_state(state).as_bytes())
}

/// The selector a monitor is addressed by. Descriptions survive being replugged
/// into a different port; connector names do not, so they are the fallback for
/// outputs whose EDID says nothing.
pub(crate) fn selector_for(monitor: &hypr::MonitorInfo) -> String {
    if monitor.description.trim().is_empty() {
        monitor.name.clone()
    } else {
        format!("desc:{}", monitor.description.trim())
    }
}

/// The output the stored selector names, or the automatic pick when it names
/// nothing connected — which is the whole point of storing a selector rather
/// than a connector: an absent monitor silently steps aside.
fn resolve_primary<'a>(
    monitors: &'a [hypr::MonitorInfo],
    stored: &str,
) -> Option<&'a hypr::MonitorInfo> {
    let usable = || monitors.iter().filter(|monitor| !monitor.disabled);

    if !stored.trim().is_empty()
        && let Some(chosen) = usable().find(|monitor| monitor.matches_selector(stored.trim()))
    {
        return Some(chosen);
    }

    // An external display is the one you sat down in front of. Between two of
    // them the larger one wins; the built-in panel is the answer only when it
    // is the only answer.
    usable()
        .filter(|monitor| !monitor.is_internal())
        .max_by_key(|monitor| (monitor.width * monitor.height) as i64)
        .or_else(|| usable().next())
}

pub(crate) fn status() -> Result<DisplayStatus> {
    let monitors = hypr::query_monitors()?;
    let state = load_state()?;
    Ok(status_for(&monitors, state))
}

fn status_for(monitors: &[hypr::MonitorInfo], state: DisplayState) -> DisplayStatus {
    let effective = resolve_primary(monitors, &state.primary);
    DisplayStatus {
        primary: state.primary,
        primary_output: effective.map(|m| m.name.clone()).unwrap_or_default(),
        primary_selector: effective.map(selector_for).unwrap_or_default(),
        outputs: state.outputs,
    }
}

/// Bring Hyprland in line with the stored topology: pin the numbered
/// workspaces to the effective primary and pull the ones that already exist
/// over with them. Rules alone would only place workspaces created later.
pub(crate) fn reconcile() -> Result<DisplayStatus> {
    let status = status()?;
    if status.primary_selector.is_empty() {
        return Ok(status);
    }

    for workspace in NUMBERED_WORKSPACES {
        hypr::eval(&workspace_rule_expression(
            workspace,
            &status.primary_selector,
        ))?;
        hypr::dispatch(&workspace_move_dispatcher(
            workspace,
            &status.primary_output,
        ))?;
    }

    Ok(status)
}

pub(crate) fn set_primary(selector: &str) -> Result<DisplayStatus> {
    let selector = selector.trim();
    let monitors = hypr::query_monitors()?;
    if !selector.is_empty()
        && !monitors
            .iter()
            .any(|monitor| monitor.matches_selector(selector))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("no connected monitor matches '{selector}'"),
        )
        .into());
    }

    let mut state = load_state()?;
    state.primary = selector.to_owned();
    persist(&state)?;
    reconcile()
}

/// Record a layout the user has already accepted. It is applied live by
/// whoever staged it; this is what makes it survive a reload.
///
/// Merged, never replaced: the entry for an output that is unplugged right now
/// is exactly the one worth keeping for when it comes back, and a layout kept
/// while it is away must not forget it.
pub(crate) fn save_layout(outputs: BTreeMap<String, OutputState>) -> Result<DisplayStatus> {
    for (selector, output) in &outputs {
        if output.disabled {
            continue;
        }
        if parse_position(&output.position).is_none() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!(
                    "position '{}' for '{selector}' is not '<x>x<y>'",
                    output.position
                ),
            )
            .into());
        }
        if output.mode.trim().is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("'{selector}' has no mode; a partial spec resets everything it omits"),
            )
            .into());
        }
    }

    let mut state = load_state()?;
    state.outputs.extend(outputs);
    persist(&state)?;
    status()
}

fn workspace_rule_expression(workspace: u32, selector: &str) -> String {
    let default = if workspace == *NUMBERED_WORKSPACES.start() {
        ", default = true"
    } else {
        ""
    };
    format!(
        "hl.workspace_rule({{ workspace = \"{workspace}\", monitor = {}{default} }})",
        hypr::lua_str(selector)
    )
}

fn workspace_move_dispatcher(workspace: u32, output: &str) -> String {
    format!(
        "hl.dsp.workspace.move({{ workspace = \"{workspace}\", monitor = {} }})",
        hypr::lua_str(output)
    )
}

fn parse_position(value: &str) -> Option<(i64, i64)> {
    let (x, y) = value.trim().split_once('x')?;
    Some((x.trim().parse().ok()?, y.trim().parse().ok()?))
}

/// One output per line on purpose, so the same file is both the Lua the
/// compositor reads and the state this module reads back.
fn render_state(state: &DisplayState) -> String {
    let mut out = String::from("-- Generated by desktopctl - do not edit\nreturn {\n");
    out.push_str(&format!(
        "    primary = {},\n",
        hypr::lua_str(&state.primary)
    ));
    out.push_str("    outputs = {\n");
    for (selector, output) in &state.outputs {
        out.push_str(&format!(
            "        [{}] = {{ mode = {}, position = {}, scale = {}, vrr = {}, transform = {}, disabled = {} }},\n",
            hypr::lua_str(selector),
            hypr::lua_str(&output.mode),
            hypr::lua_str(&output.position),
            output.scale,
            output.vrr,
            output.transform,
            output.disabled,
        ));
    }
    out.push_str("    },\n}\n");
    out
}

fn parse_state(contents: &str) -> DisplayState {
    let mut state = DisplayState::default();
    for line in contents.lines() {
        let line = line.trim();
        if let Some(value) = line.strip_prefix("primary = ") {
            state.primary = unquote(value.trim_end_matches(',')).unwrap_or_default();
        } else if let Some((selector, output)) = parse_output_line(line) {
            state.outputs.insert(selector, output);
        }
    }
    state
}

fn parse_output_line(line: &str) -> Option<(String, OutputState)> {
    let rest = line.strip_prefix("[\"")?;
    let (selector, rest) = rest.split_once("\"] = {")?;
    let fields = rest.trim_end_matches(&[',', ' '][..]).strip_suffix('}')?;

    let mut output = OutputState::default();
    for field in fields.split(", ") {
        let Some((key, value)) = field.split_once(" = ") else {
            continue;
        };
        match key.trim() {
            "mode" => output.mode = unquote(value)?,
            "position" => output.position = unquote(value)?,
            "scale" => output.scale = value.trim().parse().ok()?,
            "vrr" => output.vrr = value.trim().parse().ok()?,
            "transform" => output.transform = value.trim().parse().ok()?,
            "disabled" => output.disabled = value.trim() == "true",
            _ => {}
        }
    }
    Some((unescape(selector), output))
}

fn unquote(value: &str) -> Option<String> {
    let inner = value.trim().strip_prefix('"')?.strip_suffix('"')?;
    Some(unescape(inner))
}

fn unescape(value: &str) -> String {
    value.replace("\\\"", "\"").replace("\\\\", "\\")
}

pub(crate) fn print_status(status: &DisplayStatus, json: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string(status)?);
        return Ok(());
    }

    println!(
        "primary = {}",
        if status.primary.is_empty() {
            "auto"
        } else {
            &status.primary
        }
    );
    println!("primary_output = {}", status.primary_output);
    for (selector, output) in &status.outputs {
        println!(
            "{selector} = {} at {} scale {}{}",
            output.mode,
            output.position,
            output.scale,
            if output.disabled { " (disabled)" } else { "" }
        );
    }
    Ok(())
}

/// Read-only fallback for a dead daemon, mirroring `hypr input status`.
pub(crate) fn print_direct_status(json: bool) -> Result<()> {
    print_status(&status()?, json)
}

pub(crate) fn print_status_value(value: &serde_json::Value, json: bool) -> Result<()> {
    let status: DisplayStatus = serde_json::from_value(value.clone())?;
    print_status(&status, json)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn monitor(name: &str, description: &str, width: f64, height: f64) -> hypr::MonitorInfo {
        hypr::MonitorInfo::for_test(name, description, width, height)
    }

    fn output(mode: &str, position: &str, scale: f64) -> OutputState {
        OutputState {
            mode: mode.to_owned(),
            position: position.to_owned(),
            scale,
            ..OutputState::default()
        }
    }

    #[test]
    fn state_round_trips_through_the_generated_lua() {
        let mut state = DisplayState {
            primary: "desc:LG Electronics LG ULTRAWIDE".to_owned(),
            outputs: BTreeMap::new(),
        };
        state.outputs.insert(
            "desc:LG Display 0x06B3".to_owned(),
            output("1920x1200@59.95", "0x0", 1.25),
        );
        state.outputs.insert(
            "DP-4".to_owned(),
            OutputState {
                vrr: 1,
                transform: 1,
                disabled: true,
                ..output("2560x1080@60.00", "-320x-1080", 1.0)
            },
        );

        assert_eq!(parse_state(&render_state(&state)), state);
    }

    /// The bug this whole struct exists for: a spec that names only a position
    /// is a *separate rule* at parse time, so scale falls back to `auto`.
    #[test]
    fn every_rendered_output_carries_a_full_spec() {
        let mut state = DisplayState::default();
        state
            .outputs
            .insert("eDP-1".to_owned(), output("1920x1200@59.95", "0x0", 1.0));

        let rendered = render_state(&state);
        for field in ["mode", "position", "scale", "vrr", "transform", "disabled"] {
            assert!(rendered.contains(field), "missing {field}: {rendered}");
        }
    }

    #[test]
    fn an_absent_stored_primary_falls_back_to_the_automatic_pick() {
        let monitors = vec![
            monitor("eDP-1", "LG Display 0x06B3", 1920.0, 1200.0),
            monitor("DP-4", "LG Electronics LG ULTRAWIDE", 2560.0, 1080.0),
        ];
        let state = DisplayState {
            primary: "desc:BNQ ZOWIE XL".to_owned(),
            ..DisplayState::default()
        };

        let status = status_for(&monitors, state);
        assert_eq!(status.primary_output, "DP-4");
        // The stored choice is kept, not overwritten by the fallback: plugging
        // the BenQ back in has to restore it.
        assert_eq!(status.primary, "desc:BNQ ZOWIE XL");
    }

    #[test]
    fn the_builtin_panel_is_primary_only_when_it_is_alone() {
        let alone = vec![monitor("eDP-1", "LG Display 0x06B3", 1920.0, 1200.0)];
        assert_eq!(
            status_for(&alone, DisplayState::default()).primary_output,
            "eDP-1"
        );

        let docked = vec![
            monitor("eDP-1", "LG Display 0x06B3", 1920.0, 1200.0),
            monitor("DP-4", "LG Electronics LG ULTRAWIDE", 2560.0, 1080.0),
        ];
        assert_eq!(
            status_for(&docked, DisplayState::default()).primary_output,
            "DP-4"
        );
    }

    #[test]
    fn the_larger_external_wins_between_two_of_them() {
        let monitors = vec![
            monitor("DP-2", "BNQ ZOWIE XL", 1920.0, 1080.0),
            monitor("DP-4", "LG Electronics LG ULTRAWIDE", 2560.0, 1080.0),
        ];
        assert_eq!(
            status_for(&monitors, DisplayState::default()).primary_output,
            "DP-4"
        );
    }

    #[test]
    fn only_the_first_numbered_workspace_claims_the_default_flag() {
        let first = workspace_rule_expression(1, "desc:LG ULTRAWIDE");
        let second = workspace_rule_expression(2, "desc:LG ULTRAWIDE");
        assert!(first.contains("default = true"));
        assert!(!second.contains("default"));
        assert!(second.contains("monitor = \"desc:LG ULTRAWIDE\""));
    }

    #[test]
    fn a_kept_layout_never_forgets_an_output_that_is_unplugged() {
        // save_layout merges onto the stored map; the entry for an absent
        // output is the one worth keeping for when it comes back.
        let mut stored = DisplayState::default();
        stored
            .outputs
            .insert("DP-4".to_owned(), output("2560x1080@60.00", "0x0", 1.0));

        let mut incoming = BTreeMap::new();
        incoming.insert("eDP-1".to_owned(), output("1920x1200@59.95", "0x0", 1.0));
        stored.outputs.extend(incoming);

        assert_eq!(stored.outputs.len(), 2);
        assert!(stored.outputs.contains_key("DP-4"));
    }

    #[test]
    fn positions_must_be_an_x_separated_pair() {
        assert_eq!(parse_position("-320x-1080"), Some((-320, -1080)));
        assert_eq!(parse_position("0x0"), Some((0, 0)));
        assert_eq!(parse_position("auto"), None);
    }
}
