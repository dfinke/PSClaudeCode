# agent-v3-anthropic.ps1 - Agent with structured tools and subagents using Anthropic
# agent-v3-anthropic.ps1 "Create a new file called 'test.txt' with the content 'Hello, World!', then read it back and display the contents."
function Invoke-PSClaudeCode {
    param(
        [string]$Task,
        [string]$Model = "claude-sonnet-4-5-20250929",
        [switch]$dangerouslySkipPermissions
    )

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