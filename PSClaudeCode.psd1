@{
    ModuleVersion     = '1.1.0'
    GUID              = '36c95bb7-6763-4c71-9d48-feffa33efc5c'  
    Author            = 'Doug Finke'
    CompanyName       = 'Doug Finke'
    Copyright         = '(c) 2026 Douglas Finke. All rights reserved.'
    Description       = 'A PowerShell module for building Claude Code using Anthropic, with reference implementations for tool-based interactions.'
    PowerShellVersion = '5.1'
    RootModule        = 'PSClaudeCode.psm1'
    FunctionsToExport = @('Invoke-PSClaudeCode')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('ipcc')
    PrivateData       = @{
        PSData = @{
            Tags         = @('AI', 'Agent', 'Anthropic', 'Claude', 'PowerShell', 'Automation')
            LicenseUri   = 'https://github.com/dfinke/PSClaudeCode/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/dfinke/PSClaudeCode'
            ReleaseNotes = 'Initial release with Invoke-PSClaudeCode cmdlet.'
        }
    }
}