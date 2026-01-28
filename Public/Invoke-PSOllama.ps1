
function Invoke-PSOllama {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Task,
        [Parameter(ValueFromPipeline = $true)]
        [object]$InputObject,
        [string]$Model = "llama3.2:latest",
        [string]$Endpoint = "http://192.168.12.176:11434/v1/chat/completions",
        [switch]$dangerouslySkipPermissions
    )

    begin {
        $pipelineBuffer = ""
        $logDir = Join-Path $PWD "Conversations"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
        $logFile = Join-Path $logDir "Conversation-Ollama-$((Get-Date).ToString('yyyy-MM-dd')).md"
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

        Log-Message "`n## Task (Ollama): $Task`n"

        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🦙 Processing request..."

        # Tools in OpenAI Format
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
                    description = "Delegate a focused task to a sub-agent"
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
        
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🦙 Starting sub-agent for: $SubTask"
            $subMessages = @(@{ role = "user"; content = $SubTask })
            $turns = 0
            
            while ($turns -lt $MaxTurns) {
                $turns++
                $body = @{
                    model       = $Model
                    messages    = $subMessages
                    tools       = $tools
                    tool_choice = "auto"
                } | ConvertTo-Json -Depth 10

                try {
                    $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers @{ "Content-Type" = "application/json" } -Body $body
                }
                catch {
                    return "Error calling Ollama: $_"
                }
                
                $message = $response.choices[0].message
                $subMessages += $message

                if ($message.tool_calls) {
                    $toolResults = @()
                    foreach ($toolCall in $message.tool_calls) {
                        $toolName = $toolCall.function.name
                        $toolInput = $toolCall.function.arguments | ConvertFrom-Json
                        
                        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))]   🔧 $toolName"
                        
                        if (Check-Permission $toolName $toolInput) {
                            $result = Execute-Tool $toolName $toolInput
                        }
                        else {
                            $result = "Permission denied by user"
                        }
                        
                        $toolResults += @{
                            tool_call_id = $toolCall.id
                            role         = "tool"
                            name         = $toolName
                            content      = $result
                        }
                    }
                    $subMessages += $toolResults
                }
                else {
                    return $message.content
                }
            }
            return "Sub-agent reached max turns."
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
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] 🦙 Consulting Ollama ($Model)..."
            
            $body = @{
                model       = $Model
                messages    = $messages
                tools       = $tools
                tool_choice = "auto"
            } | ConvertTo-Json -Depth 10

            try {
                $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers @{ "Content-Type" = "application/json" } -Body $body
            }
            catch {
                Write-Host "❌ Error connecting to Ollama at $Endpoint. Is it running?" -ForegroundColor Red
                Log-Message "Error: $_"
                break
            }

            $message = $response.choices[0].message
            $messages += $message

            if ($message.tool_calls) {
                # OpenAI standard: tool_calls is an array
                $toolResults = @()
                foreach ($toolCall in $message.tool_calls) {
                    $toolName = $toolCall.function.name
                    # Parse arguments: sometimes string, sometimes object depending on provider quirks, usually JSON string
                    $toolInput = $toolCall.function.arguments 
                    if ($toolInput -is [string]) {
                        try { $toolInput = $toolInput | ConvertFrom-Json } catch { }
                    }

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
                        tool_call_id = $toolCall.id
                        role         = "tool"
                        name         = $toolName
                        content      = $result
                    }
                }
                $messages += $toolResults
            }
            else {
                $content = $message.content
                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] ✅ $content"
                Log-Message "`n### Response`n$content`n"
                break
            }
        }
    }
}
