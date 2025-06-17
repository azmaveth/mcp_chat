#!/bin/bash

# Integration test script for MCP Chat
# Tests the actual functionality with proper environment setup

set -e

echo "======================================"
echo "MCP Chat Integration Tests"
echo "======================================"

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Build if needed
if [ ! -f "./mcp_chat" ]; then
    echo "Building MCP Chat..."
    mix escript.build
fi

# Set up environment
export MCP_CHAT_TEST_MODE=true
export EX_LLM_MOCK_ENABLED=true

# Function to test a feature
test_feature() {
    local name="$1"
    local test_fn="$2"
    
    echo ""
    echo "▶ Testing: $name"
    
    if $test_fn; then
        echo "  ✅ PASS"
        return 0
    else
        echo "  ❌ FAIL"
        return 1
    fi
}

# Test functions
test_commands() {
    # Test basic commands work in Elixir context
    elixir -e '
        # Load dependencies
        Code.prepend_path("_build/dev/lib/mcp_chat/ebin")
        Code.prepend_path("_build/dev/lib/ex_llm/ebin")
        Code.prepend_path("_build/dev/lib/ex_mcp/ebin")
        
        # Test command modules exist
        modules = [
            MCPChat.CLI.Commands.Utility,
            MCPChat.CLI.Commands.Session,
            MCPChat.CLI.Commands.Context,
            MCPChat.CLI.Commands.Alias
        ]
        
        missing = Enum.reject(modules, &Code.ensure_loaded?/1)
        
        if length(missing) == 0 do
            IO.puts("  All command modules loaded successfully")
            System.halt(0)
        else
            IO.puts("  Missing modules: #{inspect(missing)}")
            System.halt(1)
        end
    '
}

test_context_management() {
    elixir -e '
        Code.prepend_path("_build/dev/lib/mcp_chat/ebin")
        
        # Test context module
        if Code.ensure_loaded?(MCPChat.Context) do
            # Basic operations should work
            MCPChat.Context.add_to_context("test content", "test.txt")
            stats = MCPChat.Context.get_context_stats()
            
            if is_map(stats) do
                IO.puts("  Context operations work")
                System.halt(0)
            else
                System.halt(1)
            end
        else
            System.halt(1)
        end
    '
}

test_session_management() {
    elixir -e '
        Code.prepend_path("_build/dev/lib/mcp_chat/ebin")
        
        if Code.ensure_loaded?(MCPChat.Session) do
            session = MCPChat.Session.new_session()
            
            if is_map(session) and Map.has_key?(session, :id) do
                IO.puts("  Session creation works")
                System.halt(0)
            else
                System.halt(1)
            end
        else
            System.halt(1)
        end
    '
}

test_mock_llm() {
    elixir -e '
        Code.prepend_path("_build/dev/lib/mcp_chat/ebin")
        Code.prepend_path("_build/dev/lib/ex_llm/ebin")
        
        # Test mock adapter
        messages = [%{role: "user", content: "test"}]
        
        case MCPChat.LLM.ExLLMAdapter.chat(messages, 
                                          provider: :mock, 
                                          mock_response: "Mock response") do
            {:ok, response} ->
                if response.content == "Mock response" do
                    IO.puts("  Mock LLM works")
                    System.halt(0)
                else
                    System.halt(1)
                end
            _ ->
                System.halt(1)
        end
    '
}

# Run tests
total=0
passed=0

tests=(
    "Command Modules:test_commands"
    "Context Management:test_context_management"
    "Session Management:test_session_management"
    "Mock LLM Adapter:test_mock_llm"
)

for test in "${tests[@]}"; do
    IFS=':' read -r name func <<< "$test"
    ((total++))
    
    if test_feature "$name" "$func"; then
        ((passed++))
    fi
done

# Summary
echo ""
echo "======================================"
echo "Summary"
echo "======================================"
echo "Total: $total"
echo "Passed: $passed"
echo "Failed: $((total - passed))"
echo ""

if [ $passed -eq $total ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi