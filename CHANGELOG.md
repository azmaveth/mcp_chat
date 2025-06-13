# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2024-06-13

### Fixed
- **MCP Transport Architecture**: Fixed ExMCP.Client communication issues
  - Fixed push/pull model mismatch in ManagedStdio transport
  - Eliminated FunctionClauseError in ExMCP.Client.handle_info/2
  - Implemented proper pull-based message queuing with async receiver
  - Resolved integration test timeouts and connection failures
- **Test Suite Improvements**: Significantly improved test reliability
  - Fixed all acceptance tests (8/8 now passing)
  - Reduced integration test failures from 8 to 2 remaining edge cases
  - Enhanced test infrastructure with ANSI handling and case-insensitive matching
  - Updated standalone MCP server to use correct protocol version (2025-03-26)
- **Process Management**: Enhanced stdio process lifecycle management
  - Added comprehensive process status tracking (stopped, running, exited, failed)
  - Implemented restart counting and proper exit status handling
  - Fixed StdioProcessManager auto-start behavior for production use
  - Enhanced ServerWrapper with health checks and better timeout handling
- **Command System**: Fixed missing command routing
  - Added /stats command routing to Utility module
  - Ensured all CLI commands work properly in escript mode

### Added
- **OTP Supervision**: Built robust process supervision architecture
  - Created StdioProcessSupervisor for automatic restart logic
  - Configurable restart strategies with exponential backoff
  - Restart counting and rate limiting for stability
  - Integration with existing ServerWrapper for seamless operation

### Added
- **Permanent Session Management**: All chat sessions are now automatically saved permanently
  - Sessions are saved with datetime and directory-based naming (e.g., `mcp_chat_20250531_161140`)
  - Automatic saving on every message for zero data loss
  - CLI flags for session management:
    - `-c/--continue`: Continue the most recent chat session
    - `-r/--resume <path>`: Resume a specific session by filename or ID
    - `-l/--list-sessions`: List all saved chat sessions with details
  - Session metadata tracking (start directory, timestamps)
  - Beautiful session info display when resuming with recent message preview
  - Session listing shows time ago, message count, and file size
- **Enhanced Terminal Support**: Updated ex_readline integration for improved escript functionality
  - Integrated ex_readline v0.2.1 with automatic terminal mode detection
  - Fixed arrow key navigation in escript mode (no more raw escape sequences)
  - Proper Ctrl-P/N history navigation in compiled binaries
  - Direct TTY access for escript environments
  - Maintained backward compatibility with existing readline functionality
- **Async Context File Loading**: Non-blocking file loading with progress tracking
  - AsyncFileLoader module with concurrent file processing
  - Progress tracking integration with real-time updates
  - Batch file loading with configurable concurrency limits
  - Memory-efficient streaming for large files
  - CLI commands: `/context add-async` and `/context add-batch`
  - Content validation and preprocessing with line ending normalization
- **TUI Components**: Beautiful text-based UI components using Owl library
  - Progress display with real-time updates for MCP operations
  - Resource cache display with summary and detailed views
  - TUI manager for coordinating multiple displays
  - `/tui` command for controlling displays
- **Performance Optimizations**:
  - Startup profiling with detailed phase tracking
  - Lazy loading for MCP servers (lazy/eager/background modes)
  - Configurable startup behavior in config.toml
- **Memory Management**:
  - Message store with hybrid memory/disk storage
  - Configurable pagination for conversation history
  - Smart context memory adapter for efficient retrieval
- **Resource Caching**:
  - Local caching layer for MCP resources
  - Automatic cache invalidation via resource subscriptions
  - LRU eviction policy with size limits
  - Comprehensive cache statistics and monitoring
- **Notification Enhancements**:
  - Comprehensive notification handler for all MCP event types
  - Event history tracking and batching
  - Configurable notification settings per category
  - `/notification` command for runtime control
- **Enhanced Streaming**:
  - StreamManager for async processing with backpressure
  - StreamBuffer circular buffer for efficient memory usage
  - EnhancedConsumer with intelligent chunk batching
  - Configurable streaming parameters (buffer size, batch intervals)
  - Comprehensive streaming metrics and monitoring
  - Graceful handling of slow terminals
- **Parallel MCP Connections**:
  - ParallelConnectionManager for concurrent server initialization
  - Configurable concurrency limits and per-server timeouts
  - Progress tracking for parallel connection operations
  - Integration with all connection modes (lazy/eager/background)
  - Individual error isolation prevents one server blocking others
  - Significant startup time improvements in eager mode
- **Concurrent Tool Execution**:
  - ConcurrentToolExecutor for safe parallel tool execution
  - Safety checks to prevent unsafe concurrent operations
  - Server-based grouping with configurable concurrency limits
  - Progress tracking and timeout handling for long operations
  - /concurrent command for testing and managing concurrent operations
  - Tool safety analysis and execution statistics

### Changed
- Improved startup performance with lazy loading options
- Enhanced memory efficiency for long conversations
- Better resource management with caching
- **Logger Configuration**: Default log level set to `:info` to reduce debug noise
- **Autosave Behavior**: Sessions now saved immediately on every message (no more periodic saves)

### Fixed
- Memory usage for large conversation histories
- Startup delays when connecting to multiple MCP servers
- **Config Module**: Added missing `get/2` and `get/3` functions with default value support
- **Circuit Breaker**: Fixed Task ownership issue by handling tasks in owner process
- **Credo Issues**: Fixed all warnings (replaced `length()` with `Enum.empty?()`, fixed alias ordering)

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