.PHONY: all test unit integration examples acceptance clean build help

# Default target
all: build test

# Help target
help:
	@echo "MCP Chat Makefile targets:"
	@echo "  make build       - Build the project and escript"
	@echo "  make test        - Run all tests"
	@echo "  make unit        - Run unit tests only"
	@echo "  make integration - Run integration tests only"
	@echo "  make examples    - Run example demos non-interactively"
	@echo "  make acceptance  - Run user acceptance tests"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make quality     - Run code quality checks (format, credo, dialyzer)"
	@echo "  make setup       - Initial project setup"

# Build targets
build:
	@echo "Building MCP Chat..."
	@mix deps.get
	@mix compile
	@mix escript.build
	@echo "✅ Build complete"

# Test targets
test:
	@echo "Running all tests..."
	@mix test

unit:
	@echo "Running unit tests..."
	@mix test --exclude integration

integration:
	@echo "Running integration tests..."
	@mix test --only integration

# Example and acceptance test targets
examples:
	@echo "Running example demos..."
	@elixir examples/run_examples_simple.exs

acceptance:
	@echo "Running user acceptance tests..."
	@./test_examples.sh

examples-full:
	@echo "Running full example suite..."
	@elixir examples/run_all_examples.exs

acceptance-full:
	@echo "Running comprehensive acceptance tests..."
	@elixir examples/user_acceptance_tests.exs

# Code quality targets
quality: format-check credo dialyzer

format:
	@echo "Formatting code..."
	@mix format

format-check:
	@echo "Checking code formatting..."
	@mix format --check-formatted

credo:
	@echo "Running Credo analysis..."
	@mix credo --strict

dialyzer:
	@echo "Running Dialyzer..."
	@mix dialyzer

# Clean target
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf _build
	@rm -rf deps
	@rm -f mcp_chat
	@echo "✅ Clean complete"

# Setup target for initial development
setup:
	@echo "Setting up MCP Chat development environment..."
	@mix deps.get
	@mix compile
	@./setup.sh
	@echo "✅ Setup complete"

# Quick test for CI/CD
ci-test: build unit examples
	@echo "✅ CI tests complete"

# Development workflow
dev-test: format unit
	@echo "✅ Dev tests complete"

# Full validation before commit
validate: format-check credo unit integration examples
	@echo "✅ All validations passed"