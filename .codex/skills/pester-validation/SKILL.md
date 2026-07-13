---
name: pester-validation
description: Run and interpret the repo's PowerShell parser, Pester, PSScriptAnalyzer, and GitHub Actions validation for sccmpatch.ps1 changes.
---

# Pester Validation

Use this skill when validating edits or diagnosing failed checks.

## Local Checks

Run the parser check first because it is cheap and catches syntax regressions:

```powershell
pwsh -NoLogo -NoProfile -Command "$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path './sccmpatch.ps1'), [ref]$null, [ref]$errors); if ($errors) { $errors | Format-List; exit 1 }"
```

Run Pester next:

```powershell
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
```

If installed locally, run analyzer:

```powershell
pwsh -NoLogo -NoProfile -Command "Invoke-ScriptAnalyzer -Path . -Recurse"
```

## CI Checks

Expected workflows:

- `Pester Tests`
- `PSScriptAnalyzer`
- `CodeQL Advanced`
- `Dependency review` on pull requests

Use GitHub Actions logs for failures; do not infer root cause from workflow names alone.

## Failure Handling

- Parser failure: fix syntax first.
- Pester failure: update script or test so the documented contract is true.
- Analyzer failure: prefer changing the script over suppressing rules.
- Missing local modules: report as an environment limitation and rely on CI if the workflow has the required action/tool.
