mod brightness;
mod daemon;
mod hypr;
mod ipc;
mod launch;
mod night_light;
mod paths;
mod solar;
#[cfg(test)]
mod test_support;
mod theme;

use clap::{Args, Parser, Subcommand};
use std::process::ExitCode;

#[derive(Debug, Parser)]
#[command(
    name = "desktopctl",
    version,
    about = "Unified desktop daemon and CLI for the dotfiles desktop stack",
    long_about = None,
    arg_required_else_help = true,
    subcommand_required = true,
    propagate_version = true
)]
struct Cli {
    #[command(subcommand)]
    command: TopLevelCommand,
}

#[derive(Debug, Subcommand)]
enum TopLevelCommand {
    /// Start the desktop daemon in the foreground.
    Daemon,
    /// Apply and inspect desktop theme state.
    Theme(ThemeArgs),
    /// Control brightness helpers and display state.
    Brightness(BrightnessArgs),
    /// Run Hyprland helper commands.
    Hypr(HyprArgs),
    /// Export cursor variables and launch Quickshell.
    LaunchQuickshell(LaunchQuickshellArgs),
    /// Inspect and control night-light override state.
    NightLight(NightLightArgs),
    /// Inspect solar scheduling state.
    Sun(SunArgs),
}

#[derive(Debug, Args)]
#[command(arg_required_else_help = true, subcommand_required = true)]
struct ThemeArgs {
    #[command(subcommand)]
    command: ThemeCommand,
}

#[derive(Debug, Subcommand)]
enum ThemeCommand {
    /// Apply all theme targets.
    All(WaitDaemonArgs),
    /// Apply all sync-safe targets for activation-time usage.
    Sync,
    /// Apply color-dependent targets.
    Colors(WaitDaemonArgs),
    /// Apply only the wallpaper target.
    Wallpaper(WaitDaemonArgs),
    /// Apply only the cursor target.
    Cursor(WaitDaemonArgs),
    /// Apply font-dependent targets.
    Fonts(WaitDaemonArgs),
    /// Apply one target by registry name.
    Target(TargetArgs),
    /// Update one theme-state key and apply affected targets.
    Set(SetArgs),
    /// Load a preset and apply all targets.
    Preset(NamedArg),
    /// Save a preset from a JSON patch payload.
    SavePreset(SavePresetArgs),
    /// Delete a preset by name.
    DeletePreset(NamedArg),
    /// List available color schemes.
    ListSchemes(JsonOutputArgs),
    /// List wallpapers and cached preview paths.
    ListWallpapers(ListWallpapersArgs),
    /// List available presets.
    ListPresets(JsonOutputArgs),
    /// Show the current theme state.
    Status(JsonOutputArgs),
    /// Print the current state in `styling/state.json` seed format.
    Export,
}

/// Shared by daemon-routed write subcommands, mainly for autostart call
/// sites racing the daemon's own startup.
#[derive(Debug, Args)]
struct WaitDaemonArgs {
    /// Retry connecting to the daemon for up to this many seconds.
    #[arg(long, value_name = "SECS", default_value_t = 0)]
    wait_daemon: u64,
}

#[derive(Debug, Args)]
struct ListWallpapersArgs {
    /// Print machine-readable JSON instead of human-readable text.
    #[arg(long)]
    json: bool,
    /// Directory to scan for wallpaper files. Defaults to the current wallpaper directory.
    #[arg(long, value_name = "DIR")]
    directory: Option<String>,
}

#[derive(Debug, Args)]
struct TargetArgs {
    /// Target name from the theme registry.
    name: String,
    #[command(flatten)]
    wait: WaitDaemonArgs,
}

#[derive(Debug, Args)]
struct SetArgs {
    /// Theme state key to update.
    key: String,
    /// New value for the provided key.
    #[arg(allow_hyphen_values = true)]
    value: String,
    #[command(flatten)]
    wait: WaitDaemonArgs,
}

#[derive(Debug, Args)]
struct NamedArg {
    /// Name of the preset to operate on.
    name: String,
    #[command(flatten)]
    wait: WaitDaemonArgs,
}

#[derive(Debug, Args)]
struct SavePresetArgs {
    /// Preset name to create or overwrite.
    name: String,
    /// JSON object payload for the preset patch.
    #[arg(value_name = "JSON")]
    payload: String,
    #[command(flatten)]
    wait: WaitDaemonArgs,
}

#[derive(Debug, Args)]
struct JsonOutputArgs {
    /// Print machine-readable JSON instead of human-readable text.
    #[arg(long)]
    json: bool,
}

#[derive(Debug, Args)]
#[command(arg_required_else_help = true, subcommand_required = true)]
struct BrightnessArgs {
    #[command(subcommand)]
    command: BrightnessCommand,
}

#[derive(Debug, Subcommand)]
enum BrightnessCommand {
    /// Print the currently selected brightness device and value.
    Status(JsonOutputArgs),
    /// Set brightness to an absolute perceived percent.
    Set(BrightnessSetArgs),
    /// Increase brightness by one perceptual 5% step.
    Up(BrightnessDeviceArgs),
    /// Decrease brightness by one perceptual 5% step.
    Down(BrightnessDeviceArgs),
    /// Gradually dim the screen for idle handling.
    Dim(BrightnessDeviceArgs),
    /// Restore the previously saved brightness level.
    Restore(BrightnessDeviceArgs),
}

#[derive(Debug, Args)]
struct BrightnessDeviceArgs {
    /// Override the auto-detected device. Use a backlight name, `ddc`, or `ddc:<i2c-bus>`.
    #[arg(long, value_name = "DEVICE")]
    device: Option<String>,
}

#[derive(Debug, Args)]
struct BrightnessSetArgs {
    /// Brightness percent, clamped to 0-100.
    percent: u16,
    /// Override the auto-detected device. Use a backlight name, `ddc`, or `ddc:<i2c-bus>`.
    #[arg(long, value_name = "DEVICE")]
    device: Option<String>,
}

#[derive(Debug, Args)]
#[command(arg_required_else_help = true, subcommand_required = true)]
struct HyprArgs {
    #[command(subcommand)]
    command: HyprCommand,
}

#[derive(Debug, Subcommand)]
enum HyprCommand {
    /// Toggle floating and recenter when promoting a tiled window.
    ToggleFloat,
    /// Apply the laptop lid-switch monitor policy.
    LidSwitch(HyprLidSwitchArgs),
    /// Focus the numbered workspace set when its pins target an absent monitor.
    ReclaimWorkspaces,
    /// Inspect and update managed Hyprland input settings.
    Input(HyprInputArgs),
    /// Persist or clear animation override state.
    Animations(HyprAnimationsArgs),
}

#[derive(Debug, Args)]
struct HyprLidSwitchArgs {
    /// Lid state to apply: open, closed, or sync.
    state: String,
    /// Internal display connector to disable/re-enable.
    #[arg(long, default_value = "eDP-1", value_name = "MONITOR")]
    internal: String,
    /// Hyprland monitor spec used when the lid opens.
    #[arg(long, default_value = "preferred,auto,1", value_name = "SPEC")]
    open_spec: String,
}

#[derive(Debug, Args)]
#[command(arg_required_else_help = true, subcommand_required = true)]
struct HyprInputArgs {
    #[command(subcommand)]
    command: HyprInputCommand,
}

#[derive(Debug, Subcommand)]
enum HyprInputCommand {
    /// Show the effective managed Hyprland input settings.
    Status(JsonOutputArgs),
    /// Persist and apply one managed Hyprland input setting.
    Set(HyprInputSetArgs),
}

#[derive(Debug, Args)]
struct HyprInputSetArgs {
    /// Managed Hyprland input setting to update.
    key: String,
    /// New value for the provided setting.
    #[arg(allow_hyphen_values = true)]
    value: String,
}

#[derive(Debug, Args)]
#[command(arg_required_else_help = true, subcommand_required = true)]
struct HyprAnimationsArgs {
    #[command(subcommand)]
    command: HyprAnimationsCommand,
}

#[derive(Debug, Subcommand)]
enum HyprAnimationsCommand {
    /// Write animation overrides from a JSON payload to the managed config file.
    Save(HyprJsonPayloadArgs),
    /// Clear all animation overrides and reload Hyprland.
    Clear,
}

#[derive(Debug, Args)]
struct HyprJsonPayloadArgs {
    /// JSON payload describing the overrides.
    #[arg(value_name = "JSON")]
    payload: String,
}

#[derive(Debug, Args)]
struct LaunchQuickshellArgs {
    /// Print XCURSOR_THEME|HYPRCURSOR_THEME|XCURSOR_SIZE and exit.
    #[arg(long)]
    print_env: bool,
}

#[derive(Debug, Args)]
#[command(arg_required_else_help = true, subcommand_required = true)]
struct NightLightArgs {
    #[command(subcommand)]
    command: NightLightCommand,
}

#[derive(Debug, Subcommand)]
enum NightLightCommand {
    /// Show daemon-controlled night-light status.
    Status(JsonOutputArgs),
    /// Force night light on until reset to auto.
    On(NightLightTempArgs),
    /// Force night light off until reset to auto.
    Off(NightLightTempArgs),
    /// Hand control back to the solar schedule.
    Auto(NightLightTempArgs),
    /// Switch between on and off based on the current hyprsunset state.
    Toggle,
}

#[derive(Debug, Args)]
struct NightLightTempArgs {
    /// Override the target temperature in Kelvin.
    #[arg(long, value_name = "K")]
    temp: Option<i32>,
}

#[derive(Debug, Args)]
#[command(arg_required_else_help = true, subcommand_required = true)]
struct SunArgs {
    #[command(subcommand)]
    command: SunCommand,
}

#[derive(Debug, Subcommand)]
enum SunCommand {
    /// Print sunrise/sunset times, the current state, and next events.
    Status,
}

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            let message = error.to_string();
            if !message.is_empty() {
                eprintln!("{message}");
            }
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        TopLevelCommand::Brightness(args) => run_brightness(args),
        TopLevelCommand::Hypr(args) => run_hypr(args),
        TopLevelCommand::LaunchQuickshell(args) => launch::run(args.print_env),
        TopLevelCommand::NightLight(args) => night_light::run(args),
        TopLevelCommand::Daemon => daemon::run(),
        TopLevelCommand::Theme(args) => theme::run(args),
        TopLevelCommand::Sun(args) => run_sun(args),
    }
}

// Writes are daemon-routed and hard-fail when it is unreachable: the daemon
// owns the dim/restore state, so a direct write would be a second writer.
fn run_brightness(args: BrightnessArgs) -> Result<()> {
    match args.command {
        BrightnessCommand::Status(args) => run_brightness_status(args.json),
        BrightnessCommand::Set(args) => strict_request(
            ipc::methods::BRIGHTNESS_SET,
            serde_json::json!({ "device": args.device, "percent": args.percent }),
        ),
        BrightnessCommand::Up(args) => strict_request(
            ipc::methods::BRIGHTNESS_STEP,
            serde_json::json!({ "device": args.device, "direction": "up" }),
        ),
        BrightnessCommand::Down(args) => strict_request(
            ipc::methods::BRIGHTNESS_STEP,
            serde_json::json!({ "device": args.device, "direction": "down" }),
        ),
        BrightnessCommand::Dim(args) => strict_request(
            ipc::methods::BRIGHTNESS_DIM,
            serde_json::json!({ "device": args.device }),
        ),
        BrightnessCommand::Restore(args) => strict_request(
            ipc::methods::BRIGHTNESS_RESTORE,
            serde_json::json!({ "device": args.device }),
        ),
    }
}

fn run_brightness_status(json: bool) -> Result<()> {
    match ipc::send_request::<(), serde_json::Value>(
        ipc::methods::BRIGHTNESS_STATUS,
        None,
        ipc::DEFAULT_TIMEOUT,
    ) {
        Ok(payload) => {
            if json {
                println!("{}", serde_json::to_string(&payload)?);
            } else {
                println!(
                    "{}: {}%",
                    payload["label"].as_str().unwrap_or("brightness"),
                    payload["percent"].as_u64().unwrap_or(0)
                );
            }
            Ok(())
        }
        Err(error) if ipc::socket_unavailable(error.as_ref()) => brightness::status(json),
        Err(error) => Err(error),
    }
}

/// Send a daemon mutation, converting a missing daemon into the strict-mode
/// failure message. The response payload is discarded; the exit code is the
/// contract.
fn strict_request(method: &str, params: serde_json::Value) -> Result<()> {
    ipc::send_request::<serde_json::Value, serde_json::Value>(
        method,
        Some(params),
        ipc::DEFAULT_TIMEOUT,
    )
    .map(|_response| ())
    .map_err(|error| {
        if ipc::socket_unavailable(error.as_ref()) {
            std::io::Error::other(ipc::daemon_unavailable_message(&error)).into()
        } else {
            error
        }
    })
}

fn run_hypr(args: HyprArgs) -> Result<()> {
    match args.command {
        HyprCommand::ToggleFloat => hypr::toggle_float(),
        HyprCommand::LidSwitch(args) => {
            let state = hypr::LidSwitchState::parse(&args.state)?;
            hypr::handle_lid_switch(state, &args.internal, &args.open_spec)
        }
        HyprCommand::ReclaimWorkspaces => hypr::reclaim_workspaces(),
        HyprCommand::Input(args) => run_hypr_input(args),
        HyprCommand::Animations(args) => run_hypr_animations(args),
    }
}

fn run_hypr_animations(args: HyprAnimationsArgs) -> Result<()> {
    match args.command {
        HyprAnimationsCommand::Save(args) => strict_request(
            ipc::methods::HYPR_ANIMATIONS_SAVE,
            serde_json::json!({ "payload": parse_payload_json(&args.payload)? }),
        ),
        HyprAnimationsCommand::Clear => {
            strict_request(ipc::methods::HYPR_ANIMATIONS_CLEAR, serde_json::json!({}))
        }
    }
}

fn parse_payload_json(raw: &str) -> Result<serde_json::Value> {
    serde_json::from_str(raw)
        .map_err(|error| std::io::Error::other(format!("invalid JSON payload: {error}")).into())
}

fn run_hypr_input(args: HyprInputArgs) -> Result<()> {
    match args.command {
        HyprInputCommand::Status(args) => {
            match ipc::send_request::<(), serde_json::Value>(
                ipc::methods::HYPR_INPUT_STATUS,
                None,
                ipc::DEFAULT_TIMEOUT,
            ) {
                Ok(state) => hypr::print_input_state_value(&state, args.json),
                Err(error) if ipc::socket_unavailable(error.as_ref()) => {
                    hypr::print_input_status(args.json)
                }
                Err(error) => Err(error),
            }
        }
        HyprInputCommand::Set(args) => strict_request(
            ipc::methods::HYPR_INPUT_SET,
            serde_json::json!({ "key": args.key, "value": args.value }),
        ),
    }
}

fn run_sun(args: SunArgs) -> Result<()> {
    match args.command {
        SunCommand::Status => solar::print_status(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hypr_input_set_accepts_negative_values_without_double_dash() {
        let cli =
            Cli::try_parse_from(["desktopctl", "hypr", "input", "set", "sensitivity", "-0.1"])
                .expect("cli should parse");

        let TopLevelCommand::Hypr(hypr_args) = cli.command else {
            panic!("expected hypr command");
        };
        let HyprCommand::Input(input_args) = hypr_args.command else {
            panic!("expected hypr input command");
        };
        let HyprInputCommand::Set(set_args) = input_args.command else {
            panic!("expected hypr input set command");
        };
        assert_eq!(set_args.key, "sensitivity");
        assert_eq!(set_args.value, "-0.1");
    }

    #[test]
    fn brightness_set_accepts_values_above_one_hundred_for_clamping() {
        let cli = Cli::try_parse_from(["desktopctl", "brightness", "set", "300"])
            .expect("cli should parse clamped brightness values");

        let TopLevelCommand::Brightness(brightness_args) = cli.command else {
            panic!("expected brightness command");
        };
        let BrightnessCommand::Set(set_args) = brightness_args.command else {
            panic!("expected brightness set command");
        };
        assert_eq!(set_args.percent, 300);
    }
}
