mod hypr;
mod paths;

use clap::{Args, Parser, Subcommand};

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
    /// List available presets.
    ListPresets(JsonOutputArgs),
    /// Show the current theme state.
    Status(JsonOutputArgs),
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
    /// Increase brightness by one perceptual 5% step.
    Up(BrightnessDeviceArgs),
    /// Decrease brightness by one perceptual 5% step.
    Down(BrightnessDeviceArgs),
    /// Gradually dim the screen for idle handling.
    Dim(BrightnessDeviceArgs),
    /// Restore the previously saved brightness level.
    Restore,
    /// Write the current brightness state to the Quickshell cache file.
    Seed(BrightnessDeviceArgs),
}

#[derive(Debug, Args)]
struct BrightnessDeviceArgs {
    /// Override the auto-detected backlight device.
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
struct SunArgs {
    #[command(subcommand)]
    command: SunCommand,
}

#[derive(Debug, Subcommand)]
enum SunCommand {
    /// Print sunrise/sunset times, the current state, and next events.
    Status,
}

fn main() {
    let _cli = Cli::parse();
    eprintln!("desktopctl subcommand logic is not implemented yet in Phase 0");
    std::process::exit(1);
}
