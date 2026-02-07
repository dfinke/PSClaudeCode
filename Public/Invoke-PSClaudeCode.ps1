<#
.SYNOPSIS
    Invokes Claude Code, an AI-powered PowerShell agent that can perform tasks using structured tools.

.DESCRIPTION
    Invoke-PSClaudeCode uses configurable LLM providers (Anthropic or OpenAI) to execute tasks by leveraging
    various tools including file reading/writing, command execution, and sub-agent delegation. The function
    supports pipeline input and provides safety checks for potentially dangerous operations.

.PARAMETER Task
    The task description for the AI agent to perform. If not provided and pipeline input exists, the piped content becomes the task.

.PARAMETER InputObject
    Accepts pipeline input that can be used as part of the task description.

.PARAMETER Model
    The model to use. Defaults to "claude-sonnet-4-5-20250929" for Anthropic.

.PARAMETER Provider
    The LLM provider to use. Defaults to "Anthropic". Use "OpenAI" for OpenAI-compatible models.

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
    Requires ANTHROPIC_API_KEY or OPENAI_API_KEY environment variable to be set, depending on Provider.
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
        [ValidateSet("Anthropic", "OpenAI")]
        [string]$Provider = "Anthropic",
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

        function Get-ApiKey {
            param([string]$SelectedProvider)

            switch ($SelectedProvider) {
                "Anthropic" { return $env:ANTHROPIC_API_KEY }
                "OpenAI" { return $env:OPENAI_API_KEY }
                default { return $null }
            }
        }

        function Convert-ToolsForProvider {
            param([string]$SelectedProvider, $ToolDefinitions)

            if ($SelectedProvider -eq "OpenAI") {
                return $ToolDefinitions | ForEach-Object {
                    @{
                        type     = "function"
                        function = @{
                            name        = $_.name
                            description = $_.description
                            parameters  = $_.input_schema
                        }
                    }
                }
            }

            return $ToolDefinitions
        }

        function Convert-OpenAIInput {
            param($MessageHistory)

            $inputs = @()
            foreach ($message in $MessageHistory) {
                $role = $message.role
                $contentValue = $message.content

                if ($contentValue -is [System.Array]) {
                    $contentValue = ($contentValue | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join ""
                }

                if ($role -eq "tool") {
                    $inputMessage = @{
                        role    = $role
                        content = @(@{
                            type         = "tool_result"
                            tool_call_id = $message.tool_call_id
                            output       = "$contentValue"
                        })
                    }
                }
                elseif ($role -eq "assistant") {
                    $inputMessage = @{
                        role    = $role
                        content = @(@{
                            type = "output_text"
                            text = "$contentValue"
                        })
                    }
                }
                else {
                    $inputMessage = @{
                        role    = $role
                        content = @(@{
                            type = "input_text"
                            text = "$contentValue"
                        })
                    }
                }

                $inputs += $inputMessage
            }

            return $inputs
        }

        function Normalize-Response {
            param([string]$SelectedProvider, $Response)

            if ($SelectedProvider -eq "OpenAI") {
                if (-not $Response.output) {
                    return @{ content = @(); rawMessage = $null }
                }

                $contentItems = @()
                $toolCalls = @()

                $outputMessages = $Response.output | Where-Object { $_.type -eq "message" }
                $outputTextItems = $Response.output | Where-Object { $_.type -eq "output_text" }
                $toolCallItems = $Response.output | Where-Object { $_.type -eq "tool_call" }

                foreach ($outputMessage in $outputMessages) {
                    foreach ($content in $outputMessage.content) {
                        if ($content.type -eq "output_text") {
                            $contentItems += @{
                                type = "text"
                                text = $content.text
                            }
                        }
                    }
                }

                foreach ($outputTextItem in $outputTextItems) {
                    $contentItems += @{
                        type = "text"
                        text = $outputTextItem.text
                    }
                }

                foreach ($toolCall in $toolCallItems) {
                    $arguments = $toolCall.arguments
                    $inputObject = if ([string]::IsNullOrWhiteSpace($arguments)) { @{} } else { $arguments | ConvertFrom-Json }
                    $contentItems += @{
                        type  = "tool_use"
                        id    = $toolCall.call_id
                        name  = $toolCall.name
                        input = $inputObject
                    }
                    $toolCalls += @{
                        id       = $toolCall.call_id
                        type     = "function"
                        function = @{
                            name      = $toolCall.name
                            arguments = $arguments
                        }
                    }
                }

                return @{
                    content    = $contentItems
                    rawMessage = @{
                        content    = ($contentItems | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join ""
                        tool_calls = $toolCalls
                    }
                }
            }

            return $Response
        }

        function Invoke-ModelRequest {
            param(
                [string]$SelectedProvider,
                [string]$SelectedModel,
                $MessageHistory,
                $ToolDefinitions,
                [string]$Key
            )

            if ($SelectedProvider -eq "OpenAI") {
                $body = @{
                    model      = $SelectedModel
                    input      = Convert-OpenAIInput -MessageHistory $MessageHistory
                    max_output_tokens = 4096
                    tools      = $ToolDefinitions
                    tool_choice = "auto"
                } | ConvertTo-Json -Depth 10

                try {
                    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/responses" -Method Post -Headers @{
                        "Authorization" = "Bearer $Key"
                        "Content-Type"  = "application/json"
                    } -Body $body -ErrorAction Stop
                }
                catch {
                    return @{ error = $_.Exception.Message }
                }

                return Normalize-Response -SelectedProvider $SelectedProvider -Response $response
            }

            $body = @{
                model      = $SelectedModel
                messages   = $MessageHistory
                max_tokens = 4096
                tools      = $ToolDefinitions
            } | ConvertTo-Json -Depth 10

            try {
                $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers @{
                    "x-api-key"         = $Key
                    "anthropic-version" = "2023-06-01"
                    "Content-Type"      = "application/json"
                } -Body $body -ErrorAction Stop
            }
            catch {
                return @{ error = $_.Exception.Message }
            }

            return $response
        }

        function Append-ToolResults {
            param(
                [string]$SelectedProvider,
                $MessageHistory,
                $ToolResults
            )

            if ($SelectedProvider -eq "OpenAI") {
                foreach ($toolResult in $ToolResults) {
                    $MessageHistory += @{
                        role         = "tool"
                        tool_call_id = $toolResult.id
                        content      = $toolResult.content
                    }
                }
                return $MessageHistory
            }

            $MessageHistory += @{ role = "user"; content = $ToolResults }
            return $MessageHistory
        }

        $apiKey = Get-ApiKey -SelectedProvider $Provider
        if (-not $apiKey) {
            Write-Host "Set ANTHROPIC_API_KEY or OPENAI_API_KEY for provider $Provider"
            exit
        }

        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Processing request with $Provider..."

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
        
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Starting sub-agent for: $SubTask"
            $subMessages = @(@{ role = "user"; content = $SubTask })
            $turns = 0
            $providerTools = Convert-ToolsForProvider -SelectedProvider $Provider -ToolDefinitions $tools
        
            while ($turns -lt $MaxTurns) {
                $turns++
                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]   🤖 Consulting model..."
                $response = Invoke-ModelRequest -SelectedProvider $Provider -SelectedModel $Model -MessageHistory $subMessages -ToolDefinitions $providerTools -Key $apiKey
                
                if ($response.error) {
                    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]   🚫 $($response.error)"
                    return "Sub-agent failed: $($response.error)"
                }

                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]   🤖 Response received, analyzing..."
            
                if ($Provider -eq "OpenAI") {
                    $assistantMessage = @{
                        role       = "assistant"
                        content    = $response.rawMessage.content
                        tool_calls = $response.rawMessage.tool_calls
                    }
                }
                else {
                    $assistantMessage = @{ role = "assistant"; content = $response.content }
                }
                $subMessages += $assistantMessage
            
                $toolUses = $response.content | Where-Object { $_.type -eq "tool_use" }
            
                if ($toolUses) {
                    $toolResults = @()
                    foreach ($toolUse in $toolUses) {
                        $toolName = $toolUse.name
                        $toolInput = $toolUse.input
                    
                        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]   🔧 $toolName`: $($toolInput | ConvertTo-Json -Compress)"
                    
                        if (Check-Permission $toolName $toolInput) {
                            $result = Execute-Tool $toolName $toolInput
                            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]      → $($result.Substring(0, [Math]::Min(100, $result.Length)))..."
                        }
                        else {
                            $result = "Permission denied by user"
                            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]      🚫 $result"
                        }
                    
                        $toolResults += @{
                            id          = $toolUse.id
                            content     = $result
                            type        = "tool_result"
                            tool_use_id = $toolUse.id
                        }
                    }
                    $subMessages = Append-ToolResults -SelectedProvider $Provider -MessageHistory $subMessages -ToolResults $toolResults
                }
                else {
                    $textContent = ($response.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join ""
                    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Sub-agent result: $textContent"
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

        $providerTools = Convert-ToolsForProvider -SelectedProvider $Provider -ToolDefinitions $tools

        while ($true) {
            if ($messages.Count -gt 1) {
                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Continuing analysis..."
            }
            
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Consulting model..."
            $response = Invoke-ModelRequest -SelectedProvider $Provider -SelectedModel $Model -MessageHistory $messages -ToolDefinitions $providerTools -Key $apiKey
            
            if ($response.error) {
                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🚫 $($response.error)"
                break
            }

            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Response received, analyzing..."

            if ($Provider -eq "OpenAI") {
                $assistantMessage = @{
                    role       = "assistant"
                    content    = $response.rawMessage.content
                    tool_calls = $response.rawMessage.tool_calls
                }
            }
            else {
                $assistantMessage = @{ role = "assistant"; content = $response.content }
            }
            $messages += $assistantMessage

            $toolUses = $response.content | Where-Object { $_.type -eq "tool_use" }
        
            if ($toolUses) {
                $toolResults = @()
                foreach ($toolUse in $toolUses) {
                    $toolName = $toolUse.name
                    $toolInput = $toolUse.input
                
                    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🔧 $toolName`: $($toolInput | ConvertTo-Json -Compress)"
                
                    if (Check-Permission $toolName $toolInput) {
                        $result = Execute-Tool $toolName $toolInput
                        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]    → $($result.Substring(0, [Math]::Min(200, $result.Length)))..."
                    }
                    else {
                        $result = "Permission denied by user"
                        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]    🚫 $result"
                    }
                
                    $toolResults += @{
                        id          = $toolUse.id
                        content     = $result
                        type        = "tool_result"
                        tool_use_id = $toolUse.id
                    }
                }
                $messages = Append-ToolResults -SelectedProvider $Provider -MessageHistory $messages -ToolResults $toolResults
            }
            else {
                $textContent = ($response.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join ""
                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] ✅ $textContent"
                break
            }
        }
    }
}
