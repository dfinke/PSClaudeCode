@{
    ModuleVersion     = '1.0.0'
    GUID              = '36c95bb7-6763-4c71-9d48-feffa33efc5c'  
    Author            = 'Doug Finke'
    CompanyName       = 'Doug Finke'
    Copyright         = '(c) 2026 Douglas Finke. All rights reserved.'
    Description       = 'A PowerShell module for building AI agents using OpenAI API, with reference implementations for tool-based interactions.'
    PowerShellVersion = '5.1'
    ModuleToProcess   = 'PSClaudeCode.psm1'
    FunctionsToExport = @('Invoke-PSClaudeCodeAgent')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('AI', 'Agent', 'OpenAI', 'PowerShell', 'Automation')
            LicenseUri   = 'https://github.com/dfinke/PSClaudeCode/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/dfinke/PSClaudeCode'
            ReleaseNotes = 'Initial release with Invoke-PSClaudeCodeAgent cmdlet.'
        }
    }
}