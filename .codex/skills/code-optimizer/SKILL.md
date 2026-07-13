---
name: code-optimizer
description: Optimize sccmpatch.ps1 while preserving Veeam proxy safety, SCCM exit codes, PowerShell 5.1 compatibility, and the repo validation path.
---

# Code Optimizer

Use this skill for focused optimization or refactoring of `sccmpatch.ps1`.

## Rules

- Read `AGENTS.md`, `sccmpatch.ps1`, `tests/sccmpatch.Tests.ps1`, and the relevant README section first.
- Optimize one concrete issue at a time: duplicated logic, fragile null handling, slow polling, unclear error handling, or documentation drift.
- Preserve the SCCM exit-code contract unless tests and README change in the same PR.
- Preserve PowerShell 5.1 compatibility in production code.
- Do not add dependencies for simple parsing, logging, or validation.
- Do not replace static validation with live Veeam or WinRM testing.

## Workflow

1. State the narrow target and why it matters for production survivability.
2. Make the smallest code change that fixes the target.
3. Add or update one Pester/static assertion when behavior or contracts change.
4. Update README only when parameters, exit codes, operator steps, or failure modes change.
5. Run the parser check and Pester; run PSScriptAnalyzer if available.

## Validation

```powershell
pwsh -NoLogo -NoProfile -Command "$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path './sccmpatch.ps1'), [ref]$null, [ref]$errors); if ($errors) { $errors | Format-List; exit 1 }"
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
```
