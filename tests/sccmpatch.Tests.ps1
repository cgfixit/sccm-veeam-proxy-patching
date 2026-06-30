BeforeAll {
    $ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'sccmpatch.ps1'

    function Get-ScriptAst {
        [System.Management.Automation.Language.Parser]::ParseFile(
            $ScriptPath, [ref]$null, [ref]$null
        )
    }
}

Describe 'sccmpatch.ps1 static analysis' {

    It 'parses without syntax errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $ScriptPath, [ref]$null, [ref]$errors
        )
        $errors | Should -BeNullOrEmpty
    }

    It 'declares the Stage parameter with ValidateSet Pre,Post' {
        $ast = Get-ScriptAst
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Stage' }
        $param | Should -Not -BeNullOrEmpty
        $validateSet = $param.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
        $validateSet | Should -Not -BeNullOrEmpty
        $values = $validateSet.PositionalArguments.Value
        $values | Should -Contain 'Pre'
        $values | Should -Contain 'Post'
    }

    It 'declares the Proxies parameter as string array' {
        $ast = Get-ScriptAst
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Proxies' }
        $param | Should -Not -BeNullOrEmpty
        $typeAttr = $param.Attributes | Where-Object { $_.TypeName.Name -eq 'string[]' }
        $typeAttr | Should -Not -BeNullOrEmpty
    }

    It 'declares PollDelay as int with default 30' {
        $ast = Get-ScriptAst
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'PollDelay' }
        $param | Should -Not -BeNullOrEmpty
        $param.DefaultValue.Value | Should -Be 30
    }

    It 'declares DrainTimeoutMinutes as int with default 30' {
        $ast = Get-ScriptAst
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'DrainTimeoutMinutes' }
        $param | Should -Not -BeNullOrEmpty
        $param.DefaultValue.Value | Should -Be 30
    }

    It 'has CmdletBinding attribute' {
        $ast = Get-ScriptAst
        $cmdletBinding = $ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
        $cmdletBinding | Should -Not -BeNullOrEmpty
    }
}

Describe 'sccmpatch.ps1 exit code coverage' {

    It 'defines all documented exit codes in the script' {
        $content = Get-Content $ScriptPath -Raw
        $expectedCodes = @(0, 10, 20, 30, 40, 50, 60, 90, 99, 3010)
        foreach ($code in $expectedCodes) {
            $content | Should -Match "exit\s+$code"
        }
    }

    It 'exits 10 when no proxies are found' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'No matching proxies found.*exit 10'
    }

    It 'exits 20 on disable failure' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'Failed to disable proxies.*exit 20'
    }

    It 'exits 30 on drain timeout' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'Task drain timeout.*exit 30'
    }

    It 'exits 40 on stop-service failure' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'Failed to stop Veeam services.*exit 40'
    }

    It 'exits 50 on start-service failure' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'Failed to start Veeam services.*exit 50'
    }

    It 'exits 60 on re-enable failure' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'Failed to re-enable proxies.*exit 60'
    }

    It 'exits 3010 when reboot is pending' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'Reboot pending detected.*exit 3010'
    }

    It 'exits 99 on unhandled error' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'Unhandled error.*exit 99'
    }
}

Describe 'sccmpatch.ps1 robustness checks' {

    It 'sets ErrorActionPreference to Stop inside the try block' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match '\$ErrorActionPreference\s*=\s*[''"]Stop[''"]'
    }

    It 'imports Veeam module with ErrorAction Stop' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'Import-Module\s+Veeam\.Backup\.PowerShell\s+-ErrorAction\s+Stop'
    }

    It 'checks for null task info before accessing SourceProxyId' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match '\$task\.Info\s+-and\s+\$task\.Info\.WorkDetails'
    }

    It 'guards Get-VBRTaskSession pipeline against null sessions' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'if\s*\(\$runningSessions\)'
    }

    It 'uses a proxy ID hashtable instead of per-iteration API calls' {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match '\$ProxyIdSet\s*='
        $content | Should -Match 'ProxyIdSet\.ContainsKey'
    }
}

Describe 'Write-ProxyLog function' {

    It 'is defined in the script' {
        $ast = Get-ScriptAst
        $func = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Write-ProxyLog' }, $true)
        $func | Should -Not -BeNullOrEmpty
    }

    It 'accepts Msg, Level, and ToConsole parameters' {
        $ast = Get-ScriptAst
        $func = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Write-ProxyLog' }, $true)
        $paramNames = $func[0].Body.ParamBlock.Parameters.Name.VariablePath.UserPath
        $paramNames | Should -Contain 'Msg'
        $paramNames | Should -Contain 'Level'
        $paramNames | Should -Contain 'ToConsole'
    }

    It 'defaults Level to INFO' {
        $ast = Get-ScriptAst
        $func = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Write-ProxyLog' }, $true)
        $levelParam = $func[0].Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Level' }
        $levelParam.DefaultValue.Value | Should -Be 'INFO'
    }
}
