# PSClaudeCode

<p align="center">
  <a href="https://x.com/dfinke">
    <img src="https://img.shields.io/twitter/follow/dfinke.svg?style=social&label=Follow%20%40dfinke"></a>
  <a href="https://youtube.com/@dougfinke">
    <img src="https://img.shields.io/youtube/channel/subscribers/UCP47ZkO5EDkoI2sr-3P4ShQ"></a>
</p>

Ever wondered how AI agents like Claude Code work their magic? Dive into this PowerShell implementation and build your own intelligent assistant from scratch!

Inspired by the original [Claude Code article](https://x.com/dabit3/status/2009668398691582315?s=20), this project demonstrates how to create a PowerShell AI agent using OpenAI's API. Start with a simple command runner and evolve it into a sophisticated agent with function calling, file operations, and conversational capabilities.

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
- **Agent Loop**: Iterative task completion with AI-driven decision making
- **Structured Tools**: Function calling for file operations (read/write) and command execution
- **Permission Checks**: Safe operations with user confirmation for dangerous actions
- **PowerShell Native**: Built entirely in PowerShell, compatible with PSAI and OpenAI APIs
- **Progressive Complexity**: Three agent versions showing evolution from simple to advanced

## Prerequisites
- PowerShell 5.1 or higher
- OpenAI API key (set as environment variable `$env:OPENAI_API_KEY`)

## Installation
1. Clone the repository:
   ```powershell
   git clone https://github.com/dfinke/PSClaudeCode.git
   cd PSClaudeCode
   ```

2. Set your OpenAI API key:
   ```powershell
   $env:OPENAI_API_KEY = "your-api-key-here"
   ```

## Usage
The repository includes three agent implementations of increasing complexity:

- `agent-v0.ps1`: Simple single-command agent
- `agent-v1.ps1`: Looping agent with JSON-based responses
- `agent-v2.ps1`: Advanced agent with structured tools and function calling

Run any agent with a task description:
```powershell
.\agent-v0.ps1 "List all PowerShell files in this directory"
```

## Examples

### Agent v0 - Simple Command Runner
```powershell
.\agent-v0.ps1 "list all PowerShell files in this directory"
# AI suggests: Get-ChildItem *.ps1
# Run this command? (y/n)
```

### Agent v1 - Looping Agent
```powershell
.\agent-v1.ps1 "List all files in the current directory and count how many there are"
# Agent will run commands iteratively until task is complete
```

### Agent v2 - Function Calling Agent
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
- [dfinke/psaisuite](https://github.com/dfinke/psaisuite): Simple, unified interface to multiple Generative AI providers. PSAISuite makes it easy for developers to use multiple LLM through a standardized interface.

## License
This project is licensed under the MIT License - see the LICENSE file for details.
