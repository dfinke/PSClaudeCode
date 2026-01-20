<p align="center">
  <img src="reference/PowerShell-Claude-Code.png" alt="alt text" width="450">
</p>

<p align="center">
  <a href="https://x.com/dfinke">
    <img src="https://img.shields.io/twitter/follow/dfinke.svg?style=social&label=Follow%20%40dfinke"></a>
  <a href="https://youtube.com/@dougfinke">
    <img src="https://img.shields.io/youtube/channel/subscribers/UCP47ZkO5EDkoI2sr-3P4ShQ"></a>
</p>
<br/>
<br/>

# PSClaudeCode

Ever wondered how AI agents like Claude Code work their magic? Dive into this PowerShell implementation and build your own intelligent assistant from scratch!

Inspired by the original [Claude Code article](https://x.com/dabit3/status/2009668398691582315?s=20), this project demonstrates how to create a PowerShell AI agent using Anthropic's Claude API. Start with a simple command runner and evolve it into a sophisticated agent with function calling, file operations, and conversational capabilities.

## Table of Contents
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Examples](#examples)
- [Agent Evolution](#agent-evolution)
- [Contributing](#contributing)
- [License](#license)

## Features
- **PowerShell Module**: Properly structured module with `Invoke-PSClaudeCode` cmdlet
- **Agent Loop**: Iterative task completion with AI-driven decision making
- **Structured Tools**: Function calling for file operations (read/write) and command execution
- **Permission Checks**: Safe operations with user confirmation for dangerous actions
- **Model Selection**: Configurable Claude model selection via parameters
- **Sub-agent Support**: Delegates complex tasks to specialized sub-agents
- **PowerShell Native**: Built entirely in PowerShell, compatible with Anthropic Claude API
- **Progressive Complexity**: Three agent versions showing evolution from simple to advanced

## Prerequisites
- PowerShell 5.1 or higher
- Anthropic API key (set as environment variable `$env:ANTHROPIC_API_KEY`)

## Installation
1. Clone the repository:
   ```powershell
   git clone https://github.com/dfinke/PSClaudeCode.git
   cd PSClaudeCode
   ```

2. Set your Anthropic API key:
   ```powershell
   $env:ANTHROPIC_API_KEY = "your-api-key-here"
   ```

3. Import the module:
   ```powershell
   Import-Module .\PSClaudeCode.psd1
   ```

   Or install it permanently:
   ```powershell
   # Copy to PowerShell modules directory
   $modulePath = "$env:USERPROFILE\Documents\PowerShell\Modules\PSClaudeCode"
   New-Item -ItemType Directory -Path $modulePath -Force
   Copy-Item -Path "PSClaudeCode.psd1" -Destination $modulePath
   Copy-Item -Path "PSClaudeCode.psm1" -Destination $modulePath
   Copy-Item -Path "Public\*" -Destination $modulePath -Recurse
   Import-Module PSClaudeCode
   ```

## Usage
After importing the module, use the `Invoke-PSClaudeCode` cmdlet:

```powershell
Invoke-PSClaudeCode -Task "List all PowerShell files in this directory"
```

### Parameters
- **`-Task`**: The task description for the AI agent to complete (required)
- **`-Model`**: The Claude model to use (optional, defaults to "claude-sonnet-4-5-20250929")

### Examples
```powershell
# Basic usage with default model
Invoke-PSClaudeCode -Task "Create a new file called 'test.txt' with 'Hello, World!'"

# Specify a different model
Invoke-PSClaudeCode -Task "List all files in the current directory" -Model "claude-3-5-sonnet-20241022"
```

The repository also includes three standalone agent script implementations of increasing complexity (these use OpenAI API for reference):

- `agent-v0.ps1`: Simple single-command agent (uses OpenAI)
- `agent-v1.ps1`: Looping agent with JSON-based responses (uses OpenAI)
- `agent-v2.ps1`: Advanced agent with structured tools and function calling (uses OpenAI)

Run any agent script directly:
```powershell
.\agent-v0.ps1 "List all PowerShell files in this directory"
```

## Examples

### Basic File Operations
```powershell
Invoke-PSClaudeCode -Task "Create a new file called 'test.txt' with the content 'Hello, World!', then read it back and display the contents."
```

### Command Execution with Safety Checks
```powershell
Invoke-PSClaudeCode -Task "List all files in the current directory and count how many there are"
# Agent will request permission for any potentially dangerous commands
```

### Using Different Models
```powershell
# Use Claude 3.5 Sonnet
Invoke-PSClaudeCode -Task "Analyze the PowerShell scripts in this directory" -Model "claude-3-5-sonnet-20241022"

# Use the latest Claude Sonnet (default)
Invoke-PSClaudeCode -Task "Create a summary of all .md files in the repository"
```

### Legacy Script Examples
The standalone agent scripts are still available for reference:

#### Agent v0 - Simple Command Runner
```powershell
.\agent-v0.ps1 "list all PowerShell files in this directory"
# AI suggests: Get-ChildItem *.ps1
# Run this command? (y/n)
```

#### Agent v1 - Looping Agent
```powershell
.\agent-v1.ps1 "List all files in the current directory and count how many there are"
# Agent will run commands iteratively until task is complete
```

#### Agent v2 - Function Calling Agent
```powershell
.\agent-v2.ps1 "Create a new file called 'test.txt' with the content 'Hello, World!', then read it back and display the contents."
# Agent uses structured tools for file operations and command execution
```

## Agent Evolution
Check out the [step-by-step guide](reference/2026-01-10-Building-PowerShell-AI-Agent-From-Scratch-to-Claude-Code.md) to understand the evolution from basic to advanced agent implementations.

## Contributing
Contributions are welcome! Please feel free to submit a Pull Request.

## Be Sure to Check out

- [dfinke/psai](https://github.com/dfinke/psai): PSAI brings the power of autonomous agents to PowerShell, allowing you to seamlessly integrate AI capabilities into your scripts and terminal workflows.
- [dfinke/psaisuite](https://github.com/dfinke/psaisuite): Simple, unified interface to multiple Generative AI providers including OpenAI, Anthropic, and others. PSAISuite makes it easy for developers to use multiple LLMs through a standardized interface.

## License
This project is licensed under the MIT License - see the LICENSE file for details.
