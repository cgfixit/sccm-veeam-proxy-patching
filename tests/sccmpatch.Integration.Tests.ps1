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

        $output = & ((Get-Process -Id $PID).Path) @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 90
        $output | Should -Match 'Invalid -Stage argument'
    }
}

Describe 'sccmpatch.ps1 CLI WhatIf' {
    It 'accepts and forwards WhatIf before installation discovery' {
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\sccmpatch.ps1')).Path
        $output = & ((Get-Process -Id $PID).Path) -NoLogo -NoProfile -NonInteractive -File $scriptPath -Stage Pre -Proxies Proxy1 -VBRServer fixture-vbr -WhatIf 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'What if:'
        $output | Should -Not -Match 'Unhandled error'
    }
}
