# Quickshell Review

Reviewed on 2026-04-03.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. Most of the earlier shell/theme wiring gaps are now closed. The
main remaining mismatch is that the settings surface still omits one theme key
the backend already supports.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | `neovide_mono_font_size_offset` exists in theming state but is missing from the editable settings list. | The backend and the settings UI no longer expose the same theme surface. |
