#!/usr/bin/env python3
"""ctx: a summary tree over a project's Claude Code transcripts (docs/ctx.md)."""

import argparse
import concurrent.futures
import fcntl
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
SHARE = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
DATA = SHARE / "ctx"
OPENCODE = SHARE / "opencode"
SOFT, HARD = 16_000, 32_000
IDLE = 3600
EVENT_CAP = 6_000
RESULT_CAP = 300
BATCH = 120_000
SUMMARY_CAP = 2_000

LEAF_PROMPT = """You index transcripts of Claude Code sessions for later retrieval. Each <chunk> is a contiguous stretch of one session: USER is the human, CLAUDE or GPT the agent, PROMPT what started a GPT session, "> tool" the agent's tool calls, "< result" the first and last bytes of their output.

For each chunk write a summary of at most 1200 bytes:
- First line: what this stretch was about, with the date.
- Then terse bullets, only those that apply: done (as reported, and whether a result showed it); decided (adopted by the human or recorded) versus merely proposed; failed, retried, or worked around (say how; flag special cases and patches around a problem); claims the transcript does not verify; open questions; commits, files, jobs, ids named.
Prefer exact names, numbers and ids over adjectives. Never invent; omit what the chunk lacks.

Reply with JSON only: {"<id>": "<summary>", ...} covering every chunk id."""

MERGE_PROMPT = """You maintain a summary tree over transcripts of Claude Code sessions. Each <pair> holds the summaries of two consecutive stretches. For each pair write one summary of at most 1200 bytes covering both: first line the span's topic and dates, then the most consequential bullets: decisions (adopted versus proposed), failures and workarounds, results, unverified claims, ids. Drop routine detail first; never invent.

Reply with JSON only: {"<id>": "<summary>", ...} covering every pair id."""


def stamp(ts):
    return ts[:16].replace("T", " ") if ts else "?"


def clip(s, cap):
    return s if len(s) <= cap else s[: cap // 2] + f"\n[… {len(s) - cap} bytes …]\n" + s[-cap // 2 :]


def oneline(s, cap):
    s = " ".join(str(s).split())
    return s if len(s) <= cap else s[: cap - 1] + "…"


class Project:
    def __init__(self, slug):
        self.slug = slug
        self.src = PROJECTS / slug
        self.dir = DATA / slug
        self.chunks_path = self.dir / "chunks.jsonl"
        self.nodes_path = self.dir / "nodes.jsonl"
        self.state_path = self.dir / "state.json"

    def exists(self):
        return self.dir.is_dir()

    def load(self):
        self.chunks = [json.loads(l) for l in open(self.chunks_path)] if self.chunks_path.exists() else []
        self.nodes = {}
        if self.nodes_path.exists():
            for line in open(self.nodes_path):
                n = json.loads(line)
                self.nodes[(n["l"], n["i"])] = n["text"]
        self.state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {}

    def save_state(self):
        tmp = self.state_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state))
        tmp.replace(self.state_path)

    def append_chunks(self, new):
        with open(self.chunks_path, "a") as f:
            for c in new:
                c["i"] = len(self.chunks)
                self.chunks.append(c)
                f.write(json.dumps(c) + "\n")

    def append_nodes(self, new):
        with open(self.nodes_path, "a") as f:
            for (l, i), text in new.items():
                self.nodes[(l, i)] = text
                f.write(json.dumps({"l": l, "i": i, "text": text}) + "\n")


# ── Extraction ─────────────────────────────────────────────────


def tool_line(name, inp):
    what = next((inp[k] for k in ("description", "command", "file_path", "filePath", "path", "pattern", "prompt") if inp.get(k)), json.dumps(inp))
    return f"> tool {name}: {oneline(what, 200)}"


def result_line(text, error, full):
    flag = "[error] " if error else ""
    return f"< result {flag}" + (text if full else oneline(clip(text, RESULT_CAP), RESULT_CAP + 40))


def claude_result(block, full):
    content = block.get("content")
    if isinstance(content, list):
        content = "\n".join(x.get("text", "") for x in content if isinstance(x, dict))
    return result_line(str(content or ""), block.get("is_error"), full)


def blocks(content):
    return [{"type": "text", "text": content}] if isinstance(content, str) else (content or [])


def render(rec, full=False):
    """One transcript record as text, or None if it carries nothing worth indexing."""
    kind, msg, ts = rec.get("type"), rec.get("message") or {}, stamp(rec.get("timestamp"))
    if rec.get("isSidechain") or kind not in ("user", "assistant"):
        return None
    if kind == "assistant":
        out = []
        for b in blocks(msg.get("content")):
            if b.get("type") == "text" and b["text"].strip():
                out.append(f"## CLAUDE {ts}\n" + (b["text"] if full else clip(b["text"], EVENT_CAP)))
            elif b.get("type") == "tool_use":
                out.append(tool_line(b.get("name"), b.get("input") or {}))
        return "\n".join(out) or None
    if rec.get("toolUseResult") is not None:
        out = [claude_result(b, full) for b in blocks(msg.get("content")) if b.get("type") == "tool_result"]
        return "\n".join(out) or None
    if rec.get("isCompactSummary"):
        return f"## COMPACTION {ts}"
    origin = (rec.get("origin") or {}).get("kind")
    text = "\n".join(b.get("text", "") for b in blocks(msg.get("content")) if b.get("type") == "text").strip()
    if origin == "human":
        return f"## USER {ts}\n" + (text if full else clip(text, EVENT_CAP))
    if origin == "task-notification":
        m = re.search(r"<summary>(.*?)</summary>", text, re.S)
        return f"## NOTE {ts} {oneline(m.group(1) if m else text, 300)}"
    if origin == "peer":
        return f"## PEER {ts}\n" + oneline(text, 600 if not full else 10**9)
    return None


def records(path, start):
    """(byte offset after the record, record) for each complete line from start."""
    with open(path, "rb") as f:
        f.seek(start)
        off = start
        for raw in f:
            if not raw.endswith(b"\n"):
                break
            off += len(raw)
            try:
                yield off, json.loads(raw)
            except json.JSONDecodeError:
                continue


def role_of(path):
    """builder, advisor, headless or interactive: a session named "builder: …" or "advisor…" wins, then its kind."""
    name, kind, entry = "", None, None
    for _, r in records(path, 0):
        t = r.get("type")
        if t in ("agent-name", "custom-title"):
            name = r.get("agentName") or r.get("customTitle") or name
        elif t in ("user", "assistant") and entry is None:
            kind, entry = r.get("sessionKind"), r.get("entrypoint")
    low = name.lower()
    if low.startswith("builder") or kind == "bg":
        return "builder"
    if low.startswith("advisor"):
        return "advisor"
    return "headless" if entry == "sdk-cli" else "interactive"


def claude_events(path, start, full=False):
    for off, rec in records(path, start):
        yield off, rec.get("timestamp"), render(rec, full)


def iso(ms):
    return datetime.fromtimestamp(ms / 1000, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def webchat_events(path, start, full=False):
    """A claude.ai conversation export, one event per message."""
    for k, m in enumerate(json.loads(Path(path).read_text()).get("chat_messages", [])):
        if k >= start:
            who = "USER" if m.get("sender") == "human" else "CLAUDE"
            parts = [b.get("text", "") for b in m.get("content", []) if b.get("type") == "text"] or [m.get("text", "")]
            text = "\n".join(parts).strip()
            yield k + 1, m.get("created_at"), f"## {who} {stamp(m.get('created_at'))}\n" + (text if full else clip(text, EVENT_CAP))


def gpt_block(kind, ts, text=None, name=None, inp=None, output="", error=False, full=False):
    if kind == "tool":
        return tool_line(name, inp or {}) + "\n" + result_line(output, error, full)
    return f"## GPT {stamp(ts)}\n" + (text if full else clip(text, EVENT_CAP)) if (text or "").strip() else None


def connect(db):
    return sqlite3.connect(f"file:{db}?mode=ro", uri=True)


def is_v2(con):
    return con.execute("select 1 from sqlite_master where name = 'session_v2'").fetchone() is not None


def opencode_events(db, sid, start, full=False):
    """A GPT session in either of opencode's schemas: a row per step with its content (v2), or per message with parts."""
    con = connect(db)
    if is_v2(con):
        for row, ms, kind, data in con.execute("select rowid, time_created, type, data from session_message "
                                               "where session_id = ? and rowid > ? order by rowid", (sid, start)):
            ts, d = iso(ms), json.loads(data)
            if kind == "assistant" and not d.get("time", {}).get("completed"):
                return
            out = []
            if kind == "user":
                out.append(f"## PROMPT {stamp(ts)}\n" + (d.get("text", "") if full else clip(d.get("text", ""), EVENT_CAP)))
            for b in d.get("content") or [] if kind == "assistant" else []:
                st = b.get("state") or {}
                if b.get("type") == "tool":
                    body = "\n".join(x.get("text", "") for x in st.get("content") or [] if isinstance(x, dict))
                    out.append(gpt_block("tool", ts, name=b.get("name"), inp=st.get("input"), output=body or str(st.get("error", "")),
                                         error=st.get("status") == "error", full=full))
                elif b.get("type") == "text":
                    out.append(gpt_block("text", ts, text=b.get("text"), full=full))
            yield row, ts, "\n".join(filter(None, out)) or None
        return
    for row, mid, ms, data in con.execute("select rowid, id, time_created, data from message "
                                          "where session_id = ? and rowid > ? order by rowid", (sid, start)):
        ts, role, out = iso(ms), json.loads(data).get("role"), []
        for (part,) in con.execute("select data from part where message_id = ? order by id", (mid,)):
            b = json.loads(part)
            st = b.get("state") or {}
            if b.get("type") == "tool":
                out.append(gpt_block("tool", ts, name=b.get("tool"), inp=st.get("input"), output=str(st.get("output") or st.get("error") or ""),
                                     error=st.get("status") == "error", full=full))
            elif b.get("type") == "text" and role == "assistant":
                out.append(gpt_block("text", ts, text=b.get("text"), full=full))
            elif b.get("type") == "text":
                out.append(f"## PROMPT {stamp(ts)}\n" + (b.get("text", "") if full else clip(b.get("text", ""), EVENT_CAP)))
        yield row, ts, "\n".join(filter(None, out)) or None


def events_of(src, start, full=False):
    if src.startswith("opencode:"):
        _, db, sid = src.split(":", 2)
        return opencode_events(db, sid, start, full)
    return (webchat_events if src.endswith(".json") else claude_events)(src, start, full)


def opencode_sessions(p):
    """(src, role, done) of each session in a directory that `opencode-dirs` (lines of `<directory> <role>`) assigns."""
    listed = p.dir / "opencode-dirs"
    dirs = [line.split() for line in listed.read_text().splitlines() if line.strip()] if listed.exists() else []
    for db in sorted(OPENCODE.glob("opencode*.db")) if dirs else []:
        con = connect(db)
        v2 = is_v2(con)
        rows = con.execute(f"select id, directory, time_updated from {'session_v2' if v2 else 'session'}").fetchall()
        for sid, directory, updated in rows:
            role = next((r for d, r in dirs if directory == d or directory.startswith(d + "/")), None)
            if role:
                last = v2 and con.execute("select type from session_message where session_id = ? order by rowid desc limit 1", (sid,)).fetchone()
                yield f"opencode:{db}:{sid}", role, sid, (last and last[0] == "idle") or time.time() - updated / 1000 > IDLE


def chunk(events, start, ended):
    """Finalized chunks of (position after, timestamp, text or None) events, and the position they reach."""
    out, cur, size, t0, t1, c0, prev = [], [], 0, None, None, start, start

    def cut():
        nonlocal cur, size, t0, c0
        out.append({"t0": t0, "t1": t1, "off": [c0, prev], "text": "\n".join(cur)})
        cur, size, t0, c0 = [], 0, None, prev

    for pos, ts, text in events:
        if text is not None:
            if cur and (size + len(text) > HARD or (size >= SOFT and text.startswith("## USER"))):
                cut()
            cur.append(text)
            size += len(text) + 1
            t0 = t0 or ts
            t1 = ts or t1
        prev = pos
    if cur and (size >= SOFT or ended):
        cut()
    return out, c0 if cur else prev


def index(p, ended):
    """Append every newly finalized chunk, ordered by end time; tiny one-off sessions are skipped."""
    new = []

    def take(src, session, role, done):
        start = p.state.get(src, 0)
        chunks, reached = chunk(events_of(src, start), start, done)
        if start == 0 and done and sum(len(c["text"]) for c in chunks) < 2_000:
            chunks = []
        who = role() if chunks and callable(role) else role
        for c in chunks:
            c.update(session=session, role=who, src=src)
        new.extend(chunks)
        p.state[src] = reached

    for path in sorted(p.src.glob("*.jsonl")):
        src, st = str(path), path.stat()
        if st.st_size > p.state.get(src, 0):
            take(src, path.stem, lambda: role_of(path), src in ended or time.time() - st.st_mtime > IDLE)
    for path in sorted((p.dir / "imports").glob("*.json")):
        take(str(path), path.stem, "webchat", True)
    for src, role, sid, done in opencode_sessions(p):
        take(src, sid, role, done)
    new.sort(key=lambda c: c["t1"] or "")
    p.append_chunks(new)
    p.save_state()
    return len(new)


# ── Summaries ──────────────────────────────────────────────────


def ask(model, system, body, tries=2):
    env = dict(os.environ, CTX_SUMMARIZER="1")
    r = subprocess.run(
        ["claude", "--print", "--model", model, "--system-prompt", system, "--tools", "", "--setting-sources", "",
         "--no-session-persistence", "--output-format", "json"],
        input=body, capture_output=True, text=True, env=env, cwd=DATA, timeout=900)
    if r.returncode:
        raise RuntimeError(f"claude exited {r.returncode}: {r.stderr.strip()[:300]}")
    reply = json.loads(r.stdout)["result"]
    try:
        return json.loads(reply[reply.index("{") : reply.rindex("}") + 1])
    except ValueError:
        if tries == 1:
            raise
        return ask(model, system, body, tries - 1)


def batches(items, size_of):
    cur, size = [], 0
    for it in items:
        if cur and size + size_of(it) > BATCH:
            yield cur
            cur, size = [], 0
        cur.append(it)
        size += size_of(it)
    if cur:
        yield cur


def header(c):
    return f"{c['role']} {c['session'][:8]} {stamp(c['t0'])} → {stamp(c['t1'])[5:]}"


def leaf_job(model, group):
    body = "\n".join(f'<chunk id="{c["i"]}" session="{header(c)}">\n{c["text"]}\n</chunk>' for c in group)
    got = ask(model, LEAF_PROMPT, body)
    return {(0, c["i"]): capped(got[str(c["i"])]) for c in group if str(c["i"]) in got}


def merge_job(model, level, group, nodes):
    body = "\n".join(
        f'<pair id="{i}">\n<a>{nodes[(level - 1, 2 * i)]}</a>\n<b>{nodes[(level - 1, 2 * i + 1)]}</b>\n</pair>' for i in group)
    got = ask(model, MERGE_PROMPT, body)
    return {(level, i): capped(got[str(i)]) for i in group if str(i) in got}


def capped(s):
    s = s.strip()
    return s if len(s) <= SUMMARY_CAP else s[: SUMMARY_CAP - 1] + "…"


def summarize(p, model, jobs):
    """Build every missing leaf summary, then every buildable merge, level by level."""
    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        todo = [c for c in p.chunks if (0, c["i"]) not in p.nodes]
        run(pool, [lambda g=g: leaf_job(model, g) for g in batches(todo, lambda c: len(c["text"]))], p)
        level = 1
        while (len(p.chunks) >> level) > 0:
            ready = [i for i in range(len(p.chunks) >> level)
                     if (level, i) not in p.nodes and (level - 1, 2 * i) in p.nodes and (level - 1, 2 * i + 1) in p.nodes]
            size = lambda i: len(p.nodes[(level - 1, 2 * i)]) + len(p.nodes[(level - 1, 2 * i + 1)])
            run(pool, [lambda g=g, lv=level: merge_job(model, lv, g, p.nodes) for g in batches(ready, size)], p)
            level += 1


def run(pool, calls, p):
    for fut in concurrent.futures.as_completed([pool.submit(c) for c in calls]):
        try:
            p.append_nodes(fut.result())
        except Exception as e:
            print(f"ctx: a summary batch failed, retried next sync: {e}", file=sys.stderr)


# ── Views ──────────────────────────────────────────────────────


def span(l, i):
    return i << l, 1 << l


def ref(l, i):
    s, n = span(l, i)
    return f"{s}+{n}"


def parse_ref(s):
    start, _, n = s.partition("+")
    start, n = int(start), int(n or 1)
    l = n.bit_length() - 1
    if n != 1 << l or start % n:
        sys.exit(f"ctx: {s} is not a node: the length must be a power of two dividing the start")
    return l, start >> l


def line(p, l, i):
    s, n = span(l, i)
    a, b = p.chunks[s], p.chunks[min(s + n, len(p.chunks)) - 1]
    roles = sorted({c["role"] for c in p.chunks[s : s + n]})
    head = f"[{ref(l, i)}] {stamp(a['t0'])} → {stamp(b['t1'])} {','.join(roles)}"
    if l == 0:
        head += f" {a['session'][:8]}"
    text = p.nodes.get((l, i))
    return f"{head}\n" + (text or f"(not summarized yet: {len(a['text'])} bytes; zoom to read)")


def cover(p, l, i):
    """The coarsest built nodes covering node (l, i)."""
    if (l, i) in p.nodes or l == 0:
        return [(l, i)]
    return cover(p, l - 1, 2 * i) + cover(p, l - 1, 2 * i + 1)


def roots(count):
    out, start = [], 0
    for l in range(count.bit_length() - 1, -1, -1):
        if count >> l & 1:
            out.append((l, start >> l))
            start += 1 << l
    return out


def view(p, budget):
    """Expand first the node nearest the end in units of its own size, as uniichat merges, so detail fades with age."""
    frontier = [n for r in roots(len(p.chunks)) for n in cover(p, *r)]
    size = lambda ns: sum(len(line(p, *n)) + 1 for n in ns)
    total = size(frontier)
    while True:
        due = sorted(((len(p.chunks) - (i + 1 << l)) / (1 << l), -l, k) for k, (l, i) in enumerate(frontier)
                     if l and (l - 1, 2 * i) in p.nodes and (l - 1, 2 * i + 1) in p.nodes)
        for _, _, k in due:
            l, i = frontier[k]
            kids = [(l - 1, 2 * i), (l - 1, 2 * i + 1)]
            grow = size(kids) - size([frontier[k]])
            if total + grow <= budget:
                frontier[k : k + 1] = kids
                total += grow
                break
        else:
            return frontier


# ── Commands ───────────────────────────────────────────────────


def slug_of(cwd):
    return re.sub(r"[^A-Za-z0-9]", "-", str(cwd))


def cmd_sync(p, args):
    p.dir.mkdir(parents=True, exist_ok=True)
    (p.dir / "imports").mkdir(exist_ok=True)
    with open(p.dir / "lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        p.load()
        n = index(p, set(args.ended or []))
        print(f"ctx: {n} new chunks, {len(p.chunks)} in all")
        if not args.index_only:
            summarize(p, args.model, args.jobs)
            missing = sum((0, c["i"]) not in p.nodes for c in p.chunks)
            print(f"ctx: {len(p.nodes)} summaries; {missing} chunks not yet summarized")


def cmd_view(p, args):
    p.load()
    print("Retrieval aid over raw transcripts, not current state or decision authority: summaries may be wrong, "
          "so zoom to the raw text before relying on one. `ctx zoom <ref>` expands a node; a leaf shows its transcript.")
    print(f"{len(p.chunks)} leaves through {stamp(p.chunks[-1]['t1']) if p.chunks else '-'}.\n")
    for n in view(p, args.budget):
        print(line(p, *n) + "\n")


def cmd_zoom(p, args):
    p.load()
    l, i = parse_ref(args.ref)
    if span(l, i)[0] >= len(p.chunks):
        sys.exit(f"ctx: no node {args.ref}")
    if l > 0:
        for k in (2 * i, 2 * i + 1):
            if span(l - 1, k)[0] < len(p.chunks):
                print(line(p, l - 1, k) + "\n")
        return
    c = p.chunks[i]
    print(f"[{args.ref}] {header(c)} {c['src']}\n")
    if args.full:
        a, b = c["off"]
        for pos, _, text in events_of(c["src"], a, True):
            if pos > b:
                break
            if text:
                print(text)
    else:
        print(c["text"])


def cmd_grep(p, args):
    p.load()
    rx = re.compile(args.regex, re.I)
    for c in p.chunks:
        hits = [l for l in c["text"].splitlines() if rx.search(l)]
        if hits:
            print(f"[{c['i']}+1] {header(c)}")
            for h in hits[: args.max]:
                print("   " + oneline(h, 240))


def cmd_hook(_, args):
    """SessionEnd: sync the session's project in the background if ctx tracks it."""
    if os.environ.get("CTX_SUMMARIZER"):
        return
    event = json.load(sys.stdin)
    path = Path(event.get("transcript_path", ""))
    p = Project(path.parent.name)
    if p.exists():
        log = open(p.dir / "sync.log", "a")
        subprocess.Popen([sys.argv[0], f"--project={p.slug}", "sync", "--ended", str(path)],
                         stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)


def main():
    ap = argparse.ArgumentParser(prog="ctx", description=__doc__)
    ap.add_argument("--project", help="a ~/.claude/projects directory name (default: the current directory's)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sync", help="index new transcript text, then summarize")
    s.add_argument("--ended", action="append", help="a transcript whose session ended (its tail is final)")
    s.add_argument("--index-only", action="store_true")
    s.add_argument("--model", default="haiku")
    s.add_argument("--jobs", type=int, default=4)
    v = sub.add_parser("view", help="the whole history at a fixed size, recent parts finer")
    v.add_argument("--budget", type=int, default=48_000)
    z = sub.add_parser("zoom", help="a node's two children, or a leaf's transcript text")
    z.add_argument("ref")
    z.add_argument("--full", action="store_true", help="a leaf's records with tool output in full")
    g = sub.add_parser("grep", help="leaves whose text matches a regex")
    g.add_argument("regex")
    g.add_argument("--max", type=int, default=5)
    sub.add_parser("hook", help="the SessionEnd hook")
    args = ap.parse_args()
    p = Project(args.project or slug_of(Path.cwd()))
    if args.cmd not in ("sync", "hook") and not p.exists():
        sys.exit(f"ctx: {p.slug} is not tracked; run `ctx sync` there first")
    {"sync": cmd_sync, "view": cmd_view, "zoom": cmd_zoom, "grep": cmd_grep, "hook": cmd_hook}[args.cmd](p, args)


if __name__ == "__main__":
    main()
