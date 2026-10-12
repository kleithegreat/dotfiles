//! Window session restore: which windows of a few known apps were open on
//! which workspace, recorded while the session runs and replayed into the
//! next one. See `docs/session-restore.md`.

use crate::{hypr, ipc, paths, theme};
use serde::{Deserialize, Serialize};
use std::{
    fs, io,
    path::{Path, PathBuf},
    thread,
    time::{Duration, Instant},
};

use crate::Result;

/// How an app's windows come back.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Relaunch {
    /// One process per window, each started on its workspace in its directory.
    PerWindow,
    /// The app reopens its own windows; they are sorted onto workspaces after.
    Whole,
}

struct App {
    class: &'static str,
    command: &'static str,
    relaunch: Relaunch,
    /// Run before a `Whole` app is launched, for whatever makes it reopen
    /// its own windows.
    prepare: Option<fn() -> Result<()>>,
}

const APPS: &[App] = &[
    App {
        class: "Alacritty",
        command: "alacritty",
        relaunch: Relaunch::PerWindow,
        prepare: None,
    },
    App {
        class: "helium",
        command: "helium",
        relaunch: Relaunch::Whole,
        prepare: Some(theme::targets::helium::mark_clean_exit),
    },
    App {
        class: "code",
        command: "code",
        relaunch: Relaunch::Whole,
        prepare: None,
    },
];

/// How long a relaunched app's window count must hold still before its
/// windows are sorted, and how long to wait for that at all.
const SETTLE: Duration = Duration::from_secs(2);
const SETTLE_DEADLINE: Duration = Duration::from_secs(30);
const SETTLE_POLL: Duration = Duration::from_millis(500);

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub(crate) struct Window {
    workspace: String,
    class: String,
    /// Tells a `Whole` app's windows apart; absent for `PerWindow` apps, whose
    /// titles churn without the window changing.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    cwd: Option<PathBuf>,
}

/// The windows of the running session, tagged with the Hyprland instance they
/// belong to so the next session can tell them from its own.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub(crate) struct Recording {
    instance: String,
    windows: Vec<Window>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub(crate) struct State {
    pub(crate) automatic: bool,
    /// The previous session's windows, until they are restored.
    pub(crate) last: Vec<Window>,
}

impl Default for State {
    fn default() -> Self {
        Self {
            automatic: true,
            last: Vec::new(),
        }
    }
}

impl State {
    pub(crate) fn status(&self) -> serde_json::Value {
        serde_json::json!({ "automatic": self.automatic, "restorable": self.last.len() })
    }

    pub(crate) fn persist(&self) -> Result<()> {
        theme::atomic_write(&path("state.json")?, &serde_json::to_vec_pretty(self)?)
    }
}

fn path(name: &str) -> io::Result<PathBuf> {
    Ok(paths::xdg_data_home()?
        .join("desktopctl/session")
        .join(name))
}

fn load<T: Default + for<'de> Deserialize<'de>>(name: &str) -> Result<T> {
    match fs::read(path(name)?) {
        Ok(contents) => Ok(serde_json::from_slice(&contents)?),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(T::default()),
        Err(error) => Err(error.into()),
    }
}

/// Load the state, first promoting a recording left by an earlier Hyprland
/// instance to "the last session". A daemon restart inside one session finds
/// its own instance on the recording and leaves it alone.
pub(crate) fn load_state() -> Result<State> {
    let mut state: State = load("state.json")?;
    let recording: Recording = load("recording.json")?;
    if !recording.instance.is_empty()
        && recording.instance != hypr::hyprland_signature().unwrap_or_default()
    {
        state.last = recording.windows;
        state.persist()?;
        fs::remove_file(path("recording.json")?)?;
    }
    Ok(state)
}

pub(crate) fn record() -> Result<Recording> {
    let mut windows: Vec<Window> = hypr::query_windows()?
        .into_iter()
        .filter_map(|window| {
            let app = APPS.iter().find(|app| app.class == window.class)?;
            Some(match app.relaunch {
                Relaunch::PerWindow => Window {
                    workspace: window.workspace.name,
                    class: window.class,
                    title: None,
                    cwd: child_cwd(window.pid),
                },
                Relaunch::Whole => Window {
                    workspace: window.workspace.name,
                    class: window.class,
                    title: Some(window.title),
                    cwd: None,
                },
            })
        })
        .collect();
    windows.sort();
    Ok(Recording {
        instance: hypr::hyprland_signature().unwrap_or_default(),
        windows,
    })
}

pub(crate) fn persist_recording(recording: &Recording) -> Result<()> {
    theme::atomic_write(
        &path("recording.json")?,
        &serde_json::to_vec_pretty(recording)?,
    )
}

/// The working directory of a terminal's shell: its first child process.
fn child_cwd(pid: i64) -> Option<PathBuf> {
    fs::read_dir(format!("/proc/{pid}/task"))
        .ok()?
        .filter_map(|task| fs::read_to_string(task.ok()?.path().join("children")).ok())
        .find_map(|children| {
            let child = children.split_whitespace().next()?;
            fs::read_link(format!("/proc/{child}/cwd")).ok()
        })
}

pub(crate) fn restore(windows: &[Window]) -> Result<()> {
    let open = hypr::query_windows()?;
    let mut sorting = Vec::new();

    for app in APPS {
        let saved: Vec<&Window> = windows
            .iter()
            .filter(|window| window.class == app.class)
            .collect();
        if saved.is_empty() {
            continue;
        }
        match app.relaunch {
            Relaunch::PerWindow => {
                for window in saved {
                    hypr::eval(&exec_on_workspace(app, window))?;
                }
            }
            // A running app keeps its windows; relaunching would only add one.
            Relaunch::Whole if open.iter().any(|window| window.class == app.class) => {}
            Relaunch::Whole => {
                if let Some(prepare) = app.prepare
                    && let Err(error) = prepare()
                {
                    eprintln!("desktopctl: preparing {} failed: {error}", app.class);
                }
                hypr::dispatch(&hypr::exec_dispatcher(app.command))?;
                sorting.push((app.class, saved));
            }
        }
    }

    if sorting.is_empty() {
        return Ok(());
    }
    let classes: Vec<&str> = sorting.iter().map(|(class, _)| *class).collect();
    let opened = settled_windows(&classes)?;
    for (class, saved) in sorting {
        let opened: Vec<&hypr::WindowInfo> = opened
            .iter()
            .filter(|window| window.class == class)
            .collect();
        for (address, workspace) in assign(&saved, &opened) {
            hypr::dispatch(&format!(
                "hl.dsp.window.move({{ workspace = {}, silent = true, window = {} }})",
                workspace_selector(workspace),
                hypr::lua_str(&format!("address:{address}")),
            ))?;
        }
    }
    Ok(())
}

fn exec_on_workspace(app: &App, window: &Window) -> String {
    let mut command = app.command.to_owned();
    if let Some(cwd) = window.cwd.as_deref().filter(|cwd| cwd.is_dir()) {
        command.push_str(&format!(" --working-directory {}", sh_quote(cwd)));
    }
    format!(
        "hl.exec_cmd({}, {{ workspace = {} }})",
        hypr::lua_str(&command),
        hypr::lua_str(&format!("{} silent", window.workspace)),
    )
}

fn sh_quote(path: &Path) -> String {
    format!("'{}'", path.to_string_lossy().replace('\'', r"'\''"))
}

fn workspace_selector(name: &str) -> String {
    match name.parse::<i64>() {
        Ok(id) => id.to_string(),
        Err(_) => hypr::lua_str(name),
    }
}

/// Wait for the relaunched apps to finish reopening their windows: every class
/// has at least one and the total has stopped changing. Past the deadline,
/// whatever is open is sorted.
fn settled_windows(classes: &[&str]) -> Result<Vec<hypr::WindowInfo>> {
    let deadline = Instant::now() + SETTLE_DEADLINE;
    let mut stable_since = Instant::now();
    let mut count = 0;

    loop {
        let windows: Vec<hypr::WindowInfo> = hypr::query_windows()?
            .into_iter()
            .filter(|window| classes.contains(&window.class.as_str()))
            .collect();
        if windows.len() != count {
            count = windows.len();
            stable_since = Instant::now();
        }
        let all_present = classes
            .iter()
            .all(|class| windows.iter().any(|window| window.class == *class));
        if (all_present && stable_since.elapsed() >= SETTLE) || Instant::now() >= deadline {
            return Ok(windows);
        }
        thread::sleep(SETTLE_POLL);
    }
}

/// Pair reopened windows with saved ones: by title where a title survived the
/// restart, in order for the rest. Returns the moves that are still needed.
fn assign<'a>(saved: &[&'a Window], opened: &[&hypr::WindowInfo]) -> Vec<(String, &'a str)> {
    let mut saved: Vec<&Window> = saved.to_vec();
    let mut unmatched = Vec::new();
    let mut pairs = Vec::new();

    for window in opened {
        match saved
            .iter()
            .position(|candidate| candidate.title.as_deref() == Some(window.title.as_str()))
        {
            Some(index) => pairs.push((*window, saved.remove(index))),
            None => unmatched.push(*window),
        }
    }
    pairs.extend(unmatched.into_iter().zip(saved));

    pairs
        .into_iter()
        .filter(|(window, target)| window.workspace.name != target.workspace)
        .map(|(window, target)| (window.address.clone(), target.workspace.as_str()))
        .collect()
}

pub fn run(args: crate::SessionArgs) -> Result<()> {
    match args.command {
        crate::SessionCommand::Status(args) => {
            let status = match ipc::send_request::<(), serde_json::Value>(
                ipc::methods::SESSION_STATUS,
                None,
                ipc::DEFAULT_TIMEOUT,
            ) {
                Err(error) if ipc::socket_unavailable(error.as_ref()) => {
                    load::<State>("state.json")?.status()
                }
                status => status?,
            };
            if args.json {
                println!("{status}");
            } else {
                println!(
                    "automatic = {}\nrestorable = {}",
                    status["automatic"], status["restorable"]
                );
            }
            Ok(())
        }
        crate::SessionCommand::Automatic(args) => request(
            ipc::methods::SESSION_AUTOMATIC,
            serde_json::json!({ "automatic": args.enabled }),
            0,
        )
        .map(drop),
        crate::SessionCommand::Restore(args) => request(
            ipc::methods::SESSION_RESTORE,
            serde_json::json!({ "if_automatic": args.if_automatic }),
            args.wait.wait_daemon,
        )
        .map(drop),
    }
}

fn request(method: &str, params: serde_json::Value, wait_daemon: u64) -> Result<serde_json::Value> {
    ipc::mutate(
        method,
        params,
        SETTLE_DEADLINE + ipc::DEFAULT_TIMEOUT,
        Duration::from_secs(wait_daemon),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn saved(workspace: &str, title: &str) -> Window {
        Window {
            workspace: workspace.to_owned(),
            class: "helium".to_owned(),
            title: Some(title.to_owned()),
            cwd: None,
        }
    }

    fn opened(address: &str, workspace: &str, title: &str) -> hypr::WindowInfo {
        serde_json::from_value(serde_json::json!({
            "address": address,
            "class": "helium",
            "title": title,
            "workspace": { "name": workspace },
        }))
        .expect("window should deserialize")
    }

    #[test]
    fn assign_matches_titles_before_falling_back_to_order() {
        let saved = [saved("1", "Mail"), saved("4", "Docs"), saved("5", "News")];
        let saved: Vec<&Window> = saved.iter().collect();
        let opened = [
            opened("0xa", "1", "New Tab"),
            opened("0xb", "1", "Docs"),
            opened("0xc", "1", "Mail"),
        ];
        let opened: Vec<&hypr::WindowInfo> = opened.iter().collect();

        // "Mail" is already on 1, so only the other two move.
        assert_eq!(
            assign(&saved, &opened),
            vec![("0xb".to_owned(), "4"), ("0xa".to_owned(), "5")]
        );
    }

    #[test]
    fn assign_leaves_surplus_windows_alone() {
        let saved = [saved("3", "Docs")];
        let saved: Vec<&Window> = saved.iter().collect();
        let opened = [opened("0xa", "1", "Other"), opened("0xb", "1", "Extra")];
        let opened: Vec<&hypr::WindowInfo> = opened.iter().collect();

        assert_eq!(assign(&saved, &opened), vec![("0xa".to_owned(), "3")]);
    }

    #[test]
    fn exec_quotes_the_directory_for_both_the_shell_and_lua() {
        let window = Window {
            workspace: "special:scratch".to_owned(),
            class: "Alacritty".to_owned(),
            title: None,
            cwd: Some(PathBuf::from("/")),
        };
        assert_eq!(
            exec_on_workspace(&APPS[0], &window),
            r#"hl.exec_cmd("alacritty --working-directory '/'", { workspace = "special:scratch silent" })"#
        );
        assert_eq!(sh_quote(Path::new("/a b/it's")), r"'/a b/it'\''s'");
    }

    #[test]
    fn workspace_selector_is_a_number_or_a_quoted_name() {
        assert_eq!(workspace_selector("3"), "3");
        assert_eq!(
            workspace_selector("special:scratch"),
            r#""special:scratch""#
        );
    }

    #[test]
    fn restore_is_automatic_until_the_state_says_otherwise() {
        assert!(State::default().automatic);
        let state: State = serde_json::from_str(r#"{"automatic":false}"#).expect("state");
        assert!(!state.automatic && state.last.is_empty());
    }
}
