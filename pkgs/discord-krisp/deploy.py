#!@pythonInterpreter@
"""Deploy the pre-patched Krisp module into Discord's writable module dir."""

import hashlib
import json
import os
import shutil
import sys
from pathlib import Path
from threading import Event, Lock

from watchdog.events import (
    DirCreatedEvent,
    DirDeletedEvent,
    DirModifiedEvent,
    DirMovedEvent,
    EVENT_TYPE_CLOSED_NO_WRITE,
    EVENT_TYPE_OPENED,
    FileClosedEvent,
    FileCreatedEvent,
    FileDeletedEvent,
    FileModifiedEvent,
    FileMovedEvent,
    FileSystemEventHandler,
)
from watchdog.observers import Observer


KRISP_STORE = Path("@krispPath@")
VERSION = "@discordVersion@"
CONFIG_DIR = "@configDirName@"
MARKER = ".nix-krisp-hash"
PARENT_CHECK_INTERVAL = 1
HASH_CHUNK_SIZE = 1024 * 1024
WATCHED_EVENTS = [
    DirCreatedEvent,
    DirDeletedEvent,
    DirModifiedEvent,
    DirMovedEvent,
    FileClosedEvent,
    FileCreatedEvent,
    FileDeletedEvent,
    FileModifiedEvent,
    FileMovedEvent,
]


def modules_dir() -> Path:
    home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    return home / CONFIG_DIR / VERSION / "modules"


def file_hash(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(HASH_CHUNK_SIZE), b""):
            h.update(chunk)
    return h.hexdigest()


KRISP_HASH = hashlib.sha256(
    (file_hash(KRISP_STORE / "discord_krisp.node") + file_hash(KRISP_STORE / "index.js")).encode()
).hexdigest()


def needs_deploy(dest: Path) -> bool:
    node = dest / "discord_krisp.node"
    index = dest / "index.js"
    marker = dest / MARKER
    if not node.exists() or not index.exists() or not marker.exists():
        return True
    try:
        stored_hash = marker.read_text(encoding="utf-8").strip()
    except OSError:
        return True
    if stored_hash != KRISP_HASH:
        return True
    return hashlib.sha256((file_hash(node) + file_hash(index)).encode()).hexdigest() != KRISP_HASH


def deploy(dest: Path, quiet: bool = False) -> None:
    if not needs_deploy(dest):
        if not quiet:
            print("[Nix] Krisp already deployed")
        return
    if not quiet:
        print("[Nix] Deploying pre-patched Krisp module")
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink():
        dest.unlink()
    elif dest.exists():
        for p in dest.rglob("*"):
            if p.is_symlink():
                p.unlink()
                continue
            p.chmod(0o755 if p.is_dir() else 0o644)
        dest.chmod(0o755)
        shutil.rmtree(dest)
    shutil.copytree(KRISP_STORE, dest)
    dest.chmod(0o755)
    for p in dest.rglob("*"):
        p.chmod(0o755 if p.is_dir() or p.suffix == ".node" else 0o644)
    (dest / MARKER).write_text(KRISP_HASH + "\n", encoding="utf-8")


def register(manifest: Path, create: bool) -> None:
    if not manifest.exists() and not create:
        return
    try:
        data = json.loads(manifest.read_text(encoding="utf-8")) if manifest.exists() else {}
    except (json.JSONDecodeError, OSError):
        data = {}
    if data.get("discord_krisp", {}).get("installedVersion") != 1:
        data["discord_krisp"] = {"installedVersion": 1}
        tmp = manifest.with_name(f"{manifest.name}.tmp")
        tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        os.replace(tmp, manifest)


def remove_incomplete_manifest(mdir: Path, manifest: Path) -> None:
    if not manifest.exists() or (mdir / "discord_desktop_core").exists():
        return
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return
    if set(data) == {"discord_krisp"}:
        manifest.unlink()


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def watch(parent_pid: int, dest: Path, manifest: Path) -> None:
    stopped = Event()
    lock = Lock()

    def repair() -> None:
        with lock:
            deploy(dest, quiet=True)
            register(manifest, create=False)

    class Handler(FileSystemEventHandler):
        def on_any_event(self, event) -> None:
            if event.event_type in {EVENT_TYPE_OPENED, EVENT_TYPE_CLOSED_NO_WRITE}:
                return
            repair()

    observer = Observer()
    observer.schedule(Handler(), str(dest.parent), recursive=True, event_filter=WATCHED_EVENTS)
    observer.start()
    try:
        repair()
        while process_alive(parent_pid):
            stopped.wait(PARENT_CHECK_INTERVAL)
    finally:
        observer.stop()
        observer.join()


def start_watcher(dest: Path, manifest: Path) -> None:
    if not hasattr(os, "fork"):
        return
    parent_pid = os.getppid()
    if os.fork() != 0:
        return
    try:
        os.setsid()
        with open(os.devnull, "w", encoding="utf-8") as devnull:
            os.dup2(devnull.fileno(), 1)
            os.dup2(devnull.fileno(), 2)
        watch(parent_pid, dest, manifest)
    finally:
        os._exit(0)


def main() -> None:
    mdir = modules_dir()
    dest = mdir / "discord_krisp"
    manifest = mdir / "installed.json"

    remove_incomplete_manifest(mdir, manifest)
    deploy(dest)
    register(manifest, create=False)
    start_watcher(dest, manifest)


if __name__ == "__main__":
    main()
