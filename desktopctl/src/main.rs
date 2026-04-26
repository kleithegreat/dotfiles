mod brightness;
mod daemon;
mod hypr;
mod launch;
mod night_light;
mod paths;
mod portal;
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
    /// Run xdg-desktop-portal helper commands.
    Portal(PortalArgs),
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
    All,
    /// Apply all sync-safe targets for activation-time usage.
    Sync,
    /// Apply color-dependent targets.
    Colors,
    /// Apply only the wallpaper target.
    Wallpaper,
    /// Apply only the cursor target.
    Cursor,
    /// Apply font-dependent targets.
    Fonts,
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
}

#[derive(Debug, Args)]
struct SetArgs {
    /// Theme state key to update.
    key: String,
    /// New value for the provided key.
    #[arg(allow_hyphen_values = true)]
    value: String,
}

#[derive(Debug, Args)]
struct NamedArg {
    /// Name of the preset to operate on.
    name: String,
}

#[derive(Debug, Args)]
struct SavePresetArgs {
    /// Preset name to create or overwrite.
    name: String,
    /// JSON object payload for the preset patch.
    #[arg(value_name = "JSON")]
    payload: String,
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
    /// Override the auto-detected backlight device.
    #[arg(long, value_name = "DEVICE")]
    device: Option<String>,
}

#[derive(Debug, Args)]
struct BrightnessSetArgs {
    /// Brightness percent, clamped to 0-100.
    percent: u8,
    /// Override the auto-detected device. Use a backlight name, `ddc`, or `ddc:<display>`.
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
    /// Inspect and update managed Hyprland input settings.
    Input(HyprInputArgs),
    /// Persist or clear animation override state.
    Animations(HyprAnimationsArgs),
    /// Persist or clear keybind override state.
    Keybinds(HyprKeybindsArgs),
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
#[command(arg_required_else_help = true, subcommand_required = true)]
struct HyprKeybindsArgs {
    #[command(subcommand)]
    command: HyprKeybindsCommand,
}

#[derive(Debug, Subcommand)]
enum HyprKeybindsCommand {
    /// Write keybind overrides from a JSON payload to the managed config file.
    Save(HyprJsonPayloadArgs),
    /// Clear all keybind overrides and reload Hyprland.
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
struct PortalArgs {
    #[command(subcommand)]
    command: PortalCommand,
}

#[derive(Debug, Subcommand)]
enum PortalCommand {
    /// Open a directory picker and print the selected path.
    PickDirectory,
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
        TopLevelCommand::Portal(args) => run_portal(args),
        TopLevelCommand::Daemon => daemon::run(),
        TopLevelCommand::Theme(args) => theme::run(args),
        TopLevelCommand::Sun(args) => run_sun(args),
    }
}

fn run_brightness(args: BrightnessArgs) -> Result<()> {
    match args.command {
        BrightnessCommand::Status(args) => brightness::status(args.json),
        BrightnessCommand::Set(args) => brightness::set(args.device.as_deref(), args.percent),
        BrightnessCommand::Up(args) => brightness::up(args.device.as_deref()),
        BrightnessCommand::Down(args) => brightness::down(args.device.as_deref()),
        BrightnessCommand::Dim(args) => brightness::dim(args.device.as_deref()),
        BrightnessCommand::Restore(args) => brightness::restore(args.device.as_deref()),
    }
}

fn run_hypr(args: HyprArgs) -> Result<()> {
    match args.command {
        HyprCommand::ToggleFloat => hypr::toggle_float(),
        HyprCommand::Input(args) => run_hypr_input(args),
        HyprCommand::Animations(args) => run_hypr_animations(args),
        HyprCommand::Keybinds(args) => run_hypr_keybinds(args),
    }
}

fn run_hypr_animations(args: HyprAnimationsArgs) -> Result<()> {
    match args.command {
        HyprAnimationsCommand::Save(args) => hypr::save_animations(&args.payload),
        HyprAnimationsCommand::Clear => hypr::clear_animations(),
    }
}

fn run_hypr_keybinds(args: HyprKeybindsArgs) -> Result<()> {
    match args.command {
        HyprKeybindsCommand::Save(args) => hypr::save_keybinds(&args.payload),
        HyprKeybindsCommand::Clear => hypr::clear_keybinds(),
    }
}

fn run_hypr_input(args: HyprInputArgs) -> Result<()> {
    match args.command {
        HyprInputCommand::Status(args) => hypr::print_input_status(args.json),
        HyprInputCommand::Set(args) => {
            let setting = hypr::InputSetting::parse(&args.key)?;
            hypr::set_input_value(setting, &args.value)
        }
    }
}

fn run_portal(args: PortalArgs) -> Result<()> {
    match args.command {
        PortalCommand::PickDirectory => {
            if let Some(path) = portal::pick_directory()? {
                println!("{path}");
            }

            Ok(())
        }
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
    fn theme_set_accepts_negative_values_without_double_dash() {
        let cli = Cli::try_parse_from([
            "desktopctl",
            "theme",
            "set",
            "chromium_font_size_offset",
            "-1",
        ])
        .expect("cli should parse");

        let TopLevelCommand::Theme(theme_args) = cli.command else {
            panic!("expected theme command");
        };
        let ThemeCommand::Set(set_args) = theme_args.command else {
            panic!("expected theme set command");
        };
        assert_eq!(set_args.key, "chromium_font_size_offset");
        assert_eq!(set_args.value, "-1");
    }

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
}
