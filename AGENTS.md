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

## Documentation

Each domain has exactly one doc: `docs/<domain>.md`. Read the relevant ones —
plus `TODO.md` for open issues near your area — before working; `[[name]]`
links between docs point at `docs/<name>.md`.

Each doc has two sections and nothing else:

- **Intent** — invariants and design decisions the code cannot express: what
  must stay true, and why, in the owner's voice. This is the review anchor.
  When the implementation and Intent conflict, that is a wall in the sense of
  the header above: stop and surface it, don't patch around it.
- **Quirks** — non-obvious operational knowledge. Admission test: an entry
  must name the wrong conclusion a competent agent would reach from the code
  alone, or the debugging time it would burn. If you cannot state the trap,
  the entry does not belong.

The docs never describe the implementation. No file maps, no data-flow
narratives, no restated command surfaces, no "current state as of <date>" —
the code is its own map and agents can read it. A doc that drifts into
describing code is a second source of truth and must be cut back.

After making changes:

- Delete or fix any doc statement your change made false. Pruning outranks
  adding.
- Add a quirk only if it passes the trap test and came out of real debugging.
- If your change intentionally diverges from Intent, update Intent (and say
  so); otherwise fix the implementation, not the doc.
- If you resolved a `TODO.md` entry, delete the entry.

## Comments

A one-line comment stating a local invariant belongs at the code it protects
— the flag an agent would otherwise remove, the ordering that must not change.
Anything longer belongs in the domain doc, with the comment reduced to a
pointer if needed. No narration, no history.

## File References

Docs cite file paths plus stable in-file anchors: function names, option
names, section headings, short quoted snippets. Never line numbers — they go
stale immediately.

## Nix

Style rules. They are mechanical: either the code follows them or it doesn't.

- Modules take the standard argument set and nothing else. A module never
  becomes `{ someArg }: { config, pkgs, ... }:` and is never called as
  `(import ./x.nix { ... })` from an `imports` list. Anything a module needs
  arrives through `pkgs`, `config`, or a `specialArgs` entry that applies to
  every module (`host`, `inputs`, `dotfilesPath`).
- Never put a value in a `let` binding that duplicates a module option. If it
  is set through `config.*`, read it back through `config.*`. `let` is for
  computed derivations and local helpers.
- Packages belong in an overlay, not in a `let`. `overlays/local-packages.nix`
  for new derivations; `overlays/native-optimized.nix` for host-native builds.
- `pkgs.optimized.<name>` is the natively-optimized build of a nixpkgs package;
  `pkgs.optimize.cc` / `pkgs.optimize.rust` apply the same treatment to a
  derivation that came from a flake input. Never re-derive either by hand.
- Cross-dependencies inside `pkgs.optimized` are wired explicitly with
  `.override`. A package that silently links the stock build of another
  optimized package puts two copies of it in the closure.
- Shared helpers go in `lib/<namespace>.nix`, which takes `{ self }` and
  returns the attrset to merge into `lib`. `lib/default.nix` picks it up with
  no registration step.
- `let inherit (lib.lists) head;` with the full submodule path, never
  `inherit (lib) head`. Exception: names that have no submodule path.
- Never `rec`. Use a `let` binding or `lib.fixedPoints.fix`.
- Prefer `lib.getExe pkgs.foo` over an interpolated `"${pkgs.foo}/bin/foo"`.
- `/* lua */`, `/* bash */`, `/* qml */` before a multiline string holding code
  in that language.
- Section comments in a large module use the existing
  `# ── Section ─────` rule, not bare `# Section`.
- Long-form CLI flags in anything written to a file or a derivation. Short
  flags are for interactive use only.
- Pipe operators (`|>`) for multi-step list and attrset transforms rather than
  nested calls. They are enabled through `nix.settings.experimental-features`.

## Tooling

Rules about how to run things here, mostly earned by wasting time.

- Never `find /nix/store` or grep across it. Use `nix derivation show`,
  `nix path-info`, or `nix eval` against a concrete attribute path.
- Never `builtins.getFlake` on this repo. It copies the whole worktree into the
  store, `desktopctl/target/` included, which is thousands of files.
- Use `jq` rather than python to read JSON. It avoids a permission prompt.
- A dirty flake only sees *tracked* files. `git add` new files before any
  `nix eval`, or they are invisible and the error will not say so.
- A refactor that is supposed to change nothing must not move
  `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`.
  Capture it before, compare after; `nix derivation show -r` on both diffs the
  closure when it does move. The flake's own source path is the one legitimate
  difference, since editing any file changes it.
- Never run `nixos-rebuild switch` or `boot` unprompted. These are live
  machines. Evaluate and build; let the owner switch.
