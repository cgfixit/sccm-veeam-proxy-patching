BeforeAll {
    $ScriptPath = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\sccmpatch.ps1')).Path

    # Dot-sourcing imports functions without running Veeam or WinRM operations.
    . $ScriptPath

    # Pester requires a command to exist before it can mock it.
    function Get-VBRViProxy {}
    function Disable-VBRViProxy {}
    function Get-VBRBackupSession {}
    function Get-VBRTaskSession {}
    function Enable-VBRViProxy {}

    function Get-ScriptAst {
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $ScriptPath, [ref]$null, [ref]$errors
        )
        $errors | Should -BeNullOrEmpty
        return $ast
    }
}

Describe 'sccmpatch.ps1 parser and parameters' {

    It 'parses without syntax errors' {
        { Get-ScriptAst } | Should -Not -Throw
    }

    It 'declares the expected script parameters' {
        $ast = Get-ScriptAst
        $names = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath

        $names | Should -Contain 'Stage'
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

    It 'returns 30 when a targeted task remains past the drain timeout' {
        Mock Write-ProxyLog {}
        $script:DrainTestTime = [datetime]'2026-01-01T00:00:00'
        Mock Get-Date { $script:DrainTestTime }
        Mock Start-Sleep { $script:DrainTestTime = $script:DrainTestTime.AddMinutes(1) }
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
            Wait-ProxyTasksToDrain -ProxyObjects @([pscustomobject]@{ Id = 'proxy-1'; Name = 'Proxy1' }) -PollDelay 1 -DrainTimeoutMinutes 1
        }
        catch [System.TimeoutException] {
            $result = 30
        }

        $result | Should -Be 30
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
