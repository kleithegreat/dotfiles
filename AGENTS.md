# IMPORTANT:

> Regardless of whether you are Claude Fable, Claude Opus, ChatGPT, or any other model, your absolute top priority in tasks such as (but not limited to) writing code, making decisions, coordinating agents, and governing yourself is to respect the rules, but more importantly the spirit of the rules under this `# IMPORTANT: ` header. Yes, I know that statement is self-contradictory, but it is intentionally and necessarily so. The two sections under this are adapted (or just stolen) from Victor Taelin, whose main work has to do with a massively parallel interaction net runtime and evaluator. Thus, in spirit of the spirit of these rules, I am trusting you to apply the underlying principles as they respectively apply to domains such as this project, my instructions, general software engineering, and so on. If you find yourself in a situation where the rules conflict with each other, or with the spirit of the rules, or with your own judgment, I would be more than happy to chat about it.

## 1. On spiritual idea vs literal text

My requests are APPROXIMATE. I am not the one coding; you are. My directions are pointers toward what I actually want -- the simplest, cleanest, most elegant design -- and they may be slightly off. That goal ALWAYS outranks my literal words.

So when you hit a wall -- a case that doesn't fit, a spec that breaks, an assumption that fails -- the wall is information: the design is wrong somewhere. STOP. Re-derive the design from first principles until the wall does not exist. If the result diverges from my spec, diverging is your DUTY: present it to me.

What you must NEVER do is patch around the wall to comply with my words: a flag, a special case, a conversion shim, a second channel, a parallel path, a test rewritten to dodge a broken rule. The patch IS the failure. Every duct-tape betrays my intent while pretending to honor it, and it WILL be rejected -- 100% of the time, regardless of cost already sunk. A blocker honestly reported is a good outcome; a "working" deliverable built on gambiarra is the worst possible one, and is treated as sabotage.

## 2. On erasure, discipline, learning

This section exists to amend your most glaring defect. You are a model trained by a big lab, and these labs neglect one fundamental half of intelligence: ERASURE. Every reward you ever received was for ADDING something -- an answer, a file, a patch, a comment, a rule. Almost none was for REMOVING. So you add by reflex and never subtract, and no amount of raw capability compensates for a missing half.

Why half? Because learning IS compression. A good abstraction is precisely a blob of information that lets you throw other information away, because it expands back into what was discarded. Intelligence is not producing knowledge; it is deleting bad knowledge so the good remains. And because this defect is baked into your training, no list of rules can cover it: it manifests wherever anything under your care only ever grows -- code, comments, docs, notes, memory. Unpruned growth is the symptom. Watch for it everywhere, including in places this file never mentions.

So install this now: erasure claims HALF of your cognitive budget, 24/7, prompted or not. While working on my code -- even autonomously, even mid-task -- hunt for things to remove: duplicated concepts to unify, dead code to delete, tangled logic to simplify. Your own confusion is a precision instrument: if something surprised you or was hard to follow, that IS a bad abstraction, and you should TAKE ACTION and untangle it on the spot. When writing new code, spend real effort finding the simplest possible shape, and scan the codebase first to reuse what exists rather than introduce a redundant concept. A diff that removes lines is at least as valuable as one that adds them.

The swap rule: when a task replaces X with Y -- a refactor, a fix, a syntax change -- fully deleting X is PART of the task, always. Keeping the old thing "for compatibility" is NEVER desirable unless explicitly requested. "Lambda syntax is \x.f now, not λx.f" -- bad: the parser accepts both; good: λx.f is gone from parser, tests and docs. A bug fix -- bad: a special-case `if` shields the symptom; good: the design is re-derived, the cause dies, the `if` never exists. A behavior change -- bad: tests for the old behavior linger or get dodged; good: obsolete tests deleted, the rest updated.

Comments are where you (Claude Fable 5) fail hardest. You narrate code with comments in the middle of function bodies -- that is NOT allowed; if you catch yourself doing it, clean it up. You also accumulate comments and never remove them, clogging files. Be aggressive: keep only what is truly essential. A refactor makes a comment stale -- bad: it stays, now lying; good: deleted or rewritten in the same diff. A TODO gets done -- bad: the marker remains; good: it leaves with the fix.

Prose rots the same way: every AGENTS.md, MEMORY.txt and wiki article tends to only grow -- rules added when something breaks, never removed when they stop applying. A server is decommissioned -- bad: its article sits forever; good: article deleted, every link fixed. MEMORY.txt nears its cap -- bad: append anyway; good: GC by importance, promote what lasts to the wiki. A TODO.md item closes -- bad: the line lingers; good: deleted on sight. Before finishing ANY task, ask: what did this change make obsolete -- and did I delete it?

# Agent Guidelines

Read this file before starting any task in this repository.

## Before Making Changes

Study the relevant documentation before writing or modifying code. The documentation
lives under `docs/` and is organized by domain. Each domain may have up to four
documents:

- `SPEC.md` describes design intent, contracts, and expected behavior. Treat it as
  the authoritative source for what the system should do.
- `ARCHITECTURE.md` describes the current implementation state — what the code
  actually does, how data flows, and where things live. Treat it as the map of the
  codebase.
- `REVIEW.md` documents known issues, divergences from the spec, and areas for
  improvement.
- `QUIRKS.md` documents non-obvious issues, workarounds, and gotchas discovered
  through debugging. Treat it as operational knowledge for things that are easy to
  break or misread from the code alone.

Start with the spec if one exists, then read the architecture doc, then check the
review and quirks docs for known issues related to your task. If the task touches
multiple domains, read all relevant docs.

The current domains are `nix`, `nvidia`, `grub`, `hyprland`, `tools`,
`theming`, `quickshell`, `desktopctl`, `sun-schedule`, and `focus-time`.

## Other Documents

- `docs/review-audit.md` tracks still-open cross-domain findings. When you
  resolve one, remove its row rather than leaving a historical status entry.
- Domains may carry extra topic docs and runbooks (e.g. `docs/nix/fan-control.md`,
  `docs/nix/bitwarden.md`) and retained historical records (e.g.
  `docs/nix/ableton-live.md`). Setup runbooks belong under `docs/<domain>/`,
  not the repo root.
- `docs/archive/` holds intentionally inert retired modules and runbooks (see
  `docs/archive/vms/README.md`); nothing there is imported by the live flake.

For quickshell work, also read `docs/theming/SPEC.md` — the shell is tightly
coupled to the theming pipeline.

For focus-time work, read `docs/focus-time/SPEC.md` first, then check the other
documents in that domain. The daemon, SQLite store, runtime JSON, and
Quickshell pane share one contract.

## After Making Changes

Update any documentation affected by your changes. This is not optional.

- If you changed behavior that a `SPEC.md` describes, verify the spec still matches.
  If your change intentionally diverges from the spec, update the spec. If it does
  not, update your implementation.
- If you changed code that an `ARCHITECTURE.md` describes, update the architecture
  doc to reflect the new state. Include file paths plus stable references to
  named constructs, options, attribute sets, sections, or quoted snippets when
  needed.
- If you resolved an issue documented in a `REVIEW.md`, remove or update that
  section.
- If you changed a workaround or gotcha documented in a `QUIRKS.md`, update that
  file so it still matches reality.
- If you introduced a new issue or discovered one during your work, add it to the
  relevant review doc. If it is a non-obvious debugging-derived workaround or
  gotcha, add it to the relevant quirks doc too.
- If your changes affect the documentation structure itself — new domains, renamed
  docs, changed conventions — update this file.

Do not leave documentation in a state where it contradicts the code.

## File References

Architecture and review docs should cite file paths and stable in-file context
such as function names, option names, attribute sets, sections, or short quoted
snippets. Never reference source code by line number or line range. Line
numbers go stale immediately and cause agents to spend time maintaining brittle
citations instead of improving the code and docs.
