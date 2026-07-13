BeforeAll {
    $PowerShellCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $PowerShellCommand) {
        $PowerShellCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
    }
}

Describe 'sccmpatch.ps1 process entrypoint' {

    It 'returns SCCM code 90 for an invalid stage without loading Veeam' {
        $scriptPath = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\sccmpatch.ps1')).Path
        $arguments = @(
            '-NoLogo'
            '-NoProfile'
            '-NonInteractive'
            '-ExecutionPolicy'
            'Bypass'
            '-File'
            $scriptPath
            '-Stage'
            'Invalid'
            '-Proxies'
            'Proxy1'
        )

        $output = & $PowerShellCommand.Source @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 90
        $output | Should -Match 'Invalid -Stage argument'
    }
}
