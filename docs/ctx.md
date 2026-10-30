# ctx

## Intent

- `ctx` turns a project's Claude Code transcripts into a summary tree, the way
  uniichat does a chat: leaves are contiguous stretches of one session, and
  each parent summarizes two children. One long-lived advisor session and many
  fresh builder sessions share one tree, so after a compaction the advisor can
  zoom back into anything a builder did.
- It is installed on the desktop only and tracks one project, moneymachine: a
  project is tracked once `ctx sync` has run in it, and the hook ignores the
  rest.
- The tree is a retrieval aid, never an authority. A summary can be wrong, so
  anything consequential is read at the leaf (`ctx zoom`, `--full` for whole
  tool output) and checked against the project's own records. Every `view`
  says so.
- The transcripts are the source of truth and stay where Claude Code writes
  them. `~/.local/share/ctx/<project>/` holds only the index (`chunks.jsonl`),
  the summaries (`nodes.jsonl`), the read offsets, and `imports/` for claude.ai
  conversation exports. It is never committed: transcripts hold secrets.
- Both data files are append-only, and chunk order is the order sessions'
  stretches were finalized, so the tree only ever grows at its end.
- A session's role comes from its name (`claude --name "builder: …"` or
  `advisor…`), else its kind (background or headless). Name sessions; don't
  maintain a role table.
- Summaries run on Haiku through `claude --print` on the subscription.
  Indexing, `view`, `zoom` and `grep` make no model calls.

## Quirks

### Claude Code deletes transcripts after 30 days by default
`cleanupPeriodDays` in `~/.claude/settings.json` must stay large (3650), or
leaves keep their indexed text but `zoom --full` loses its source.

### The SessionEnd hook is outside this repo
`ctx hook` is registered in `~/.claude/settings.json`, which Home Manager does
not manage, and syncs only projects that already have a ctx directory.

### The summarizer must not see itself
Its `claude --print` calls run with `--no-session-persistence` and
`--setting-sources ""`: otherwise each writes a transcript that the next sync
indexes, and each fires the SessionEnd hook again.

### A transcript's tail is provisional
An active session's last stretch is re-read every sync and finalized only once
it reaches 16 KB, the session ends, or its file has been idle for an hour; a
quiet session's newest work is absent from `view` until then.
