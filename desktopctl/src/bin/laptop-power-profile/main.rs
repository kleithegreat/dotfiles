//! Power-profile helper for the laptop host's hybrid CPU.
//!
//! Deliberately a separate binary rather than a `desktopctl` subcommand: the
//! laptop's polkit rule (hosts/laptop/system.nix) grants passwordless pkexec by
//! matching the program path, so folding these commands into the `desktopctl`
//! binary would hand every desktopctl subcommand passwordless root along with
//! them. The CLI surface is the one the Quickshell power popup already calls —
//! `get`, and `set <profile>` — so it stays compatible with the shell script it
//! replaces.

mod power_profile;

use clap::{Parser, Subcommand};
use power_profile::{CPU_ROOT, Profile};
use std::{path::Path, process::ExitCode};

#[derive(Debug, Parser)]
#[command(
    name = "laptop-power-profile",
    version,
    about = "Read and set the power profile on a hybrid P-core/E-core laptop",
    long_about = None,
    arg_required_else_help = true,
    subcommand_required = true
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Print the active profile.
    Get,
    /// Switch to a profile.
    Set {
        /// Profile to activate.
        #[arg(value_enum)]
        profile: Profile,
    },
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("laptop-power-profile: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> power_profile::Result<()> {
    let cli = Cli::parse();
    let root = Path::new(CPU_ROOT);

    match cli.command {
        Command::Get => {
            println!("{}", power_profile::current(root)?);
            Ok(())
        }
        Command::Set { profile } => power_profile::apply(root, profile),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_parses_every_profile_the_shell_offered() {
        for (argument, expected) in [
            ("performance", Profile::Performance),
            ("balanced", Profile::Balanced),
            ("power-saver", Profile::PowerSaver),
            ("e-core-only", Profile::ECoreOnly),
        ] {
            let cli = Cli::try_parse_from(["laptop-power-profile", "set", argument])
                .expect("profile should parse");

            let Command::Set { profile } = cli.command else {
                panic!("expected set command");
            };
            assert_eq!(profile, expected);
        }
    }

    #[test]
    fn unknown_profiles_and_bare_invocations_are_rejected() {
        assert!(Cli::try_parse_from(["laptop-power-profile", "set", "turbo"]).is_err());
        assert!(Cli::try_parse_from(["laptop-power-profile", "set"]).is_err());
        assert!(Cli::try_parse_from(["laptop-power-profile"]).is_err());
    }

    #[test]
    fn get_takes_no_arguments() {
        assert!(Cli::try_parse_from(["laptop-power-profile", "get"]).is_ok());
        assert!(Cli::try_parse_from(["laptop-power-profile", "get", "extra"]).is_err());
    }
}
