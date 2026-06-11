# Sun Schedule Review

Reviewed on 2026-06-10.

## Verdict

The `hyprsunset` ownership conflict is resolved, but the broader
night-light-versus-theme ownership story is still split; see
`docs/sun-schedule/SPEC.md` (Ownership Boundaries) for the canonical contract.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | `dark_hint` still has multiple live policy initiators and no daemon-owned override model. | This split is documented as deliberate in `docs/sun-schedule/SPEC.md`; the remaining issue is the absence of a unified override policy, pending an owner decision. Per-key upsert persistence removed the data-integrity risk of concurrent writers. |
