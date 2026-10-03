BeforeAll {
    $ScriptPath = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\sccmpatch.ps1')).Path

    # Dot-sourcing imports functions without running Veeam or WinRM operations.
    . $ScriptPath

    # Pester requires a command to exist before it can mock it.
    function Get-VBRViProxy { param($Name) }
    function Disable-VBRViProxy {}
    function Get-VBRBackupSession {}
    function Get-VBRTaskSession {}
    function Enable-VBRViProxy {}
    function Get-VBRServerSession {}
    function Connect-VBRServer { param($Server) }
    function Disconnect-VBRServer {}
    function Get-VBRBackupServerInfo {}

    function Get-ScriptAst {
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $ScriptPath, [ref]$null, [ref]$errors
        )
        $errors | Should -BeNullOrEmpty
        return $ast
    }
}

Describe 'sccmpatch.ps1 behavior' {
    BeforeEach {
        Mock Get-ProxyHostEnvironment {
            [pscustomobject]@{ IsWindows = $true; Is64BitProcess = $true; Edition = 'Core'; Version = [version]'7.6.3' }
        }
        Mock Get-ItemProperty {
            [pscustomobject]@{ DisplayName = 'Veeam Backup & Replication Server'; DisplayVersion = '13.1.1.18' }
        }
        Mock Get-Module {
            if ($ListAvailable) {
                [pscustomobject]@{ Path = Join-Path $TestDrive 'Veeam.Backup.PowerShell.psd1'; PowerShellVersion = [version]'7.6.3'; CompatiblePSEditions = @('Core') }
            }
        }
        Mock Get-VBRServerSession {}
        Mock Connect-VBRServer {}
        Mock Disconnect-VBRServer {}
        Mock Get-VBRBackupServerInfo { [pscustomobject]@{ Build = [version]'13.1.1.18' } }
    }

    Describe 'sccmpatch.ps1 parser and parameters' {

        It 'parses without syntax errors' {
            { Get-ScriptAst } | Should -Not -Throw
        }

        It 'declares the expected script parameters' {
            $ast = Get-ScriptAst
            $names = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath

            $names | Should -Contain 'Stage'
            $names | Should -Contain 'VBRServer'
            ($names -join ',') | Should -Be 'Stage,Proxies,PollDelay,DrainTimeoutMinutes,VBRServer'
            $names | Should -Contain 'Proxies'
            $names | Should -Contain 'PollDelay'
            $names | Should -Contain 'DrainTimeoutMinutes'
        }

        It 'keeps numeric polling parameters above zero' {
            $ast = Get-ScriptAst
            foreach ($name in @('PollDelay', 'DrainTimeoutMinutes')) {
                $param = $ast.ParamBlock.Parameters | Where-Object {
                    $_.Name.VariablePath.UserPath -eq $name
                }
                $range = $param.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateRange' }
                $range | Should -Not -BeNullOrEmpty
                $range.PositionalArguments[0].Value | Should -Be 1
            }
        }

        It 'uses ASCII source so Windows PowerShell 5.1 reads the script consistently' {
            $bytes = [System.IO.File]::ReadAllBytes($ScriptPath)
            @($bytes | Where-Object { $_ -gt 127 }) | Should -BeNullOrEmpty
        }
    }

    Describe 'sccmpatch.ps1 SCCM exit-code contract' {

        It 'returns 90 for an invalid stage before loading Veeam' {
            Mock Write-ProxyLog {}
            Mock Import-Module {}

            $result = Invoke-ProxyMaintenance -Stage 'Invalid' -Proxies @('Proxy1') -PollDelay 1 -DrainTimeoutMinutes 1

            $result | Should -Be 90
            Should -Invoke Import-Module -Times 0
        }

        It 'returns 10 when no proxy names are supplied' {
            Mock Write-ProxyLog {}
            Mock Import-Module {}

            $result = Invoke-ProxyMaintenance -Stage 'Pre' -Proxies @() -PollDelay 1 -DrainTimeoutMinutes 1

            $result | Should -Be 10
            Should -Invoke Import-Module -Times 0
        }

        It 'returns 20 when disabling a proxy fails' {
            Mock Write-ProxyLog {}
            Mock Import-Module {}
            Mock Get-VBRViProxy { @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) }
            Mock Disable-VBRViProxy { throw 'disable failed' }

            $result = Invoke-ProxyMaintenance -Stage 'Pre' -Proxies @('Proxy1') -PollDelay 1 -DrainTimeoutMinutes 1

            $result | Should -Be 20
        }

        It 'returns 0 for a successful Pre stage with no active sessions' {
            Mock Write-ProxyLog {}
            Mock Import-Module {}
            Mock Get-VBRViProxy { @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) }
            Mock Disable-VBRViProxy {}
            Mock Get-VBRBackupSession { @() }
            Mock Invoke-Command {}

            $result = Invoke-ProxyMaintenance -Stage 'Pre' -Proxies @('Proxy1') -PollDelay 1 -DrainTimeoutMinutes 1

            $result | Should -Be 0
            Should -Invoke Disable-VBRViProxy -Times 1
            Should -Invoke Invoke-Command -Times 1
        }

        It 'returns 40 when stopping proxy services fails' {
            Mock Write-ProxyLog {}
            Mock Import-Module {}
            Mock Get-VBRViProxy { @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) }
            Mock Disable-VBRViProxy {}
            Mock Get-VBRBackupSession { @() }
            Mock Invoke-Command { throw 'stop failed' }

            $result = Invoke-ProxyMaintenance -Stage 'Pre' -Proxies @('Proxy1') -PollDelay 1 -DrainTimeoutMinutes 1

            $result | Should -Be 40
        }

        It 'returns 50 when starting proxy services fails' {
            Mock Write-ProxyLog {}
            Mock Import-Module {}
            Mock Get-VBRViProxy { @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) }
            Mock Invoke-Command { throw 'start failed' }

            $result = Invoke-ProxyMaintenance -Stage 'Post' -Proxies @('Proxy1') -PollDelay 1 -DrainTimeoutMinutes 1

            $result | Should -Be 50
        }

        It 'returns 60 when re-enabling proxies fails' {
            Mock Write-ProxyLog {}
            Mock Import-Module {}
            Mock Get-VBRViProxy { @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) }
            Mock Invoke-Command {}
            Mock Enable-VBRViProxy { throw 'enable failed' }

            $result = Invoke-ProxyMaintenance -Stage 'Post' -Proxies @('Proxy1') -PollDelay 1 -DrainTimeoutMinutes 1

            $result | Should -Be 60
        }

        It 'returns 99 when the Veeam module cannot load' {
            Mock Write-ProxyLog {}
            Mock Import-Module { throw 'module missing' }

            $result = Invoke-ProxyMaintenance -Stage 'Pre' -Proxies @('Proxy1') -PollDelay 1 -DrainTimeoutMinutes 1

            $result | Should -Be 99
        }

        It 'supports WhatIf without loading Veeam' {
            Mock Write-ProxyLog {}
            Mock Import-Module {}

            $result = Invoke-ProxyMaintenance -Stage 'Pre' -Proxies @('Proxy1') -PollDelay 1 -DrainTimeoutMinutes 1 -WhatIf

            $result | Should -Be 0
            Should -Invoke Import-Module -Times 0
        }

        It 'returns 30 when a targeted task remains past the drain timeout' {
            Mock Write-ProxyLog {}
            $script:DrainTestTime = [datetime]'2026-01-01T00:00:00'
            $script:DrainSleepSeconds = $null
            Mock Get-Date { $script:DrainTestTime }
            Mock Start-Sleep {
                param($Seconds)
                $script:DrainSleepSeconds = $Seconds
                $script:DrainTestTime = $script:DrainTestTime.AddMinutes(1)
            }
            Mock Get-VBRBackupSession { @([pscustomobject]@{ State = 'Working' }) }
            Mock Get-VBRTaskSession {
                @([pscustomobject]@{
                    Status = 'InProgress'
                    Name = 'Backup task'
                    Info = [pscustomobject]@{
                        WorkDetails = [pscustomobject]@{ SourceProxyId = 'proxy-1' }
                    }
                })
            }
            Mock Get-VBRViProxy { @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) }

            $result = $null
            try {
                Wait-ProxyTasksToDrain -ProxyObjects @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) -PollDelay 120 -DrainTimeoutMinutes 1
            }
            catch [System.TimeoutException] {
                $result = 30
            }

            $result | Should -Be 30
            $script:DrainSleepSeconds | Should -Be 60
            Should -Invoke Start-Sleep -Times 1
        }

        It 'ignores active tasks that use an unselected proxy' {
            Mock Write-ProxyLog {}
            Mock Start-Sleep {}
            Mock Get-VBRBackupSession { @([pscustomobject]@{ State = 'Working' }) }
            Mock Get-VBRTaskSession {
                @([pscustomobject]@{
                    Status = 'InProgress'
                    Name = 'Other proxy task'
                    Info = [pscustomobject]@{
                        WorkDetails = [pscustomobject]@{ SourceProxyId = 'other-proxy' }
                    }
                })
            }

            { Wait-ProxyTasksToDrain -ProxyObjects @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) -PollDelay 1 -DrainTimeoutMinutes 1 } |
                Should -Not -Throw
            Should -Invoke Start-Sleep -Times 0
        }
    }

    Describe 'sccmpatch.ps1 Post stage' {

        It 'starts services, re-enables proxies, and returns 3010 for a pending reboot' {
            Mock Write-ProxyLog {}
            Mock Import-Module {}
            Mock Get-VBRViProxy { @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) }
            Mock Invoke-Command {}
            Mock Enable-VBRViProxy {}
            Mock Test-Path { $true }

            $result = Invoke-ProxyMaintenance -Stage 'Post' -Proxies @('Proxy1') -PollDelay 1 -DrainTimeoutMinutes 1

            $result | Should -Be 3010
            Should -Invoke Invoke-Command -Times 1
            Should -Invoke Enable-VBRViProxy -Times 1
        }
    }

    Describe 'sccmpatch.ps1 VBR startup gate' {
        BeforeEach {
            Mock Write-ProxyLog {}
            Mock Import-Module {}
            Mock Get-VBRViProxy { [pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' } }
            Mock Disable-VBRViProxy {}
            Mock Get-VBRBackupSession {}
            Mock Invoke-Command {}
        }

        It 'retains the original positional maintenance arguments' {
            Invoke-ProxyMaintenance Pre @('Proxy1') 1 1 | Should -Be 0
            Should -Invoke Get-VBRViProxy -Times 1 -ParameterFilter { $Name -contains 'Proxy1' }
        }

        It 'returns 30 from maintenance when draining times out and disconnects its own session' {
            Mock Wait-ProxyTasksToDrain { throw [System.TimeoutException]::new('fixture timeout') }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 30
            Should -Invoke Disconnect-VBRServer -Times 1
            Should -Invoke Invoke-Command -Times 0
        }

        It 'rejects missing or multiple server information records before maintenance' -ForEach @(
            @{ Records = 0 }; @{ Records = 2 }
        ) {
            Mock Get-VBRBackupServerInfo {
                for ($i = 0; $i -lt $Records; $i++) { [pscustomobject]@{ Build = [version]'13.1.1.18' } }
            }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Get-VBRViProxy -Times 0
            Should -Invoke Disconnect-VBRServer -Times 1
        }

        It 'accepts supported installed release <Product> on <Edition> <Runtime>' -ForEach @(
            @{ Product = '12.3.2.4854'; Edition = 'Desktop'; Runtime = '5.1'; Minimum = '5.1' }
            @{ Product = '13.0.0.4967'; Edition = 'Core'; Runtime = '7.4.7'; Minimum = '7.4.7' }
            @{ Product = '13.1.1.18'; Edition = 'Core'; Runtime = '7.6.3'; Minimum = '7.6.3' }
        ) {
            Mock Get-ProxyHostEnvironment {
                [pscustomobject]@{ IsWindows = $true; Is64BitProcess = $true; Edition = $Edition; Version = [version]$Runtime }
            }
            Mock Get-ItemProperty { [pscustomobject]@{ DisplayName = 'Veeam Backup & Replication Server'; DisplayVersion = $Product } }
            Mock Get-Module {
                if ($ListAvailable) {
                    [pscustomobject]@{ Path = Join-Path $TestDrive 'Veeam.Backup.PowerShell.psd1'; PowerShellVersion = [version]$Minimum; CompatiblePSEditions = @($Edition) }
                }
            }
            Mock Get-VBRBackupServerInfo { [pscustomobject]@{ Build = [version]$Product } }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 0
            Should -Invoke Connect-VBRServer -Times 1 -ParameterFilter { $Server -eq 'localhost' }
            Should -Invoke Disconnect-VBRServer -Times 1
            Should -Invoke Invoke-Command -Times 1
        }

        It 'refuses installed metadata <Product> before import or connection' -ForEach @(
            @{ Product = '' }; @{ Product = 'invalid' }; @{ Product = '12.2.0.1' }; @{ Product = '14.0.0.1' }; @{ Product = '13.2.0.1' }
            @{ Product = '12.3.2.4854' }
        ) {
            Mock Get-ItemProperty { [pscustomobject]@{ DisplayName = 'Veeam Backup & Replication Server'; DisplayVersion = $Product } }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Import-Module -Times 0
            Should -Invoke Connect-VBRServer -Times 0
            Should -Invoke Get-VBRViProxy -Times 0
        }

        It 'refuses non-Windows and 32-bit environments before registry discovery' -ForEach @(
            @{ Windows = $false; Bit64 = $true }; @{ Windows = $true; Bit64 = $false }
        ) {
            Mock Get-ProxyHostEnvironment { [pscustomobject]@{ IsWindows = $Windows; Is64BitProcess = $Bit64 } }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Get-ItemProperty -Times 0
            Should -Invoke Import-Module -Times 0
        }

        It 'refuses missing installation and mixed releases' -ForEach @(@{ Mixed = $false }; @{ Mixed = $true }) {
            Mock Get-ItemProperty {
                if ($Mixed) {
                    [pscustomobject]@{ DisplayName = 'Veeam Backup & Replication Server'; DisplayVersion = '12.3.2.4854' }
                    [pscustomobject]@{ DisplayName = 'Veeam Backup & Replication Console'; DisplayVersion = '13.1.1.18' }
                }
            }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Import-Module -Times 0
        }

        It 'requires an explicit target on a Console-only host' {
            Mock Get-ItemProperty { [pscustomobject]@{ DisplayName = 'Veeam Backup & Replication Console'; DisplayVersion = '13.1.1.18' } }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Connect-VBRServer -Times 0
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 -VBRServer fixture-vbr | Should -Be 0
            Should -Invoke Connect-VBRServer -Times 1 -ParameterFilter { $Server -eq 'fixture-vbr' }
        }

        It 'rejects ambiguous modules, manifest floors, editions, and conflicting loaded modules' -ForEach @(
            @{ Failure = 'ambiguous' }; @{ Failure = 'minimum' }; @{ Failure = 'edition' }; @{ Failure = 'loaded' }; @{ Failure = 'missing' }
        ) {
            Mock Get-Module {
                if ($ListAvailable -and $Failure -ne 'missing') {
                    [pscustomobject]@{
                        Path = Join-Path $TestDrive 'Veeam.Backup.PowerShell.psd1'
                        PowerShellVersion = if ($Failure -eq 'minimum') { [version]'7.7' } else { [version]'7.0' }
                        CompatiblePSEditions = if ($Failure -eq 'edition') { @('Desktop') } else { @('Core') }
                    }
                    if ($Failure -eq 'ambiguous') { [pscustomobject]@{ Path = Join-Path $TestDrive 'other.psd1' } }
                }
                elseif (-not $ListAvailable -and $Failure -eq 'loaded') { [pscustomobject]@{ Path = Join-Path $TestDrive 'other.psd1' } }
            }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Import-Module -Times 0
        }

        It 'rejects v13.1 on a runtime below its release floor' {
            Mock Get-ProxyHostEnvironment { [pscustomobject]@{ IsWindows = $true; Is64BitProcess = $true; Edition = 'Core'; Version = [version]'7.4.7' } }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Import-Module -Times 0
        }

        It 'preserves an existing session and refuses maintenance' {
            Mock Get-VBRServerSession { [pscustomobject]@{} }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Connect-VBRServer -Times 0
            Should -Invoke Disconnect-VBRServer -Times 0
            Should -Invoke Get-VBRViProxy -Times 0
        }

        It 'refuses invalid or mismatched connected builds and disconnects its own session' -ForEach @(
            @{ Build = '' }; @{ Build = 'garbage' }; @{ Build = '13.0.0.4967' }; @{ Build = '12.3.2.4854' }
        ) {
            Mock Get-VBRBackupServerInfo { [pscustomobject]@{ Build = $Build } }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Get-VBRViProxy -Times 0
            Should -Invoke Disconnect-VBRServer -Times 1
        }

        It 'allows a revision difference accepted by Connect and retains the maintenance exit code if cleanup fails' {
            Mock Get-VBRBackupServerInfo { [pscustomobject]@{ Build = [version]'13.1.1.99' } }
            Mock Disable-VBRViProxy { throw 'disable failed' }
            Mock Disconnect-VBRServer { throw 'disconnect failed' }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 20
            Should -Invoke Disconnect-VBRServer -Times 1
        }

        It 'does not claim ownership when Connect fails' {
            Mock Connect-VBRServer { throw 'connection failed' }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 99
            Should -Invoke Get-VBRViProxy -Times 0
            Should -Invoke Disconnect-VBRServer -Times 0
        }

        It 'validates the build before proxy discovery and imports the selected absolute module' {
            $script:StartupOrder = @()
            Mock Import-Module { $script:StartupOrder += 'import' }
            Mock Connect-VBRServer { $script:StartupOrder += 'connect' }
            Mock Get-VBRBackupServerInfo { $script:StartupOrder += 'build'; [pscustomobject]@{ Build = [version]'13.1.1.18' } }
            Mock Get-VBRViProxy { $script:StartupOrder += 'proxy'; @() }
            Invoke-ProxyMaintenance -Stage Pre -Proxies Proxy1 -PollDelay 1 -DrainTimeoutMinutes 1 | Should -Be 10
            ($script:StartupOrder -join ',') | Should -Be 'import,connect,build,proxy'
            Should -Invoke Import-Module -Times 1 -ParameterFilter { $Name -eq (Join-Path $TestDrive 'Veeam.Backup.PowerShell.psd1') }
            Should -Invoke Disconnect-VBRServer -Times 1
        }
    }

}
