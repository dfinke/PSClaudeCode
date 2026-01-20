# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-01-20

### Added
- **Model Parameter**: Added configurable `-Model` parameter to `Invoke-PSClaudeCode` function
- **Sub-agent Support**: Implemented sub-agent delegation for complex tasks with `Run-SubAgent` function
- **Enhanced Safety Checks**: Improved permission system with user confirmation for dangerous operations
- **UTF-8 Encoding**: Fixed emoji display issues by ensuring proper UTF-8 encoding throughout the codebase

### Changed
- **API Provider Migration**: Migrated from OpenAI API to Anthropic Claude API
- **Environment Variables**: Changed from `$env:OPENAI_API_KEY` to `$env:ANTHROPIC_API_KEY`
- **Module Structure**: Properly structured as PowerShell module with `.psm1` and `.psd1` files
- **Function Export**: Correctly exports `Invoke-PSClaudeCode` function through module manifest
- **Documentation**: Updated README.md to reflect Anthropic integration and new features

### Fixed
- **Encoding Issues**: Resolved corrupted Unicode emoji characters (⚠️, ✅, 🤖, 🔧, 🚫, 📝, →)
- **Module Loading**: Fixed `.psm1` file to properly dot-source functions from `Public/` directory
- **Manifest Metadata**: Corrected module description, tags, and release notes

## [1.0.1] - 2026-01-10

### Added
- **Module Manifest**: Created `PSClaudeCode.psd1` with proper metadata and function exports
- **Documentation Links**: Added links to related projects (PSAI, PSAISuite) in README
- **Header Image**: Added PowerShell-Claude-Code.png to repository

### Changed
- **Module Version**: Bumped version to 1.0.1
- **Publish Script**: Updated module path references in `PublishToGallery.ps1`

## [1.0.0] - 2026-01-01

### Added
- **Initial Release**: First public release of PSClaudeCode
- **Invoke-PSClaudeCode Function**: Main cmdlet for AI agent interactions
- **Tool-Based Architecture**: Implemented structured tools for file operations and command execution
- **Permission System**: Added safety checks for potentially dangerous operations
- **Reference Implementations**: Included three agent evolution examples (`agent-v0.ps1`, `agent-v1.ps1`, `agent-v2.ps1`)
- **Comprehensive Documentation**: Detailed README with usage examples and installation instructions
- **OpenAI Integration**: Initial implementation using OpenAI API for compatibility with PSAI

### Features
- **Agent Loop**: Iterative task completion with AI-driven decision making
- **File Operations**: Read and write file capabilities through structured tools
- **Command Execution**: Safe PowerShell command execution with user confirmation
- **JSON Tool Calling**: Function calling implementation for structured interactions
- **Progress Feedback**: Visual indicators and status messages during agent execution

---

## Development History

### Agent Evolution Path
The project includes three reference implementations showing the evolution from simple to advanced:

1. **Agent v0** (`agent-v0.ps1`): Simple single-command agent using OpenAI
2. **Agent v1** (`agent-v1.ps1`): Looping agent with JSON-based responses using OpenAI
3. **Agent v2** (`agent-v2.ps1`): Advanced agent with structured tools and function calling using OpenAI

### Migration to Anthropic
- **API Migration**: Transitioned from OpenAI to Anthropic Claude API for improved performance and capabilities
- **Model Updates**: Updated to use latest Claude models (claude-sonnet-4-5-20250929)
- **Parameter Flexibility**: Added model selection capability for different use cases

---

## Contributing

When contributing to this project, please:
1. Update the CHANGELOG.md file with your changes
2. Follow the existing format and categorization
3. Add entries under an "Unreleased" section for upcoming changes

### Types of Changes
- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security-related changes