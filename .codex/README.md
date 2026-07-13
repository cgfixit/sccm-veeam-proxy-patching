# Codex Setup

This directory contains repo-local Codex guidance for `cgfixit/sccm-veeam-proxy-patching`.

## What This Repo Is

A PowerShell 5.1-compatible maintenance helper for Veeam Backup & Replication VMware proxies during SCCM/ConfigMgr patching windows. The script disables selected VBR proxies, drains active backup tasks, remotely stops Veeam services, then starts services and re-enables proxies after patching.

## First Files To Read

- `AGENTS.md`: repo rules, validation commands, and safety posture.
- `README.md`: operator runbook, SCCM integration, requirements, and exit codes.
- `SECURITY.md`: vulnerability reporting and WinRM/service-account guidance.
- `sccmpatch.ps1`: production script.
- `tests/sccmpatch.Tests.ps1`: static Pester coverage.

## Skills

- `.codex/skills/code-optimizer/SKILL.md`
- `.codex/skills/proxy-maintenance-safety/SKILL.md`
- `.codex/skills/pester-validation/SKILL.md`
- `.codex/skills/docs-runbook-sync/SKILL.md`

Use the smallest skill that matches the work. Most changes should need only `code-optimizer` or `pester-validation`.

## Non-Goals

- No live Veeam, WinRM, SCCM, or proxy operations during normal Codex validation.
- No new frameworks or dependencies for this one-script repo unless there is a concrete failing check that requires one.
- No broad rewrite of `sccmpatch.ps1` without a specific defect, measurable risk, or requested refactor.
