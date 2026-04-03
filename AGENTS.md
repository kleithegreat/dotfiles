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

For quickshell work, also read `docs/theming/SPEC.md` — the shell is tightly
coupled to the theming pipeline.

## After Making Changes

Update any documentation affected by your changes. This is not optional.

- If you changed behavior that a `SPEC.md` describes, verify the spec still matches.
  If your change intentionally diverges from the spec, update the spec. If it does
  not, update your implementation.
- If you changed code that an `ARCHITECTURE.md` describes, update the architecture
  doc to reflect the new state. Include file paths and line references.
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

Architecture and review docs include specific file paths and line ranges. When
updating these docs, verify that your references point to the correct locations
after your changes. Stale line references are worse than no references.
