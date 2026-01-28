# PSClaudeCode: The Comprehensive Guide

## 1. Analysis & Overview
**PSClaudeCode** is a PowerShell module that brings the power of **Autonomous AI Agents** directly into your terminal. It effectively recreates the experience of tools like "Claude Code" but built entirely natively in PowerShell.

### Architecture Overview
At its core, the agent operates on a **Loop-Thought-Action** cycle:
1.  **Think**: It sends your task + current context to the AI model (Anthropic Claude).
2.  **Decide**: The AI decides if it needs to use a **Tool** (like `Read-File` or `Run-Command`) or if it's done.
3.  **Act**: If a tool is chosen, the script creates a sandbox, checks permissions (for safety), executes the tool, and captures the output.
4.  **Loop**: The output is fed back to the AI as "context", and the loop repeats until the task is complete.

### Key Components
-   **`Invoke-PSClaudeCode` (Alias `ipcc`)**: The main driver. It handles the API communication, tool execution, and state management.
-   **`agent-v0` to `agent-v2`**: These are educational snapshots showing how the agent was built from scratch.
    -   *v0*: Simple command runner.
    -   *v1*: Adds a loop for multi-step tasks.
    -   *v2*: Adds structured "Function Calling" for reliability.
-   **Tools**:
    -   `Read-File` / `Write-File`: For file system manipulation.
    -   `Run-Command`: To execute *any* PowerShell command (the agent's "hands").
    -   `Delegate-Task`: A powerful feature allowing the agent to spawn *sub-agents* to handle complex sub-tasks without cluttering its main context.

---

## 2. Setting Up Your Environment
Before you can run the agent, you need to prepare your environment.

### Prerequisites
1.  **PowerShell 5.1+** (You are on macOS, so you likely have PowerShell Core 7+, which is perfect).
2.  **Anthropic API Key**: You need a key from [console.anthropic.com](https://console.anthropic.com/).

### Installation
1.  **Clone the Repo** (You are already here):
    ```powershell
    cd /Users/ifiokmoses/code/PSClaudeCode
    ```
2.  **Set your API Key**:
    ```powershell
    $env:ANTHROPIC_API_KEY = "sk-ant-..." # Replace with your actual key
    ```
    *Tip: Add this to your `$PROFILE` to verify it persists.*

3.  **Import the Module**:
    ```powershell
    Import-Module ./PSClaudeCode.psd1
    ```

---

## 3. Step-by-Step Tutorial: The Evolution of an Agent
To truly understand this repo, let's walk through how it "grew up". This will demystify the "AI Magic".

### Level 1: The Command Runner (`agent-v0.ps1`)
*Concept: "Just tell me what command to run."*
This script simply takes your English request, sends it to OpenAI (original versions used OpenAI), and asks for a PowerShell command back.
-   **Try it**: `.\agent-v0.ps1 "List all PDF files in my downloads"`
-   **Limitation**: It can't read the output. It assumes the command worked. It can't do two things in a row.

### Level 2: The Loop (`agent-v1.ps1`)
*Concept: "Keep trying until you're done."*
This version introduces a `while($true)` loop. The AI can now say "I am done" or "Run this command".
-   **Scenario**: "Find the largest file and copy it to a backup folder."
-   **Flow**:
    1.  AI: `ls | sort length -desc | select -first 1`
    2.  Script: Runs it, sends output back. "File is 'video.mp4'".
    3.  AI: `cp video.mp4 ./backup/`
    4.  Script: Runs it.
    5.  AI: "Done."
-   **Limitation**: It relies on parsing text ("Action: powershell"). If the AI makes a typo in the format, it breaks.

### Level 3: The Professional (`Invoke-PSClaudeCode`)
*Concept: "Structured Tools & Delegation."*
This is the final `ipcc` command. It switches to **Anthropic Claude**, which is excellent at coding. It uses **Native Function Calling**, meaning the API strictly enforces how tools are used (no more parsing errors).
-   **Key Feature**: **Sub-Agents**.
    -   If you ask: "Refactor this entire project," the agent might spawn a sub-agent for *each file*. This keeps the main conversation clean and focused.

---

## 4. Real-World Use Cases
Now that you have the power, here is how to use it creatively.

### Use Case 1: The "Log Sentinel" 🛡️
*Goal: Analyze messy logs without writing regex.*
Instead of writing complex grep/regex patterns, pipe the log file directly to the agent.
```powershell
# Analyze standard system logs for "Error" patterns and summary
Get-Content -Tail 100 /var/log/system.log | ipcc "Analyze these recent logs. Group similar errors together and suggest a fix for the most frequent one."
```
**Why it works**: The agent reads the piped input as "context" and then uses its internal knowledge base to diagnose the error strings.

### Use Case 2: The "Code Janitor" 🧹
*Goal: Mass-update legacy code conventions.*
You have 50 scripts that need a specific comment header or a parameter name change.
```powershell
# Find all scripts, valid them, and ask the agent to update them
Get-ChildItem -Path ./src -Filter *.ps1 | ForEach-Object {
    ipcc "Review $($_.FullName). If it is missing a .SYNOPSIS help block, add one based on the code content. Write the file back."
}
```
**Why it works**: You are automating the automation. The agent opens the file, understands usage, writes the specific help block, and saves it.

### Use Case 3: The "On-Call Detective" 🕵️‍♂️
*Goal: Debugging a live issue.*
You are exploring a system and don't know where the config files are.
```powershell
ipcc "I need to find valid Nginx configurations on this mac, checking common locations. Once found, print the server_name."
```
**Why it works**: The agent will autonomously:
1.  `ls /usr/local/etc/nginx` (Fail? Try next)
2.  `ls /opt/homebrew/etc/nginx` (Success!)
3.  `Read-File nginx.conf`
4.  Extract and print `server_name`.
It handles the "Search" logic for you.

### Use Case 4: The "Git Assistant" 🐙
*Goal: Generate meaningful commit messages.*
```powershell
# Stage your changes first
git add .
# Ask agent to explain diffs and commit
git diff --staged | ipcc "Write a conventional commit message for these changes. If it looks good, run the git commit command."
```

## 5. Safety First ⚠️
The agent has a `Run-Command` tool. This is powerful but dangerous.
-   **Default Mode**: The agent **will ask permission** before running commands like `Remove-Item` or `Set-Content` (writing files).
-   **`-dangerouslySkipPermissions`**: Use this ONLY in sandboxed environments (like a Docker container) or when you trust the task completely (e.g., "Read this file").

## Quick Reference
| Command                          | Description                               |
| :------------------------------- | :---------------------------------------- |
| `ipcc "Task"`                    | Run a generic task.                       |
| `ipcc -Model "claude-3-opus..."` | Use a smarter (but more expensive) model. |

## 6. Local AI with Ollama 🦙
You can now run the agent **completely free and locally** using `Invoke-PSOllama`.

### Prerequisites
1.  **Ollama**: Installed and running (locally or on a network server).
2.  **Model**: `llama3.2` or similar (run `ollama pull llama3.2`).

### Usage
```powershell
# Load the function
. ./Public/Invoke-PSOllama.ps1

# Run with default (localhost)
Invoke-PSOllama "Tell me a joke"

# Run with a specific model
Invoke-PSOllama "Analyze this file" -Model "mistral"

# Run against a remote server
Invoke-PSOllama "Task..." -Endpoint "http://192.168.1.50:11434/v1/chat/completions"
```

### Features
*   **Logging**: Automatically saves all chats to `Conversations/Conversation-Ollama-DATE.md`.
*   **API Compatibility**: Uses the OpenAI-compatible API endpoint provided by Ollama.

