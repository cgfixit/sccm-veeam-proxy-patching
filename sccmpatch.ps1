<#
Author: Chris Grady (cgfixit.com & cgfixit.com/code)

Purpose  : Gracefully drain selected VMware proxies, stop Veeam services for
           patching/reboot, then return them to production.
Pre      : Disable selected proxies, wait for backup tasks to drain, then stop
           Veeam services safely for patching/reboot.
Post     : Start services, re-enable proxies, and return 3010 when the script
           host has a pending Windows reboot.

Exit codes:
    0    Success
    10   Proxy objects not found
    20   Disable failed (Pre)
    30   Task-drain timeout (Pre)
    40   Stop-service failure (Pre)
    50   Start-service failure (Post)
    60   Re-enable failure (Post)
    90   Invalid Stage argument
    99   Unhandled error
    3010 Reboot pending (Post, for SCCM)
#>

[CmdletBinding()]
param(
    [string]$Stage = 'Pre',
    [string[]]$Proxies = @('F-1', 'M-1'),
    [ValidateRange(1, 3600)]
    [int]$PollDelay = 30,
    [ValidateRange(1, 1440)]
    [int]$DrainTimeoutMinutes = 30
)

$script:LogPath = $null

function Initialize-ProxyLog {
    $script:LogPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath (
        'ProxyMaintenance_{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    )
}

function Write-ProxyLog {
    param(
        [Parameter(Mandatory)]
        [string]$Msg,
        [string]$Level = 'INFO',
        [switch]$ToConsole
    )

    $entry = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Msg
    try {
        Add-Content -LiteralPath $script:LogPath -Value $entry -ErrorAction Stop
    }
    catch {
        Write-Warning ('Unable to write log file: {0}' -f $_.Exception.Message)
    }

    if ($ToConsole) {
        Write-Host $Msg -ForegroundColor Cyan
    }
}

function Wait-ProxyTasksToDrain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$ProxyObjects,
        [Parameter(Mandatory)]
        [int]$PollDelay,
        [Parameter(Mandatory)]
        [int]$DrainTimeoutMinutes
    )

    Write-ProxyLog 'Waiting for active tasks to drain...' -ToConsole
    $proxyIdSet = @{}
    foreach ($proxy in $ProxyObjects) {
        if ($null -ne $proxy.Id) {
            $proxyIdSet[$proxy.Id] = $proxy.Name
        }
    }

    $startTime = Get-Date
    do {
        $runningSessions = @(
            Get-VBRBackupSession -ErrorAction Stop |
                Where-Object { $_.State -eq 'Working' }
        )
        $runningTasks = @()
        if ($runningSessions.Count -gt 0) {
            $runningTasks = @(
                $runningSessions |
                    Get-VBRTaskSession -ErrorAction Stop |
                    Where-Object { $_.Status -eq 'InProgress' }
            )
        }

        $busyTask = $null
        foreach ($task in $runningTasks) {
            if ($task.Info -and $task.Info.WorkDetails) {
                $proxyId = $task.Info.WorkDetails.SourceProxyId
                if ($proxyId -and $proxyIdSet.ContainsKey($proxyId)) {
                    $busyTask = $task
                    break
                }
            }
        }

        if ($busyTask) {
            Write-ProxyLog (
                'Task still active on proxy {0}: {1}' -f
                $proxyIdSet[$busyTask.Info.WorkDetails.SourceProxyId], $busyTask.Name
            ) 'WARN' -ToConsole

            if (((Get-Date) - $startTime).TotalMinutes -ge $DrainTimeoutMinutes) {
                throw [System.TimeoutException]::new(
                    ('Task drain timeout after {0} minutes.' -f $DrainTimeoutMinutes)
                )
            }

            Write-ProxyLog (
                '{0} active task(s) remain; sleeping {1}s.' -f $runningTasks.Count, $PollDelay
            ) -ToConsole
            Start-Sleep -Seconds $PollDelay
        }
    } while ($busyTask)

    Write-ProxyLog 'No active tasks; stopping services.' -ToConsole
}

function Invoke-ProxyServiceAction {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$ProxyNames,
        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Stop')]
        [string]$Action
    )

    foreach ($node in $ProxyNames) {
        $verb = if ($Action -eq 'Start') { 'Starting' } else { 'Stopping' }
        Write-ProxyLog ('{0} Veeam services on {1}...' -f $verb, $node) -ToConsole
        if ($PSCmdlet.ShouldProcess($node, ('{0} Veeam services' -f $Action))) {
            Invoke-Command -ComputerName $node -ErrorAction Stop -ScriptBlock {
                param($ServiceAction)

                $services = @(Get-Service -Name 'Veeam*' -ErrorAction Stop)
                if ($services.Count -eq 0) {
                    throw 'No Veeam services were found.'
                }

                if ($ServiceAction -eq 'Stop') {
                    $services | Stop-Service -Force -ErrorAction Stop
                }
                else {
                    $services | Start-Service -ErrorAction Stop
                }
            } -ArgumentList $Action
        }
    }
}

function Invoke-ProxyMaintenance {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Stage,
        [string[]]$Proxies,
        [Parameter(Mandatory)]
        [int]$PollDelay,
        [Parameter(Mandatory)]
        [int]$DrainTimeoutMinutes
    )

    $ErrorActionPreference = 'Stop'
    Initialize-ProxyLog

    try {
        Write-ProxyLog ('Process begins (Stage: {0}, Proxies: {1})' -f $Stage, ($Proxies -join ', ')) -ToConsole

        if (($Stage -ne 'Pre') -and ($Stage -ne 'Post')) {
            Write-ProxyLog 'Invalid -Stage argument. Use Pre or Post.' 'ERROR' -ToConsole
            return 90
        }

        if (-not $Proxies -or $Proxies.Count -eq 0) {
            Write-ProxyLog 'No proxy names were supplied.' 'ERROR' -ToConsole
            return 10
        }

        if (-not $PSCmdlet.ShouldProcess(($Proxies -join ', '), ('Run {0} proxy maintenance' -f $Stage))) {
            return 0
        }

        Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
        $proxyObjects = @(Get-VBRViProxy -Name $Proxies -ErrorAction Stop)
        if ($proxyObjects.Count -eq 0) {
            Write-ProxyLog 'No matching proxies found.' 'ERROR' -ToConsole
            return 10
        }

        if ($Stage -eq 'Pre') {
            try {
                $proxyObjects | Disable-VBRViProxy -ErrorAction Stop
            }
            catch {
                Write-ProxyLog ('Failed to disable proxies: {0}' -f $_) 'ERROR' -ToConsole
                return 20
            }

            try {
                Wait-ProxyTasksToDrain -ProxyObjects $proxyObjects -PollDelay $PollDelay -DrainTimeoutMinutes $DrainTimeoutMinutes
            }
            catch [System.TimeoutException] {
                Write-ProxyLog $_.Exception.Message 'ERROR' -ToConsole
                return 30
            }
            catch {
                Write-ProxyLog ('Failed while draining proxy tasks: {0}' -f $_) 'ERROR' -ToConsole
                return 99
            }

            try {
                Invoke-ProxyServiceAction -ProxyNames $Proxies -Action Stop
            }
            catch {
                Write-ProxyLog ('Failed to stop Veeam services: {0}' -f $_) 'ERROR' -ToConsole
                return 40
            }

            Write-ProxyLog 'Stage Pre completed successfully' -ToConsole
            return 0
        }

        try {
            Invoke-ProxyServiceAction -ProxyNames $Proxies -Action Start
        }
        catch {
            Write-ProxyLog ('Failed to start Veeam services: {0}' -f $_) 'ERROR' -ToConsole
            return 50
        }

        try {
            $proxyObjects | Enable-VBRViProxy -ErrorAction Stop
        }
        catch {
            Write-ProxyLog ('Failed to re-enable proxies: {0}' -f $_) 'ERROR' -ToConsole
            return 60
        }

        if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            Write-ProxyLog 'Reboot pending detected' 'WARN' -ToConsole
            return 3010
        }

        Write-ProxyLog 'Stage Post completed successfully' -ToConsole
        return 0
    }
    catch {
        Write-ProxyLog ('Unhandled error: {0}' -f $_) 'ERROR' -ToConsole
        return 99
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-ProxyMaintenance -Stage $Stage -Proxies $Proxies -PollDelay $PollDelay -DrainTimeoutMinutes $DrainTimeoutMinutes)
}
