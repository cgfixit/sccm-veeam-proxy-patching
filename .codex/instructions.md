# Codex Runtime Instructions

- Start with `AGENTS.md`; it is the repo contract.
- Before editing behavior, read the full `sccmpatch.ps1` flow and the matching tests.
- Default validation is static: parser check, Pester, and PSScriptAnalyzer when available.
- Never use a live proxy, VBR host, SCCM target, or WinRM command as a smoke test unless the user explicitly requests a live operational run.
- Keep production script changes PowerShell 5.1 or 7 compatible (depending on windows and vbr version).
- Keep SCCM exit codes and README documentation in sync.
