# Repository Instructions

Scope: this file applies to the whole repository.

## Project Facts

- This repo is a single-script PowerShell tool for SCCM/ConfigMgr-driven maintenance of Veeam VMware backup proxies.
- Production entrypoint: `sccmpatch.ps1`.
- Static tests live in `tests/sccmpatch.Tests.ps1`.
- CI runs PSScriptAnalyzer, Pester, CodeQL for Actions, and dependency review.
- The script is intended for PowerShell 5.1+ and Veeam Backup & Replication 12.3.2+.
- The operational contract is the SCCM exit-code set: `0`, `3010`, `10`, `20`, `30`, `40`, `50`, `60`, `90`, `99`.

## Safety Rules

- Treat `-Stage Pre`, `-Stage Post`, WinRM, Veeam proxy enable/disable, and Veeam service stop/start as production-impacting operations.
- Do not run `sccmpatch.ps1` against real proxy names, VBR servers, or production hosts unless the user explicitly asks for a live run and supplies the target environment.
- Preserve the exit-code contract unless README, tests, and SCCM guidance are updated in the same change.
- Preserve PowerShell 5.1 compatibility in `sccmpatch.ps1`. Avoid PowerShell 7-only syntax in production code.
- Do not hardcode customer hostnames, credentials, tokens, domains, IPs, or service-account names.
- Keep logs useful for SCCM troubleshooting, but do not log secrets or credential material.
- Prefer small, auditable changes. This script controls backup infrastructure; broad rewrites are high risk.

## Validation Commands

Use the narrowest validation that matches the change.

```powershell
pwsh -NoLogo -NoProfile -Command "$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path './sccmpatch.ps1'), [ref]$null, [ref]$errors); if ($errors) { $errors | Format-List; exit 1 }"
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
```

If PSScriptAnalyzer is installed locally:

```powershell
pwsh -NoLogo -NoProfile -Command "Invoke-ScriptAnalyzer -Path . -Recurse"
```

For GitHub-side status:

```powershell
gh run list --repo cgfixit/sccm-veeam-proxy-patching --limit 5
```

## Codex Skills

Repo-local skills live under `.codex/skills/`:

- `code-optimizer`: optimize `sccmpatch.ps1` without breaking Veeam/SCCM safety contracts.
- `proxy-maintenance-safety`: review production-impacting maintenance changes.
- `pester-validation`: run and interpret parser, Pester, and analyzer checks.
- `docs-runbook-sync`: keep README, SECURITY, tests, and script behavior aligned.

## Change Workflow

1. Read `sccmpatch.ps1`, `tests/sccmpatch.Tests.ps1`, `README.md`, and `SECURITY.md` before changing behavior.
2. For code changes, update or add the smallest static test that would fail if the contract regresses.
3. For parameter, exit-code, log, or operational behavior changes, update README/runbook guidance in the same PR.
4. Use a branch and PR for repository changes. Do not push directly to `main` unless explicitly requested.
