# Quickshell Review

Reviewed on 2026-04-07.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. Most of the earlier shell/theme wiring gaps are now closed. The
remaining issues are now narrower: one theme-setting omission in the settings
surface, and one shell IPC path that still only reports failures.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | `neovide_mono_font_size_offset` exists in theming state but is missing from the editable settings list. | The backend and the settings UI no longer expose the same theme surface. |
| Low | `theme.apply` still has no positive completion reporting. | `config/quickshell/shell.qml:376-410` now tokenizes args safely and reports failures through `ToastService.showError(...)`, but successful completion is still silent. IPC callers can fire-and-forget a theme change, but they do not get a matching success signal or toast from the shell. |
