# Get all function files from the Public folder and dot-source them
$PublicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public" -Filter "*.ps1" -ErrorAction SilentlyContinue
foreach ($FunctionFile in $PublicFunctions) {
    . $FunctionFile.FullName
}

# Define aliases
Set-Alias -Name 'ipcc' -Value 'Invoke-PSClaudeCode'