
function Invoke-PSClaudeCodeWithLog {
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
        $logDir = Join-Path $PWD "Conversations"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
        $logFile = Join-Path $logDir "Conversation-$((Get-Date).ToString('yyyy-MM-dd')).md"
    }
    process {
        if ($PSBoundParameters.ContainsKey("InputObject") -and $null -ne $InputObject) {
            $pipelineBuffer += ($InputObject | Out-String)
        }
    }
    end {
        if (-not $Task -and $pipelineBuffer) {
            $Task = $pipelineBuffer.TrimEnd("`r", "`n")
        }
        elseif ($Task -and $pipelineBuffer) {
            $Task = "$Task`n`n--- Begin piped input ---`n$($pipelineBuffer.TrimEnd("`r","`n"))`n--- End piped input ---"
        }

        function Log-Message {
            param([string]$Content)
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Add-Content -Path $logFile -Value $Content
        }

        # Start Log Entry
        Log-Message "`n## Task: $Task`n"

        $apiKey = $env:ANTHROPIC_API_KEY
        if (-not $apiKey) { Write-Host "Set ANTHROPIC_API_KEY"; exit }

        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Processing request..."

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
            }
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
            if ($messages.Count -gt 1) {
                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Continuing analysis..."
            }
            
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Consulting Claude..."
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
            
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🤖 Response received, analyzing..."

            $assistantMessage = @{ role = "assistant"; content = $response.content }
            $messages += $assistantMessage

            $toolUses = $response.content | Where-Object { $_.type -eq "tool_use" }
        
            if ($toolUses) {
                $toolResults = @()
                foreach ($toolUse in $toolUses) {
                    $toolName = $toolUse.name
                    $toolInput = $toolUse.input
                
                    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🔧 $toolName`: $($toolInput | ConvertTo-Json -Compress)"
                    Log-Message "- **Tool Call**: `$toolName`"
                    Log-Message "  ```json`n  $($toolInput | ConvertTo-Json -Depth 5)`n  ```"

                    if (Check-Permission $toolName $toolInput) {
                        $result = Execute-Tool $toolName $toolInput
                        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]    → $($result.Substring(0, [Math]::Min(200, $result.Length)))..."
                    }
                    else {
                        $result = "Permission denied by user"
                        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]    🚫 $result"
                    }

                    Log-Message "  > Result: $($result.Substring(0, [Math]::Min(200, $result.Length)))..."
                
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
                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] ✅ $textContent"
                Log-Message "`n### Response`n$textContent`n"
                break
            }
        }
    }
}
