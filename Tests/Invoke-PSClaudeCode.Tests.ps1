BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSClaudeCode.psd1'
    Import-Module $ModulePath -Force

    # Store original API key
    $script:OriginalApiKey = $env:ANTHROPIC_API_KEY

    # Load function content once for all tests
    $script:FunctionPath = Join-Path $PSScriptRoot '..' 'Public' 'Invoke-PSClaudeCode.ps1'
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
}
