<#
.SYNOPSIS
    Invokes Claude Code, an AI-powered PowerShell agent that can perform tasks using structured tools.

.DESCRIPTION
    Invoke-PSClaudeCode uses Anthropic's Claude AI model to execute tasks by leveraging various tools including
    file reading/writing, command execution, and sub-agent delegation. The function supports pipeline input
    and provides safety checks for potentially dangerous operations.

.PARAMETER Task
    The task description for the AI agent to perform. If not provided and pipeline input exists, the piped content becomes the task.

.PARAMETER InputObject
    Accepts pipeline input that can be used as part of the task description.

.PARAMETER Model
    The Claude model to use. Defaults to "claude-sonnet-4-5-20250929".

.PARAMETER dangerouslySkipPermissions
    Switch to skip permission prompts for potentially dangerous operations. Use with caution.

.EXAMPLE
    PS> Invoke-PSClaudeCode "Create a new file called 'test.txt' with the content 'Hello, World!'"

    This example instructs the AI agent to create a file with specific content.

.EXAMPLE
    PS> Get-Content "data.txt" | Invoke-PSClaudeCode "Analyze this data and create a summary report"

    This example pipes file content to the function for analysis.

.EXAMPLE
    PS> Invoke-PSClaudeCode -Task "List all files in the current directory" -dangerouslySkipPermissions

    This example runs a command without permission prompts.

.NOTES
    Requires ANTHROPIC_API_KEY environment variable to be set.
    The function includes safety checks for file operations and command execution.
#>
function Invoke-PSClaudeCode {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Task,
        [Parameter(ValueFromPipeline = $true)]
        [object]$InputObject,
        [string]$Model = "claude-sonnet-4-5-20250929",
        [switch]$dangerouslySkipPermissions
    )

    begin {
        $pipelineBuffer = ""
    }
    process {
        if ($PSBoundParameters.ContainsKey("InputObject") -and $null -ne $InputObject) {
            $pipelineBuffer += ($InputObject | Out-String)
        }
    }
    end {
        # If the caller piped content but didn't provide a Task, use the piped content as the Task.
        if (-not $Task -and $pipelineBuffer) {
            $Task = $pipelineBuffer.TrimEnd("`r", "`n")
        }
        elseif ($Task -and $pipelineBuffer) {
            # Merge the task and piped content with clear separators so the model sees both.
            $Task = "$Task`n`n--- Begin piped input ---`n$($pipelineBuffer.TrimEnd("`r","`n"))`n--- End piped input ---"
        }

        # proceed with the rest of the function using the possibly-updated $Task

        $apiKey = $env:ANTHROPIC_API_KEY
        if (-not $apiKey) { Write-Host "Set ANTHROPIC_API_KEY"; exit }

        $tools = @(
            @{
                name         = "Read-File"
                description  = "Read the contents of a file"
                input_schema = @{
                    type       = "object"
                    properties = @{
                        path = @{ type = "string"; description = "Path to the file" }
                    }
                    required   = @("path")
                }
            }
            @{
                name         = "Write-File"
                description  = "Write content to a file"
                input_schema = @{
                    type       = "object"
                    properties = @{
                        path    = @{ type = "string"; description = "Path to the file" }
                        content = @{ type = "string"; description = "Content to write" }
                    }
                    required   = @("path", "content")
                }
            }
            @{
                name         = "Run-Command"
                description  = "Run a PowerShell command"
                input_schema = @{
                    type       = "object"
                    properties = @{
                        command = @{ type = "string"; description = "The command to run" }
                    }
                    required   = @("command")
                }
            }
            @{
                name         = "Delegate-Task"
                description  = "Delegate a focused task to a sub-agent with limited context"
                input_schema = @{
                    type       = "object"
                    properties = @{
                        task     = @{ type = "string"; description = "The task to delegate" }
                        maxTurns = @{ type = "integer"; description = "Maximum turns for the sub-agent (default 10)" }
                    }
                    required   = @("task")
                }
            }
        )

        function Execute-Tool {
            param([string]$Name, $ToolInput)
        
            switch ($Name) {
                "Read-File" {
                    try {
                        $content = Get-Content $ToolInput.path -Raw
                        return "Contents of $($ToolInput.path):`n$content"
                    }
                    catch {
                        return "Error: $_"
                    }
                }
                "Write-File" {
                    try {
                        Set-Content $ToolInput.path $ToolInput.content
                        return "Successfully wrote to $($ToolInput.path)"
                    }
                    catch {
                        return "Error: $_"
                    }
                }
                "Run-Command" {
                    try {
                        $output = Invoke-Expression $ToolInput.command 2>&1 | Out-String
                        return "`$ $($ToolInput.command)`n$output"
                    }
                    catch {
                        return "Error: $_"
                    }
                }
                "Delegate-Task" {
                    $subTask = $ToolInput.task
                    $maxTurns = if ($ToolInput.maxTurns) { $ToolInput.maxTurns } else { 10 }
                    return Run-SubAgent $subTask $maxTurns
                }
                default { return "Unknown tool: $Name" }
            }
        }

        function Run-SubAgent {
            param([string]$SubTask, [int]$MaxTurns = 10)
        
            Write-Host "🤖 Starting sub-agent for: $SubTask"
            $subMessages = @(@{ role = "user"; content = $SubTask })
            $turns = 0
        
            while ($turns -lt $MaxTurns) {
                $turns++
                $body = @{
                    model      = $Model
                    messages   = $subMessages
                    max_tokens = 4096
                    tools      = $tools
                } | ConvertTo-Json -Depth 10
            
                $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers @{
                    "x-api-key"         = $apiKey
                    "anthropic-version" = "2023-06-01"
                    "Content-Type"      = "application/json"
                } -Body $body
            
                $assistantMessage = @{ role = "assistant"; content = $response.content }
                $subMessages += $assistantMessage
            
                $toolUses = $response.content | Where-Object { $_.type -eq "tool_use" }
            
                if ($toolUses) {
                    $toolResults = @()
                    foreach ($toolUse in $toolUses) {
                        $toolName = $toolUse.name
                        $toolInput = $toolUse.input
                    
                        Write-Host "  🔧 $toolName`: $($toolInput | ConvertTo-Json -Compress)"
                    
                        if (Check-Permission $toolName $toolInput) {
                            $result = Execute-Tool $toolName $toolInput
                            Write-Host "     → $($result.Substring(0, [Math]::Min(100, $result.Length)))..."
                        }
                        else {
                            $result = "Permission denied by user"
                            Write-Host "     🚫 $result"
                        }
                    
                        $toolResults += @{
                            type        = "tool_result"
                            tool_use_id = $toolUse.id
                            content     = $result
                        }
                    }
                    $userMessage = @{ role = "user"; content = $toolResults }
                    $subMessages += $userMessage
                }
                else {
                    $textContent = ($response.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join ""
                    Write-Host "🤖 Sub-agent result: $textContent"
                    return $textContent
                }
            }
            return "Sub-agent reached max turns without completion."
        }

        function Check-Permission {
            param([string]$ToolName, $ToolInput)
        
            if ($dangerouslySkipPermissions) { return $true }
        
            if ($ToolName -eq "Run-Command") {
                $cmd = $ToolInput.command
                if ($cmd -match "rm|del|Remove-Item|rmdir|rd|Set-Content.*>.*|.*\|.*iex") {
                    Write-Host "⚠️ Potentially dangerous command: $cmd"
                    $response = Read-Host "Allow? (y/n)"
                    return $response -eq "y"
                }
            }
            elseif ($ToolName -eq "Write-File") {
                Write-Host "📝 Will write to: $($ToolInput.path)"
                $response = Read-Host "Allow? (y/n)"
                return $response -eq "y"
            }
            return $true
        }

        $messages = @(@{ role = "user"; content = $Task })

        while ($true) {
            $body = @{
                model      = $Model
                messages   = $messages
                max_tokens = 4096
                tools      = $tools
            } | ConvertTo-Json -Depth 10

            $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers @{
                "x-api-key"         = $apiKey
                "anthropic-version" = "2023-06-01"
                "Content-Type"      = "application/json"
            } -Body $body

            $assistantMessage = @{ role = "assistant"; content = $response.content }
            $messages += $assistantMessage

            $toolUses = $response.content | Where-Object { $_.type -eq "tool_use" }
        
            if ($toolUses) {
                $toolResults = @()
                foreach ($toolUse in $toolUses) {
                    $toolName = $toolUse.name
                    $toolInput = $toolUse.input
                
                    Write-Host "🔧 $toolName`: $($toolInput | ConvertTo-Json -Compress)"
                
                    if (Check-Permission $toolName $toolInput) {
                        $result = Execute-Tool $toolName $toolInput
                        Write-Host "   → $($result.Substring(0, [Math]::Min(200, $result.Length)))..."
                    }
                    else {
                        $result = "Permission denied by user"
                        Write-Host "   🚫 $result"
                    }
                
                    $toolResults += @{
                        type        = "tool_result"
                        tool_use_id = $toolUse.id
                        content     = $result
                    }
                }
                $userMessage = @{ role = "user"; content = $toolResults }
                $messages += $userMessage
            }
            else {
                $textContent = ($response.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join ""
                Write-Host "✅ $textContent"
                break
            }
        }
    }
}