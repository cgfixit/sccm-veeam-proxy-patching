---
name: docs-runbook-sync
description: Keep README, SECURITY, tests, and sccmpatch.ps1 aligned for SCCM/Veeam operator guidance, parameters, logs, and exit codes.
---

# Docs Runbook Sync

Use this skill when script behavior, operator steps, parameters, logging, or exit codes change.

## Sync Points

- `README.md` must describe the current parameters, defaults, SCCM success/failure codes, and Pre/Post sequence.
- `SECURITY.md` must stay accurate for WinRM, service-account, execution-policy, and elevated-operation guidance.
- `tests/sccmpatch.Tests.ps1` must cover documented exit codes and key static safety guards.
- `sccmpatch.ps1` header comments should not contradict README operator guidance.

## Workflow

1. Compare `sccmpatch.ps1` parameters and exits against README tables.
2. Compare high-risk operational behavior against SECURITY guidance.
3. Update the smallest set of docs/tests needed to remove drift.
4. Run parser and Pester checks when tests or script contracts change.

## Do Not

- Add marketing copy.
- Add unsupported live-run claims.
- Document operator steps that the script does not actually implement.
