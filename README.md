# Veeam proxy maintenance for SCCM patching

`sccmpatch.ps1` coordinates maintenance of selected Windows VMware backup proxies from a Windows Veeam Backup & Replication server or a Windows management host with the matching Veeam Console installed.

`Pre` disables the selected proxies, waits for their active backup tasks to drain, then stops their Veeam services over WinRM. `Post` starts those services, re-enables the proxies, and returns `3010` if the **script host** has a pending reboot. The SCCM task sequence patches the script host; service operations target the proxy names you supply.

## VBR detection and PowerShell requirements

The script identifies the local Veeam Server or Console release from Windows installed-product records. It reads `DisplayName` and `DisplayVersion` under the native 64-bit `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` key. Only the exact `Veeam Backup & Replication Server` and `Veeam Backup & Replication Console` product names qualify. The generic installer bundle is also used by Enterprise Manager and does not establish a backup-server installation. The presence of `powershell.exe` or `pwsh.exe` is not used to infer the VBR version.

| Installed Veeam release | Required host |
| --- | --- |
| VBR 12, starting at 12.3.2 | 64-bit Windows PowerShell 5.1, Desktop edition |
| VBR 13.0 | 64-bit PowerShell 7, Core edition, meeting the installed module's declared minimum |
| VBR 13.1 | 64-bit PowerShell 7.6.3 or later, Core edition, meeting the installed module's declared minimum |

The script also checks the selected module's `PowerShellVersion` and `CompatiblePSEditions` before importing it. The table describes the script's compatibility gates. Use the PowerShell build supported by Veeam for your installed VBR release; satisfying a manifest minimum does not certify every later PowerShell release.

The [VBR 12.3.2 archive](https://helpcenter.veeam.com/archive/backup/120/powershell/getting_started.html) requires Windows PowerShell 5.1. The [VBR 13 global changes](https://helpcenter.veeam.com/docs/vbr/powershell/global_changes_v13.html) require PowerShell 7. The [current Windows instructions](https://helpcenter.veeam.com/docs/vbr/powershell/running_ps_sessions_windows.html?ver=13), checked on October 3, 2026, apply to VBR 13.1.1.18 and specify PowerShell 7.6.3. Do not apply a historical 13.0 PowerShell build requirement to all of VBR 13.

After import, the script connects to `-VBRServer` under the current Windows identity and reads the actual backup server version with [`Get-VBRBackupServerInfo`](https://helpcenter.veeam.com/docs/vbr/powershell/get-vbrbackupserverinfo.html). The local installed release and connected server build are logged separately. Their major, minor, and build components must match. Windows Installer metadata may not reflect a hotfix revision, so the script leaves revision compatibility to Veeam's connection checks. The Console must match the server as described in [Veeam's Console requirements](https://helpcenter.veeam.com/docs/vbr/userguide/console_install_before_you_begin.html).

Missing, malformed, ambiguous, unsupported, or mismatched version evidence returns `99` before proxy lookup or service operations. An incompatible shell also returns `99` with the required executable and version. The script does not install PowerShell or relaunch itself. Configure SCCM with the correct executable below. Versions older than 12.3.2, VBR 13.2 or later, and future major versions require an explicit compatibility update.

A [Veeam installation report and product-team response](https://forums.veeam.com/viewtopic.php?f=2&start=30&t=100568) demonstrate why this distinction matters: the Server and Console MSI records remained at 12.3.2.3617 after a patch, while `Get-VBRBackupServerInfo` reported 12.3.2.4165.

The installed-product lookup uses [Windows Installer metadata](https://learn.microsoft.com/en-us/windows/win32/msi/uninstall-registry-key). It identifies the local release, including Console-only installations; it is not a remote server query or a guarantee of the exact patched binary version.

## Prerequisites

- Run in a fresh, 64-bit Windows PowerShell process with no existing Veeam server session. The script refuses to take over an existing session.
- Install the Veeam Console and its PowerShell module on the management host. Keep it compatible with the intended backup server.
- Supply `-VBRServer` on a Console-only host. A local Server installation can use the default `localhost` target.
- Use a Veeam Backup Administrator account with local administrator rights on the selected Windows proxies. Veeam PowerShell does not support MFA. See [KB4535](https://www.veeam.com/kb4535) and [SECURITY.md](SECURITY.md).
- Enable WinRM and allow connectivity from the script host to each target proxy. Configure Kerberos or HTTPS according to your environment.
- Use an execution policy that permits the script, such as `RemoteSigned` or `AllSigned`.

A Windows Console can connect to a VBR 13 Linux backup server. The SCCM host and the proxies whose Windows services this script manages must still be Windows machines. This script does not patch a Linux appliance or manage Linux proxy services.

## Usage

Copy `sccmpatch.ps1` to the VBR server or management host, such as `C:\Scripts`. Run it in the required shell, with your actual proxy names and backup server target.

```powershell
.\sccmpatch.ps1 -Stage Pre -Proxies 'Proxy1','Proxy2' -VBRServer 'VBRServer'
.\sccmpatch.ps1 -Stage Post -Proxies 'Proxy1','Proxy2' -VBRServer 'VBRServer'
.\sccmpatch.ps1 -Stage Pre -Proxies 'Proxy1','Proxy2' -DrainTimeoutMinutes 60 -VBRServer 'VBRServer'
```

`-WhatIf` returns before installation discovery, Veeam module import, connection, or remote operations. It previews the requested maintenance action; it does **not** validate prerequisites or query current backup activity.

```powershell
.\sccmpatch.ps1 -Stage Pre -Proxies 'Proxy1','Proxy2' -WhatIf
```

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-Stage` | `Pre` | `Pre` or `Post`. Other values return `90`. |
| `-Proxies` | The two example names in the script | Windows proxy names as registered in VBR. Always override these for your environment. |
| `-VBRServer` | Local server when installed | Explicit backup server name. Required on a Console-only host. |
| `-PollDelay` | `30` | Seconds between drain polls, from 1 through 3600. |
| `-DrainTimeoutMinutes` | `30` | Maximum drain duration, from 1 through 1440 minutes. |

## SCCM task sequence

Use a **Run Command Line** step with the matching shell. These examples construct the proxy array inside PowerShell because native `-File` argument passing does not reliably preserve a multi-element array in Windows PowerShell 5.1. Keep `exit $LASTEXITCODE` to propagate the script's SCCM code from `-Command`.

VBR 12.3.2, from a 64-bit SCCM step:

```text
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "& 'C:\Scripts\sccmpatch.ps1' -Stage Pre -Proxies @('Proxy1','Proxy2') -VBRServer 'VBRServer'; exit $LASTEXITCODE"
```

VBR 13, using a supported PowerShell 7 installation:

```text
"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -NonInteractive -Command "& 'C:\Scripts\sccmpatch.ps1' -Stage Pre -Proxies @('Proxy1','Proxy2') -VBRServer 'VBRServer'; exit $LASTEXITCODE"
```

Use this sequence:

1. Run `Pre`. Accept only `0`, and stop the sequence on failure.
2. Install the approved Windows updates on the VBR or management host.
3. Run the same version-appropriate command with `-Stage Post`. Accept `0` and `3010`.
4. Let ConfigMgr's restart policy handle `3010` for the script host.

Disable the task-sequence option to run as a 32-bit process. The startup check rejects 32-bit hosts. For an Application deployment type, configure the return-code mappings below and provide a separate Post recovery step.

| Code | Meaning | SCCM action |
| --- | --- | --- |
| `0` | Success | Continue |
| `3010` | Post succeeded; script host has a pending reboot | Soft reboot |
| `10` | Empty proxy list or no matching proxy objects | Fail and verify names |
| `20` | Pre failed to disable proxies | Fail and inspect VBR permissions and connectivity |
| `30` | Pre task-drain timeout | Fail; inspect active work and timeout |
| `40` | Pre failed to stop proxy services | Fail and inspect WinRM or service access |
| `50` | Post failed to start proxy services | Fail and inspect proxy service health |
| `60` | Post failed to re-enable proxies | Fail; restore proxy availability manually if needed |
| `90` | Invalid Stage | Fail and correct the command |
| `99` | Startup/version/module/connection failure or unhandled error | Fail and inspect the log |

A Pre failure after proxy disable can leave proxies disabled. Inspect the log and recover through Post or the Veeam Console when the cause is resolved.

## Logs and troubleshooting

Logs are written to `%TEMP%\ProxyMaintenance_yyyyMMdd-HHmmss.log` in the account running the script. They record the local Veeam installation, PowerShell host, connected server build, stage, and operation failures. Retain these files with your SCCM deployment evidence; temporary files may be cleaned by Windows.

For `99`, check the logged installed version and required PowerShell executable first. Confirm the Console and server releases match, that `-VBRServer` names the intended server, and that a single Veeam module installation is discoverable. Start a fresh shell if a Veeam session already exists. Repair missing or conflicting product records instead of guessing a version. Complete any Veeam certificate trust setup through the supported administrative process; the script does not force certificate acceptance.

For `30`, inspect the selected proxies' active work in Veeam before increasing the timeout. The default poll interval is 30 seconds and the default timeout is 30 minutes. For `40` or `50`, inspect WinRM and the `Veeam*` services on the named proxies. For `60`, inspect server connectivity and re-enable the proxies in the Console after services are healthy.

## Validation and limitations

The tests execute the script with isolated Windows installation, PowerShell host, Veeam, and WinRM doubles. They cover version decisions, refusal before mutation, ordering, and SCCM return values. CI runs on PowerShell 7 and Windows PowerShell 5.1. These checks do not load real Veeam assemblies or perform live proxy maintenance.

The existing drain algorithm uses `task.Info.WorkDetails.SourceProxyId`. Veeam's public PowerShell reference does not document that internal property. The exact VBR 13 Windows installer records have not been verified against a live installation. Validate task-to-proxy matching on your VBR build before production use, along with registry metadata, module loading, service behavior, and Windows process exit `3010`. Test a complete Pre/Post cycle in a non-production environment and retain a recovery plan.
