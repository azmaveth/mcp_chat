# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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