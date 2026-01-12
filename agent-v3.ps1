# agent-v3.ps1 - Agent with structured tools and subagents
# agent-v3.ps1 "Create a new file called 'test.txt' with the content 'Hello, World!', then read it back and display the contents."

<#
agent-v3.ps1 @"
Design and implement a KQL-based anomaly detection system for Azure Application Insights telemetry data. The system should:
1. Explore and analyze sample telemetry data to identify key metrics (e.g., response times, error rates, user sessions).
2. Build modular KQL queries for real-time anomaly detection using statistical methods (e.g., z-score, moving averages).
3. Create alerts and dashboards in Azure Monitor/Log Analytics.
4. Optimize queries for performance and cost-efficiency.
5. Generate a PowerShell script to automate deployment and testing of the KQL queries.

Delegate each major step (data exploration, query building, optimization, and scripting) to sub-agents with focused contexts. Ensure sub-agents iterate on feedback and return only final, validated results.
"@
#>

param(
    [string]$Task
)

$apiKey = $env:OPENAI_API_KEY
if (-not $apiKey) { Write-Host "Set OPENAI_API_KEY"; exit }

$tools = @(
    @{
        type     = "function"
        function = @{
            name        = "Read-File"
            description = "Read the contents of a file"
            parameters  = @{
                type       = "object"
                properties = @{
                    path = @{ type = "string"; description = "Path to the file" }
                }
                required   = @("path")
            }
        }
    }
    @{
        type     = "function"
        function = @{
            name        = "Write-File"
            description = "Write content to a file"
            parameters  = @{
                type       = "object"
                properties = @{
                    path    = @{ type = "string"; description = "Path to the file" }
                    content = @{ type = "string"; description = "Content to write" }
                }
                required   = @("path", "content")
            }
        }
    }
    @{
        type     = "function"
        function = @{
            name        = "Run-Command"
            description = "Run a PowerShell command"
            parameters  = @{
                type       = "object"
                properties = @{
                    command = @{ type = "string"; description = "The command to run" }
                }
                required   = @("command")
            }
        }
    }
    @{
        type     = "function"
        function = @{
            name        = "Delegate-Task"
            description = "Delegate a focused task to a sub-agent with limited context"
            parameters  = @{
                type       = "object"
                properties = @{
                    task     = @{ type = "string"; description = "The task to delegate" }
                    maxTurns = @{ type = "integer"; description = "Maximum turns for the sub-agent (default 10)" }
                }
                required   = @("task")
            }
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
            model       = "gpt-4.1"
            messages    = $subMessages
            max_tokens  = 4096
            tools       = $tools
            tool_choice = "auto"
        } | ConvertTo-Json -Depth 10
        
        $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers @{
            "Authorization" = "Bearer $apiKey"
            "Content-Type"  = "application/json"
        } -Body $body
        
        $message = $response.choices[0].message
        $subMessages += $message
        
        if ($message.tool_calls) {
            $toolResults = @()
            foreach ($toolCall in $message.tool_calls) {
                $toolName = $toolCall.function.name
                $toolInput = $toolCall.function.arguments | ConvertFrom-Json
                
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
                    tool_call_id = $toolCall.id
                    role         = "tool"
                    content      = $result
                }
            }
            $subMessages += $toolResults
        }
        else {
            Write-Host "🤖 Sub-agent result: $($message.content)"
            return $message.content
        }
    }
    return "Sub-agent reached max turns without completion."
}

function Check-Permission {
    param([string]$ToolName, $ToolInput)
    
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
        model       = "gpt-4.1"
        messages    = $messages
        max_tokens  = 4096
        tools       = $tools
        tool_choice = "auto"
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type"  = "application/json"
    } -Body $body

    $message = $response.choices[0].message
    $messages += $message

    if ($message.tool_calls) {
        $toolResults = @()
        foreach ($toolCall in $message.tool_calls) {
            $toolName = $toolCall.function.name
            $toolInput = $toolCall.function.arguments | ConvertFrom-Json
            
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
                tool_call_id = $toolCall.id
                role         = "tool"
                content      = $result
            }
        }
        $messages += $toolResults
    }
    else {
        Write-Host "✅ $($message.content)"
        break
    }
}