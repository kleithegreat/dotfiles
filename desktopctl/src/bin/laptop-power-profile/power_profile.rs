//! Power-profile control for a hybrid-core (P-core + E-core) laptop.
//!
//! Every entry point takes the CPU sysfs root as an argument rather than
//! reaching for [`CPU_ROOT`] directly, so the topology walks can be exercised
//! against a fake tree instead of the running machine.

use clap::ValueEnum;
use std::{
    fs, io,
    path::{Path, PathBuf},
    process::{Command, Output},
};

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

pub const CPU_ROOT: &str = "/sys/devices/system/cpu";

#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
pub enum Profile {
    /// power-profiles-daemon `performance`.
    #[value(name = "performance")]
    Performance,
    /// power-profiles-daemon `balanced`.
    #[value(name = "balanced")]
    Balanced,
    /// power-profiles-daemon `power-saver`.
    #[value(name = "power-saver")]
    PowerSaver,
    /// `power-saver` with every P-core thread offlined.
    #[value(name = "e-core-only")]
    ECoreOnly,
}

impl Profile {
    /// The name this profile is known by to `powerprofilesctl`, to the polkit
    /// rule, and to the Quickshell power popup. Kept in sync with the
    /// `#[value(name = ...)]` spellings by `profile_names_match_value_enum`.
    pub fn as_str(self) -> &'static str {
        match self {
            Profile::Performance => "performance",
            Profile::Balanced => "balanced",
            Profile::PowerSaver => "power-saver",
            Profile::ECoreOnly => "e-core-only",
        }
    }
}

/// Parse a kernel cpulist (`0`, `0-1`, `0,4`, `0-3,8-11`) into its members.
///
/// Returns `None` for anything that does not parse, so a sysfs read that is not
/// a cpulist can never be mistaken for a single-entry list — which is what
/// decides P-core membership below.
pub fn parse_cpulist(value: &str) -> Option<Vec<u32>> {
    let mut cpus = Vec::new();

    for token in value.trim().split(',') {
        let token = token.trim();
        if token.is_empty() {
            continue;
        }

        match token.split_once('-') {
            Some((start, end)) => {
                let start: u32 = start.trim().parse().ok()?;
                let end: u32 = end.trim().parse().ok()?;
                if end < start {
                    return None;
                }
                cpus.extend(start..=end);
            }
            None => cpus.push(token.parse().ok()?),
        }
    }

    Some(cpus)
}

/// A CPU is a P-core thread iff it has SMT siblings, i.e. its thread sibling
/// list names more than just itself. The kernel emits cpulist ranges (`0-1`)
/// for adjacent siblings, so the list is parsed rather than compared as text.
pub fn is_p_core(siblings: &str) -> bool {
    parse_cpulist(siblings).is_some_and(|cpus| cpus.len() > 1)
}

/// Every `cpuN` directory under `root`, in numeric order. The number must parse
/// in full, which is what keeps siblings like `cpufreq` and `cpuidle` out.
pub fn cpu_numbers(root: &Path) -> Result<Vec<u32>> {
    let mut cpus = Vec::new();

    for entry in fs::read_dir(root)? {
        let name = entry?.file_name();
        let Some(number) = name
            .to_str()
            .and_then(|name| name.strip_prefix("cpu"))
            .and_then(|number| number.parse::<u32>().ok())
        else {
            continue;
        };
        cpus.push(number);
    }

    cpus.sort_unstable();
    Ok(cpus)
}

pub fn p_core_cpus(root: &Path) -> Result<Vec<u32>> {
    let mut cpus = Vec::new();

    for cpu in cpu_numbers(root)? {
        let siblings =
            match fs::read_to_string(cpu_path(root, cpu, "topology/thread_siblings_list")) {
                Ok(siblings) => siblings,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error.into()),
            };

        if is_p_core(&siblings) {
            cpus.push(cpu);
        }
    }

    Ok(cpus)
}

/// CPUs the kernel will let us offline. Boot CPUs have no `online` file at all,
/// which is why `set_cpu_online` tolerates its absence rather than failing.
pub fn hotpluggable_cpus(root: &Path) -> Result<Vec<u32>> {
    Ok(cpu_numbers(root)?
        .into_iter()
        .filter(|cpu| cpu_path(root, *cpu, "online").is_file())
        .collect())
}

/// Whether this machine has both core types.
///
/// `e-core-only` offlines every SMT thread, which on a uniform-SMT processor is
/// every core there is. desktopctl ships on every host, so this check — not the
/// packaging — is what keeps the helper inert on non-hybrid hardware.
pub fn is_hybrid(root: &Path) -> Result<bool> {
    let cpus = cpu_numbers(root)?;
    let p_cores = p_core_cpus(root)?;

    Ok(!p_cores.is_empty() && p_cores.len() < cpus.len())
}

/// Offlined CPUs lose their `topology/` sysfs group, so sibling-based detection
/// cannot work after the fact. This binary is the only thing offlining CPUs on
/// the host and every standard profile re-onlines everything first, so:
/// e-core-only is active iff any hotpluggable CPU is offline.
pub fn is_efficiency_mode(root: &Path) -> Result<bool> {
    for cpu in hotpluggable_cpus(root)? {
        if !is_online(root, cpu)? {
            return Ok(true);
        }
    }

    Ok(false)
}

pub fn current(root: &Path) -> Result<String> {
    // Before the topology check, not after. The mask this looks for is exactly
    // what makes that check fail: offlining the P-cores takes their `topology/`
    // group with it, so a machine sitting in e-core-only reads as non-hybrid and
    // `ensure_hybrid` would refuse to answer for the one profile it is in.
    if is_efficiency_mode(root)? {
        return Ok(Profile::ECoreOnly.as_str().to_owned());
    }

    ensure_hybrid(root)?;

    let output = powerprofilesctl(&["get"])?;
    Ok(String::from_utf8(output.stdout)?.trim().to_owned())
}

/// Bring every hotpluggable CPU back online, whatever profile is being applied.
///
/// Every profile starts from a fully-online machine: the P-core mask is only
/// readable while the cores are online, so e-core-only has to re-online before
/// it can work out what to offline, and the standard profiles have to undo
/// whatever mask a previous e-core-only left behind.
///
/// Runs before the `powerprofilesctl` call, never after: that command writes
/// `energy_performance_preference` for every policy, and an offlined core's
/// policy answers EBUSY.
fn unmask(root: &Path) -> Result<()> {
    ensure_manageable(root)?;

    for cpu in hotpluggable_cpus(root)? {
        set_cpu_online(root, cpu, true)?;
    }

    Ok(())
}

pub fn apply(root: &Path, profile: Profile) -> Result<()> {
    unmask(root)?;

    match profile {
        Profile::ECoreOnly => {
            // The authoritative topology check, deliberately here and not at the
            // top: the re-onlining above is what brings `topology/` back, and
            // this is the only arm that needs it — both to trust the machine is
            // hybrid and to read the mask off it. Leaving e-core-only asks sysfs
            // nothing, so it stays reachable even when the mask is what is
            // making the topology unreadable.
            ensure_hybrid(root)?;

            powerprofilesctl(&["set", Profile::PowerSaver.as_str()])?;
            for cpu in p_core_cpus(root)? {
                set_cpu_online(root, cpu, false)?;
            }
        }
        profile => {
            powerprofilesctl(&["set", profile.as_str()])?;
        }
    }

    Ok(())
}

fn ensure_hybrid(root: &Path) -> Result<()> {
    if is_hybrid(root)? {
        return Ok(());
    }

    Err(not_hybrid())
}

/// The gate `apply` opens with, before it has re-onlined anything. An active
/// mask passes on its own because it is proof of a topology `is_hybrid` can no
/// longer see — sound for the same reason [`is_efficiency_mode`] is sound: this
/// binary is the only thing that offlines CPUs here, and it only ever does so
/// once `ensure_hybrid` has already said yes.
///
/// Deliberately weaker than [`ensure_hybrid`], and never the check that guards
/// an offline: `apply` re-onlines and then runs the real check inside the arm
/// that masks, so a uniform-SMT machine that happens to have a core offline gets
/// its core back and an error, not every core but cpu0 offlined.
fn ensure_manageable(root: &Path) -> Result<()> {
    if is_hybrid(root)? || is_efficiency_mode(root)? {
        return Ok(());
    }

    Err(not_hybrid())
}

fn not_hybrid() -> Box<dyn std::error::Error + Send + Sync> {
    io::Error::other("no hybrid P-core/E-core topology here; use powerprofilesctl directly").into()
}

fn cpu_path(root: &Path, cpu: u32, rest: &str) -> PathBuf {
    root.join(format!("cpu{cpu}")).join(rest)
}

fn is_online(root: &Path, cpu: u32) -> Result<bool> {
    let value = fs::read_to_string(cpu_path(root, cpu, "online"))?;

    Ok(value.trim() != "0")
}

fn set_cpu_online(root: &Path, cpu: u32, online: bool) -> Result<()> {
    let path = cpu_path(root, cpu, "online");
    if !path.is_file() {
        return Ok(());
    }

    fs::write(path, if online { "1" } else { "0" })?;
    Ok(())
}

fn powerprofilesctl(args: &[&str]) -> Result<Output> {
    let output = Command::new("powerprofilesctl").args(args).output()?;
    if output.status.success() {
        return Ok(output);
    }

    let stderr = String::from_utf8_lossy(&output.stderr);
    let detail = if stderr.trim().is_empty() {
        "(no stderr)".to_owned()
    } else {
        stderr.trim().to_owned()
    };

    Err(io::Error::other(format!(
        "powerprofilesctl {} failed: {detail}",
        args.join(" ")
    ))
    .into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        env, process,
        sync::atomic::{AtomicU32, Ordering},
        time::{SystemTime, UNIX_EPOCH},
    };

    /// Tests run in parallel in one process, so the timestamp alone is not
    /// enough to keep two trees apart.
    static TREE_COUNTER: AtomicU32 = AtomicU32::new(0);

    struct TempTree {
        path: PathBuf,
    }

    impl TempTree {
        fn new() -> Self {
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            let serial = TREE_COUNTER.fetch_add(1, Ordering::Relaxed);
            let path = env::temp_dir().join(format!(
                "laptop-power-profile-{}-{timestamp}-{serial}",
                process::id()
            ));
            fs::create_dir_all(&path).expect("temp tree is creatable");
            Self { path }
        }

        fn path(&self) -> &Path {
            &self.path
        }

        fn write(&self, relative: &str, contents: &str) {
            let path = self.path.join(relative);
            fs::create_dir_all(path.parent().expect("relative path has a parent"))
                .expect("parent is creatable");
            fs::write(path, contents).expect("file is writable");
        }
    }

    impl Drop for TempTree {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    /// The laptop's i7-12700H: 6 P-cores as 12 SMT threads (cpu0..cpu11) plus 8
    /// single-threaded E-cores (cpu12..cpu19). cpu0 is the boot CPU and has no
    /// `online` file, matching the real machine.
    fn hybrid_tree() -> TempTree {
        let tree = TempTree::new();

        for cpu in 0..12u32 {
            let pair_start = cpu - (cpu % 2);
            tree.write(
                &format!("cpu{cpu}/topology/thread_siblings_list"),
                &format!("{pair_start}-{}\n", pair_start + 1),
            );
        }
        for cpu in 12..20u32 {
            tree.write(
                &format!("cpu{cpu}/topology/thread_siblings_list"),
                &format!("{cpu}\n"),
            );
        }
        for cpu in 1..20u32 {
            tree.write(&format!("cpu{cpu}/online"), "1\n");
        }

        // Non-CPU entries the real sysfs root carries alongside the cpuN dirs.
        tree.write("cpufreq/policy0/scaling_governor", "powersave\n");
        tree.write("cpuidle/current_driver", "intel_idle\n");

        tree
    }

    #[test]
    fn parse_cpulist_reads_singles_ranges_and_mixtures() {
        assert_eq!(parse_cpulist("3"), Some(vec![3]));
        assert_eq!(parse_cpulist("0-1\n"), Some(vec![0, 1]));
        assert_eq!(parse_cpulist("0,4"), Some(vec![0, 4]));
        assert_eq!(
            parse_cpulist("0-3,8-11"),
            Some(vec![0, 1, 2, 3, 8, 9, 10, 11])
        );
        assert_eq!(parse_cpulist(""), Some(Vec::new()));
    }

    #[test]
    fn parse_cpulist_rejects_non_cpulist_input() {
        assert_eq!(parse_cpulist("not-a-list"), None);
        assert_eq!(parse_cpulist("5-2"), None);
        assert_eq!(parse_cpulist("0-"), None);
    }

    /// The bug the parse guards against: token-counting on ',' sees one token in
    /// "0-1" and would call an SMT pair a single-threaded E-core.
    #[test]
    fn is_p_core_treats_a_sibling_range_as_smt() {
        assert!(is_p_core("0-1"));
        assert!(is_p_core("0,4"));
        assert!(!is_p_core("12"));
        assert!(!is_p_core("12\n"));
        assert!(!is_p_core("garbage"));
    }

    #[test]
    fn cpu_numbers_sorts_numerically_and_skips_non_cpu_entries() {
        let tree = hybrid_tree();

        assert_eq!(
            cpu_numbers(tree.path()).unwrap(),
            (0..20).collect::<Vec<_>>()
        );
    }

    #[test]
    fn p_core_cpus_finds_the_smt_threads_only() {
        let tree = hybrid_tree();

        assert_eq!(
            p_core_cpus(tree.path()).unwrap(),
            (0..12).collect::<Vec<_>>()
        );
    }

    #[test]
    fn hotpluggable_cpus_excludes_the_boot_cpu() {
        let tree = hybrid_tree();

        assert_eq!(
            hotpluggable_cpus(tree.path()).unwrap(),
            (1..20).collect::<Vec<_>>()
        );
    }

    #[test]
    fn efficiency_mode_is_off_when_every_hotpluggable_cpu_is_online() {
        let tree = hybrid_tree();

        assert!(!is_efficiency_mode(tree.path()).unwrap());
    }

    #[test]
    fn efficiency_mode_is_on_when_any_cpu_is_offline() {
        let tree = hybrid_tree();
        tree.write("cpu5/online", "0\n");

        assert!(is_efficiency_mode(tree.path()).unwrap());
    }

    /// Offlining strips `topology/`, so detection has to survive the P-cores it
    /// is meant to detect having lost their sibling lists.
    #[test]
    fn efficiency_mode_survives_offlined_cpus_losing_their_topology() {
        let tree = hybrid_tree();
        for cpu in 1..12u32 {
            fs::remove_dir_all(tree.path().join(format!("cpu{cpu}/topology")))
                .expect("topology is removable");
            tree.write(&format!("cpu{cpu}/online"), "0\n");
        }

        assert!(is_efficiency_mode(tree.path()).unwrap());
    }

    #[test]
    fn hybrid_topology_is_detected() {
        let tree = hybrid_tree();

        assert!(is_hybrid(tree.path()).unwrap());
    }

    #[test]
    fn uniform_smt_desktop_is_not_hybrid() {
        let tree = TempTree::new();
        for cpu in 0..16u32 {
            let pair_start = cpu - (cpu % 2);
            tree.write(
                &format!("cpu{cpu}/topology/thread_siblings_list"),
                &format!("{pair_start}-{}\n", pair_start + 1),
            );
        }

        assert!(!is_hybrid(tree.path()).unwrap());
    }

    #[test]
    fn machine_without_smt_is_not_hybrid() {
        let tree = TempTree::new();
        for cpu in 0..8u32 {
            tree.write(
                &format!("cpu{cpu}/topology/thread_siblings_list"),
                &format!("{cpu}\n"),
            );
        }

        assert!(!is_hybrid(tree.path()).unwrap());
    }

    /// A tree in the state e-core-only actually leaves behind: P-cores offline,
    /// their `topology/` gone with them, cpu0 now claiming no SMT sibling.
    fn masked_tree() -> TempTree {
        let tree = hybrid_tree();

        tree.write("cpu0/topology/thread_siblings_list", "0\n");
        for cpu in 1..12u32 {
            fs::remove_dir_all(tree.path().join(format!("cpu{cpu}/topology")))
                .expect("topology is removable");
            tree.write(&format!("cpu{cpu}/online"), "0\n");
        }

        tree
    }

    /// The regression: `current` used to run the topology check first, so the
    /// mask hid the very profile that laid it down. The popup read that failure
    /// as "no laptop-helper backend", fell back to powerprofilesctl, and dropped
    /// the e-core-only entry off the list while the P-cores stayed offline.
    #[test]
    fn current_reports_e_core_only_through_the_mask_it_left() {
        let tree = masked_tree();

        assert!(!is_hybrid(tree.path()).unwrap());
        assert_eq!(current(tree.path()).unwrap(), "e-core-only");
    }

    /// The other half of the same regression: with the mask on, `apply` refused
    /// too, so the profile could not be left by the control that entered it.
    /// The tree stays stripped of `topology/` after the re-onlining, which real
    /// sysfs would restore — leaving e-core-only must not lean on that.
    #[test]
    fn apply_re_onlines_through_the_mask_it_left() {
        let tree = masked_tree();

        unmask(tree.path()).expect("the mask comes off without a topology to read");

        for cpu in 1..20u32 {
            assert_eq!(
                fs::read_to_string(tree.path().join(format!("cpu{cpu}/online"))).unwrap(),
                "1",
                "cpu{cpu} should be back online"
            );
        }
    }

    /// An offline CPU alone must not be taken as licence to offline the rest:
    /// on uniform SMT every core reads as a P-core, so a mask laid on the
    /// strength of `ensure_manageable` would leave the machine on cpu0 alone.
    #[test]
    fn uniform_smt_with_an_offline_cpu_is_still_refused() {
        let tree = TempTree::new();
        for cpu in 0..16u32 {
            let pair_start = cpu - (cpu % 2);
            tree.write(
                &format!("cpu{cpu}/topology/thread_siblings_list"),
                &format!("{pair_start}-{}\n", pair_start + 1),
            );
        }
        for cpu in 1..16u32 {
            tree.write(&format!("cpu{cpu}/online"), "1\n");
        }
        tree.write("cpu7/online", "0\n");

        assert!(apply(tree.path(), Profile::ECoreOnly).is_err());

        for cpu in 1..16u32 {
            assert_eq!(
                fs::read_to_string(tree.path().join(format!("cpu{cpu}/online"))).unwrap(),
                "1",
                "cpu{cpu} should be online, not masked"
            );
        }
    }

    /// `current` and `apply` must refuse before shelling out to
    /// powerprofilesctl, so a non-hybrid host falls back cleanly.
    #[test]
    fn non_hybrid_topology_is_refused() {
        let tree = TempTree::new();
        for cpu in 0..4u32 {
            tree.write(
                &format!("cpu{cpu}/topology/thread_siblings_list"),
                &format!("{cpu}\n"),
            );
        }

        assert!(current(tree.path()).is_err());
        assert!(apply(tree.path(), Profile::ECoreOnly).is_err());
    }

    #[test]
    fn set_cpu_online_ignores_cpus_without_an_online_file() {
        let tree = hybrid_tree();

        set_cpu_online(tree.path(), 0, false).expect("boot cpu is skipped, not an error");

        assert!(!tree.path().join("cpu0/online").exists());
    }

    #[test]
    fn set_cpu_online_writes_the_bare_sysfs_value() {
        let tree = hybrid_tree();

        set_cpu_online(tree.path(), 5, false).unwrap();
        assert_eq!(
            fs::read_to_string(tree.path().join("cpu5/online")).unwrap(),
            "0"
        );

        set_cpu_online(tree.path(), 5, true).unwrap();
        assert_eq!(
            fs::read_to_string(tree.path().join("cpu5/online")).unwrap(),
            "1"
        );
    }

    /// These strings are a wire contract with the polkit rule, the Quickshell
    /// power popup, and powerprofilesctl itself.
    #[test]
    fn profile_names_match_value_enum() {
        for profile in [
            Profile::Performance,
            Profile::Balanced,
            Profile::PowerSaver,
            Profile::ECoreOnly,
        ] {
            let value = profile.to_possible_value().expect("profile is selectable");
            assert_eq!(value.get_name(), profile.as_str());
        }

        assert_eq!(Profile::PowerSaver.as_str(), "power-saver");
        assert_eq!(Profile::ECoreOnly.as_str(), "e-core-only");
    }
}
