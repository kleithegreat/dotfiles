//! Estimated, not measured: RAPL meters the cores and the iGPU only as wholes,
//! so each sample's core watts are split by CPU time and its iGPU watts by
//! engine time.

use super::Sample;
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::Path,
};

const KEPT: usize = 12;

#[derive(Default)]
pub(super) struct Snapshot(HashMap<Key, Usage>);

/// A pid alone can be reused within an interval.
#[derive(PartialEq, Eq, Hash)]
struct Key {
    pid: u32,
    start: u64,
}

struct Usage {
    name: String,
    cpu_ticks: u64,
    runs: u64,
    gpu_ns: u64,
}

pub(super) struct Share {
    pub(super) name: String,
    pub(super) cpu_w: Option<f64>,
    pub(super) gpu_w: Option<f64>,
    pub(super) runs_per_s: f64,
}

pub(super) fn snapshot() -> Snapshot {
    let mut gpu_clients = HashSet::new();
    Snapshot(
        fs::read_dir("/proc")
            .into_iter()
            .flatten()
            .flatten()
            .filter_map(|entry| {
                let pid = entry.file_name().to_str()?.parse().ok()?;
                read_process(pid, &entry.path(), &mut gpu_clients)
            })
            .collect(),
    )
}

/// The heaviest groups of one sample. A process absent from `previous` started
/// after it was taken, so its whole lifetime belongs to this interval.
pub(super) fn attribute(previous: &Snapshot, current: &Snapshot, sample: &Sample) -> Vec<Share> {
    let mut groups: HashMap<&str, [u64; 3]> = HashMap::new();
    for (key, now) in &current.0 {
        let before = previous.0.get(key);
        let delta = |field: fn(&Usage) -> u64| field(now).saturating_sub(before.map_or(0, field));
        let group = groups.entry(&now.name).or_default();
        group[0] += delta(|usage| usage.cpu_ticks);
        group[1] += delta(|usage| usage.runs);
        group[2] += delta(|usage| usage.gpu_ns);
    }

    let [_, _, core_w, uncore_w] = sample.watts;
    let gpu_ns: u64 = groups.values().map(|group| group[2]).sum();
    let mut shares: Vec<Share> = groups
        .into_iter()
        .filter(|(_, group)| group.iter().any(|value| *value > 0))
        .map(|(name, [cpu_ticks, runs, group_gpu_ns])| Share {
            name: name.to_owned(),
            cpu_w: core_w
                .zip(sample.busy_ticks)
                .map(|(watts, busy)| watts * fraction(cpu_ticks, busy)),
            gpu_w: uncore_w.map(|watts| watts * fraction(group_gpu_ns, gpu_ns)),
            runs_per_s: runs as f64 / sample.seconds,
        })
        .collect();
    shares.sort_by(|a, b| {
        watts(b)
            .total_cmp(&watts(a))
            .then(b.runs_per_s.total_cmp(&a.runs_per_s))
    });
    shares.truncate(KEPT);
    shares
}

fn watts(share: &Share) -> f64 {
    share.cpu_w.unwrap_or(0.0) + share.gpu_w.unwrap_or(0.0)
}

fn fraction(part: u64, whole: u64) -> f64 {
    if whole == 0 {
        0.0
    } else {
        (part as f64 / whole as f64).min(1.0)
    }
}

fn read_process(pid: u32, dir: &Path, gpu_clients: &mut HashSet<String>) -> Option<(Key, Usage)> {
    let (comm, cpu_ticks, start) = parse_stat(&fs::read_to_string(dir.join("stat")).ok()?)?;
    let cmdline = fs::read(dir.join("cmdline")).unwrap_or_default();
    Some((
        Key { pid, start },
        Usage {
            name: group_name(&comm, &cmdline),
            cpu_ticks,
            runs: task_runs(dir),
            gpu_ns: gpu_ns(dir, gpu_clients),
        },
    ))
}

/// `(comm, utime + stime, starttime)`; comm may itself hold spaces and parentheses.
fn parse_stat(stat: &str) -> Option<(String, u64, u64)> {
    let comm = &stat[stat.find('(')? + 1..stat.rfind(')')?];
    let fields: Vec<&str> = stat[stat.rfind(')')? + 1..].split_whitespace().collect();
    let field = |number: usize| fields.get(number - 3)?.parse::<u64>().ok();
    Some((comm.to_owned(), field(14)? + field(15)?, field(22)?))
}

/// Groups a program's processes under one name: argv[0]'s basename, the Nix
/// wrapper's `.name-wrapped` undone, or the comm prefix for kernel threads
/// (`kworker/3:1` → `kworker`) and processes that retitle themselves.
fn group_name(comm: &str, cmdline: &[u8]) -> String {
    let argv0 =
        String::from_utf8_lossy(cmdline.split(|byte| *byte == 0).next().unwrap_or_default());
    if argv0.is_empty() {
        return comm.split('/').next().unwrap_or(comm).to_owned();
    }
    if argv0.contains(' ') {
        return comm.to_owned();
    }
    let base = argv0.rsplit('/').next().unwrap_or(&argv0);
    base.strip_prefix('.')
        .and_then(|base| base.strip_suffix("-wrapped"))
        .unwrap_or(base)
        .to_owned()
}

/// Times the process's threads were put on a CPU; for a mostly idle process,
/// its wakeups.
fn task_runs(dir: &Path) -> u64 {
    fs::read_dir(dir.join("task"))
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|task| {
            fs::read_to_string(task.path().join("schedstat"))
                .ok()?
                .split_whitespace()
                .nth(2)?
                .parse::<u64>()
                .ok()
        })
        .sum()
}

/// Only the process's own user may read its fds; others count as no GPU time.
fn gpu_ns(dir: &Path, gpu_clients: &mut HashSet<String>) -> u64 {
    let Ok(fds) = fs::read_dir(dir.join("fd")) else {
        return 0;
    };
    fds.flatten()
        .filter(|fd| fs::read_link(fd.path()).is_ok_and(|target| target.starts_with("/dev/dri/")))
        .filter_map(|fd| {
            parse_fdinfo(&fs::read_to_string(dir.join("fdinfo").join(fd.file_name())).ok()?)
        })
        .filter(|(client, _)| gpu_clients.insert(client.clone()))
        .map(|(_, ns)| ns)
        .sum()
}

/// A DRM client's identity and its engine time summed over engines. Dup'd fds
/// share one client, so callers count each client once.
fn parse_fdinfo(fdinfo: &str) -> Option<(String, u64)> {
    let mut pdev = None;
    let mut client = None;
    let mut ns = 0;
    for line in fdinfo.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let value = value.trim();
        match key {
            "drm-pdev" => pdev = Some(value),
            "drm-client-id" => client = Some(value),
            _ if key.starts_with("drm-engine-") && !key.starts_with("drm-engine-capacity-") => {
                ns += value
                    .strip_suffix(" ns")
                    .and_then(|ns| ns.parse::<u64>().ok())
                    .unwrap_or(0);
            }
            _ => {}
        }
    }
    Some((format!("{}/{}", pdev?, client?), ns))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn usage(name: &str, cpu_ticks: u64, runs: u64, gpu_ns: u64) -> Usage {
        Usage {
            name: name.to_owned(),
            cpu_ticks,
            runs,
            gpu_ns,
        }
    }

    fn sample() -> Sample {
        Sample {
            seconds: 5.0,
            battery_w: 20.0,
            charge_uah: 1,
            watts: [Some(18.0), Some(8.0), Some(4.0), Some(1.0)],
            busy_ticks: Some(100),
            cpu_busy: Some(0.1),
        }
    }

    #[test]
    fn watts_split_by_cpu_and_engine_time_across_a_programs_processes() {
        let previous = Snapshot(HashMap::from([
            (Key { pid: 1, start: 10 }, usage("helium", 100, 10, 0)),
            (Key { pid: 2, start: 10 }, usage("helium", 50, 10, 1_000)),
            (Key { pid: 3, start: 10 }, usage("kitty", 0, 0, 0)),
        ]));
        let current = Snapshot(HashMap::from([
            (Key { pid: 1, start: 10 }, usage("helium", 120, 20, 0)),
            (Key { pid: 2, start: 10 }, usage("helium", 70, 20, 4_000)),
            (Key { pid: 3, start: 10 }, usage("kitty", 10, 5, 1_000)),
        ]));
        let shares = attribute(&previous, &current, &sample());
        let names: Vec<&str> = shares.iter().map(|share| share.name.as_str()).collect();
        assert_eq!(names, ["helium", "kitty"]);
        assert_eq!(shares[0].cpu_w, Some(1.6));
        assert_eq!(shares[0].gpu_w, Some(0.75));
        assert_eq!(shares[0].runs_per_s, 4.0);
        assert_eq!(shares[1].cpu_w, Some(0.4));
    }

    #[test]
    fn a_reused_pid_counts_from_zero_and_idle_programs_are_dropped() {
        let previous = Snapshot(HashMap::from([
            (Key { pid: 1, start: 10 }, usage("old", 500, 0, 0)),
            (Key { pid: 2, start: 10 }, usage("idle", 7, 7, 0)),
        ]));
        let current = Snapshot(HashMap::from([
            (Key { pid: 1, start: 99 }, usage("new", 5, 0, 0)),
            (Key { pid: 2, start: 10 }, usage("idle", 7, 7, 0)),
        ]));
        let shares = attribute(&previous, &current, &sample());
        assert_eq!(shares.len(), 1);
        assert_eq!(shares[0].name, "new");
        assert_eq!(shares[0].cpu_w, Some(0.2));
    }

    #[test]
    fn stat_parsing_survives_parentheses_in_comm() {
        let stat = "42 (a (b) c) S 1 42 42 0 -1 4194560 0 0 0 0 7 3 0 0 20 0 1 0 12345 0 0";
        assert_eq!(parse_stat(stat), Some(("a (b) c".to_owned(), 10, 12345)));
    }

    #[test]
    fn group_names_follow_argv0() {
        assert_eq!(
            group_name(
                "helium",
                b"/nix/store/x-helium/bin/helium\0--type=renderer\0"
            ),
            "helium"
        );
        assert_eq!(
            group_name(
                ".desktopctl-wra",
                b"/nix/store/x/bin/.desktopctl-wrapped\0daemon\0"
            ),
            "desktopctl"
        );
        assert_eq!(group_name("kworker/u40:3-e", b""), "kworker");
        assert_eq!(group_name("sshd", b"sshd: kevin@pts/0\0"), "sshd");
    }

    #[test]
    fn fdinfo_sums_engines_but_not_capacities() {
        let fdinfo = "drm-driver:\ti915\ndrm-client-id:\t45\ndrm-pdev:\t0000:00:02.0\n\
                      drm-engine-render:\t300 ns\ndrm-engine-video:\t20 ns\ndrm-engine-capacity-video:\t2\n";
        assert_eq!(
            parse_fdinfo(fdinfo),
            Some(("0000:00:02.0/45".to_owned(), 320))
        );
    }
}
