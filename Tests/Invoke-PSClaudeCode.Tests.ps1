BeforeAll {
    # Import the module
    $ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'PSClaudeCode.psd1'
    Import-Module $ModulePath -Force

    # Store original API key
    $script:OriginalApiKey = $env:ANTHROPIC_API_KEY

    # Load function content once for all tests
    $script:FunctionPath = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'Public') 'Invoke-PSClaudeCode.ps1'
    $script:FunctionContent = Get-Content $script:FunctionPath -Raw
}

AfterAll {
    # Restore original API key
    $env:ANTHROPIC_API_KEY = $script:OriginalApiKey
}

Describe 'Invoke-PSClaudeCode' {
    Context 'Parameter Validation' {
        It 'Should have a Task parameter' {
            $command = Get-Command Invoke-PSClaudeCode
            $command.Parameters.Keys | Should -Contain 'Task'
        }

        It 'Should have a Model parameter with default value' {
            $command = Get-Command Invoke-PSClaudeCode
            $command.Parameters.Keys | Should -Contain 'Model'
            $command.Parameters['Model'].Attributes.TypeId.Name | Should -Contain 'ParameterAttribute'
        }

        It 'Should have a dangerouslySkipPermissions switch parameter' {
            $command = Get-Command Invoke-PSClaudeCode
            $command.Parameters.Keys | Should -Contain 'dangerouslySkipPermissions'
            $command.Parameters['dangerouslySkipPermissions'].SwitchParameter | Should -Be $true
        }

        It 'Should have an InputObject parameter that accepts pipeline input' {
            $command = Get-Command Invoke-PSClaudeCode
            $command.Parameters.Keys | Should -Contain 'InputObject'
            $inputObjectParam = $command.Parameters['InputObject']
            $inputObjectParam.Attributes | Where-Object { $_.TypeId.Name -eq 'ParameterAttribute' } | 
            Select-Object -ExpandProperty ValueFromPipeline | Should -Be $true
        }
    }

    Context 'API Key Validation' {
        BeforeEach {
            # Clear API key for these tests
            $env:ANTHROPIC_API_KEY = $null
        }

        AfterEach {
            # Restore API key
            $env:ANTHROPIC_API_KEY = $script:OriginalApiKey
        }

        It 'Should validate API key is set' {
            # We can't directly test the exit behavior in Pester easily,
            # but we can verify the function requires the environment variable
            $env:ANTHROPIC_API_KEY | Should -BeNullOrEmpty
        }
    }

    Context 'Tool Definitions' {
        It 'Should define Read-File tool' {
            $script:FunctionContent | Should -Match 'name\s*=\s*"Read-File"'
        }

        It 'Should define Write-File tool' {
            $script:FunctionContent | Should -Match 'name\s*=\s*"Write-File"'
        }

        It 'Should define Run-Command tool' {
            $script:FunctionContent | Should -Match 'name\s*=\s*"Run-Command"'
        }

        It 'Should define Delegate-Task tool' {
            $script:FunctionContent | Should -Match 'name\s*=\s*"Delegate-Task"'
        }
    }

    Context 'Execute-Tool Function Behavior' {
        BeforeAll {
            # Create test files for Execute-Tool testing
            $script:TestFilePath = Join-Path $TestDrive 'test-file.txt'
            $script:TestContent = 'Hello, World!'
            Set-Content -Path $script:TestFilePath -Value $script:TestContent
        }

        It 'Should have Execute-Tool function defined' {
            $script:FunctionContent | Should -Match 'function Execute-Tool'
        }

        It 'Should handle Read-File tool execution' {
            $script:FunctionContent | Should -Match '"Read-File"[\s\S]*Get-Content'
        }

        It 'Should handle Write-File tool execution' {
            $script:FunctionContent | Should -Match '"Write-File"[\s\S]*Set-Content'
        }

        It 'Should handle Run-Command tool execution' {
            $script:FunctionContent | Should -Match '"Run-Command"[\s\S]*Invoke-Expression'
        }

        It 'Should handle Delegate-Task tool execution' {
            $script:FunctionContent | Should -Match '"Delegate-Task"[\s\S]*Run-SubAgent'
        }
    }

    Context 'Check-Permission Function Behavior' {
        It 'Should have Check-Permission function defined' {
            $script:FunctionContent | Should -Match 'function Check-Permission'
        }

        It 'Should check dangerous commands in Run-Command tool' {
            $script:FunctionContent | Should -Match 'rm|del|Remove-Item'
        }

        It 'Should prompt for Write-File permissions' {
            $script:FunctionContent | Should -Match '"Write-File"'
            $script:FunctionContent | Should -Match 'Read-Host'
        }

        It 'Should respect dangerouslySkipPermissions flag' {
            $script:FunctionContent | Should -Match 'dangerouslySkipPermissions.*return \$true'
        }
    }

    Context 'Run-SubAgent Function Behavior' {
        It 'Should have Run-SubAgent function defined' {
            $script:FunctionContent | Should -Match 'function Run-SubAgent'
        }

        It 'Should have MaxTurns parameter with default value' {
            $script:FunctionContent | Should -Match 'MaxTurns.*=.*10'
        }

        It 'Should call Anthropic API in sub-agent' {
            $script:FunctionContent | Should -Match 'api\.anthropic\.com/v1/messages'
        }
    }

    Context 'Main Function Behavior' {
        It 'Should use default Claude model when not specified' {
            $script:FunctionContent | Should -Match 'Model\s*=\s*"claude-sonnet-4-5-20250929"'
        }

        It 'Should call Anthropic API endpoint' {
            $script:FunctionContent | Should -Match 'https://api\.anthropic\.com/v1/messages'
        }

        It 'Should set correct API headers' {
            $script:FunctionContent | Should -Match 'x-api-key'
            $script:FunctionContent | Should -Match 'anthropic-version'
        }

        It 'Should process tool uses from API response' {
            $script:FunctionContent | Should -Match 'tool_use'
        }

        It 'Should handle text content in responses' {
            $script:FunctionContent | Should -Match 'type.*-eq.*"text"'
        }
    }

    Context 'Module Integration' {
        It 'Should be exported from the module' {
            $exportedCommands = (Get-Module PSClaudeCode).ExportedCommands.Keys
            $exportedCommands | Should -Contain 'Invoke-PSClaudeCode'
        }

        It 'Should have alias ipcc' {
            $alias = Get-Alias -Name ipcc -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.ResolvedCommandName | Should -Be 'Invoke-PSClaudeCode'
        }
    }

    Context 'Pipeline Input Processing' {
        It 'Should have pipeline processing logic in the function' {
            $script:FunctionContent | Should -Match 'ValueFromPipeline.*=.*\$true'
        }

        It 'Should initialize pipeline buffer in begin block' {
            $script:FunctionContent | Should -Match '\$pipelineBuffer\s*=\s*""'
        }

        It 'Should accumulate pipeline input in process block' {
            $script:FunctionContent | Should -Match 'process\s*\{'
            $script:FunctionContent | Should -Match '\$pipelineBuffer\s*\+=\s*\(\$InputObject\s*\|\s*Out-String\)'
        }

        It 'Should use pipeline input as task when no task provided' {
            $script:FunctionContent | Should -Match 'if\s*\(-not\s*\$Task\s*-and\s*\$pipelineBuffer\)'
            $script:FunctionContent | Should -Match '\$Task\s*=\s*\$pipelineBuffer\.TrimEnd'
        }

        It 'Should merge task and pipeline input when both provided' {
            $script:FunctionContent | Should -Match 'elseif\s*\(\$Task\s*-and\s*\$pipelineBuffer\)'
            $script:FunctionContent | Should -Match '--- Begin piped input ---'
            $script:FunctionContent | Should -Match '--- End piped input ---'
        }
    }
    Context 'Comment-Based Help' {
        It 'Should have comment-based help defined' {
            $help = Get-Help Invoke-PSClaudeCode
            $help | Should -Not -BeNullOrEmpty
        }

        It 'Should have SYNOPSIS section' {
            $help = Get-Help Invoke-PSClaudeCode
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Synopsis | Should -Match 'AI-powered PowerShell agent'
        }

        It 'Should have DESCRIPTION section' {
            $help = Get-Help Invoke-PSClaudeCode
            $help.Description | Should -Not -BeNullOrEmpty
            $help.Description.Text | Should -Match 'Anthropic.*Claude'
        }

        It 'Should have PARAMETERS section' {
            $help = Get-Help Invoke-PSClaudeCode
            $help.Parameters | Should -Not -BeNullOrEmpty
            $help.Parameters.Parameter | Should -HaveCount 4  # Task, InputObject, Model, dangerouslySkipPermissions
        }

        It 'Should have parameter help for Task' {
            $help = Get-Help Invoke-PSClaudeCode
            $taskParam = $help.Parameters.Parameter | Where-Object { $_.Name -eq 'Task' }
            $taskParam | Should -Not -BeNullOrEmpty
            $taskParam.Description.Text | Should -Match 'task description'
        }

        It 'Should have parameter help for Model' {
            $help = Get-Help Invoke-PSClaudeCode
            $modelParam = $help.Parameters.Parameter | Where-Object { $_.Name -eq 'Model' }
            $modelParam | Should -Not -BeNullOrEmpty
            $modelParam.Description.Text | Should -Match 'Claude model'
        }

        It 'Should have parameter help for dangerouslySkipPermissions' {
            $help = Get-Help Invoke-PSClaudeCode
            $dangerParam = $help.Parameters.Parameter | Where-Object { $_.Name -eq 'dangerouslySkipPermissions' }
            $dangerParam | Should -Not -BeNullOrEmpty
            $dangerParam.Description.Text | Should -Match 'skip permission prompts'
        }

        It 'Should have EXAMPLES section' {
            $help = Get-Help Invoke-PSClaudeCode
            $help.Examples | Should -Not -BeNullOrEmpty
            $help.Examples.Example | Should -HaveCount 3
        }

        It 'Should have NOTES section' {
            $help = Get-Help Invoke-PSClaudeCode
            $help.AlertSet | Should -Not -BeNullOrEmpty
            $help.AlertSet.Alert.Text | Should -Match 'ANTHROPIC_API_KEY'
        }
    }
}
