# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2025-05-26

### Added
- **Progress Tracking**: Real-time progress bars for long-running MCP operations
  - `/mcp tool` with `--progress` flag enables progress tracking
  - `/mcp progress` command shows all active operations
  - ProgressTracker GenServer manages operation lifecycle
- **Notification System**: Real-time updates when server capabilities change
  - NotificationRegistry with pluggable handlers
  - Automatic notifications for tool/resource/prompt changes
  - `/mcp notify` command to control notification display
- **Server-side LLM Generation**: Support for MCP servers with sampling capability
  - `/mcp sample` command for server-side text generation
  - Support for temperature, max tokens, and model preferences
  - Integration with existing cost tracking
- **Enhanced MCP Commands**:
  - `/mcp capabilities` shows detailed server capabilities including new features
  - Improved `/model` command shows current model and available models
  - Consolidated all MCP commands under `/mcp` with subcommands
- **Context File Management**:
  - `/context add <file>` to add files to session context
  - `/context rm <file>` to remove files
  - `/context list` to show all context files
  - Context files included in LLM requests automatically
- **Supervision Improvements**:
  - HealthMonitor for process health tracking
  - CircuitBreaker for LLM API resilience
  - ChatSupervisor for main loop crash recovery
  - PortSupervisor for stdio connection management
  - ConnectionPool framework for HTTP clients
- **Documentation**:
  - New NOTIFICATIONS.md guide
  - Comprehensive examples in examples/ directory
  - BEAM integration examples with multi-agent support
  - Demo MCP servers (time, calculator, data)

### Changed
- Updated to use ex_mcp v0.2.0 with latest protocol features
- MCP client connections now use NotificationClient wrapper when notifications enabled
- Improved error messages and user feedback throughout
- Enhanced UI with progress bars and markdown rendering support

### Fixed
- Legacy MCP commands removed for cleaner interface
- Various compilation warnings resolved
- Test isolation improved for notification handlers

## [0.1.1] - 2025-01-26

### Added
- Comprehensive test coverage for MCP CLI commands (`/tools`, `/connect`, etc.)
- Documentation for handling numeric formatting in tests (NUMERIC_FORMATTING_NOTES.md)

### Changed
- Hardware acceleration warning now logs at debug level instead of warning level
- Improved accuracy of hardware acceleration status reporting
- Model loader initialization messages now correctly reflect actual acceleration status

### Fixed
- Fixed test failures due to ExAlias API returning structured error tuples
- Fixed session message ordering (removed incorrect reversal)
- Fixed cost test failures caused by Elixir formatter adding underscores to numeric literals
- Fixed MCP adapter to properly handle both new and legacy tool response formats
- Fixed various test compilation errors and outdated expectations

### Technical
- Disabled Credo's `LargeNumbers` check to prevent conflicts with test assertions
- Updated tests to use arithmetic expressions instead of literal numbers to avoid formatter issues
- Improved test isolation with proper mocking using meck

## [0.1.0] - Initial Release

### Added
- Initial implementation of MCP Chat Client
- Support for multiple LLM backends (Anthropic, OpenAI, Ollama, etc.)
- MCP server integration
- Command-line interface with various commands
- Session management and persistence
- Cost tracking and reporting
- Hardware acceleration support detection