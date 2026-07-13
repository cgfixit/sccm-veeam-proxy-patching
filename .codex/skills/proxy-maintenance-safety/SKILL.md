---
name: proxy-maintenance-safety
description: Review changes that can affect Veeam proxy drain, service stop/start, WinRM, SCCM exit codes, or backup-infrastructure availability.
---

# Proxy Maintenance Safety

Use this skill for safety review of production-impacting changes.

## Review Checklist

- `Pre` stage disables only the selected VBR proxy objects and waits for matching active tasks to drain.
- Drain logic does not interrupt active backups or treat unrelated running tasks as safe to ignore without evidence.
- Timeout behavior exits `30` and leaves enough log evidence for SCCM operators.
- Remote service stop/start uses explicit proxy targets and does not broaden to non-target hosts.
- `Post` stage attempts service start before proxy re-enable and preserves exit `60` for re-enable failure.
- Reboot detection remains scoped to the script host, not remote proxies.
- Logs do not expose credentials, tokens, or environment secrets.
- README and tests match any changed parameter, exit code, or operator action.

## Output

Lead with a verdict:

- `PASS`: no blocking production-safety issue found.
- `BLOCKED`: change can disrupt backup infrastructure, hide failure, or strand disabled proxies.
- `PARTIAL`: static evidence is acceptable, but live-environment behavior still needs operator validation.

Keep findings file/line grounded and specific.
