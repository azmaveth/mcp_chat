#!/bin/bash

# MCP Chat Example Test Runner
# This script tests the mcp_chat escript with various commands

set -e  # Exit on error

echo "======================================"
echo "MCP Chat Example Test Suite"
echo "======================================"

# Check if mcp_chat escript exists
if [ ! -f "./mcp_chat" ]; then
    echo "❌ Error: mcp_chat escript not found. Run 'mix escript.build' first."
    exit 1
fi

# Make sure it's executable
chmod +x ./mcp_chat

# Function to run a test
run_test() {
    local test_name="$1"
    local command="$2"
    local expected="$3"
    
    echo ""
    echo "▶ Testing: $test_name"
    echo "  Command: $command"
    
    # Run command and capture output, filtering out logs and ANSI codes
    output=$(echo -e "$command\n/exit" | timeout 15s ./mcp_chat 2>/dev/null | grep -v "^\[" | grep -v "^15:" | grep -v "warning\|info\|notice" | sed 's/\x1b\[[0-9;]*m//g' || true)
    
    # Check if output contains expected text (case insensitive)
    if echo "$output" | grep -qi "$expected"; then
        echo "  ✅ PASS"
        return 0
    else
        echo "  ❌ FAIL - Expected: $expected"
        echo "  Output: ${output:0:100}..."
        return 1
    fi
}

# Function to test with input file
run_input_test() {
    local test_name="$1"
    local input_file="$2"
    local expected="$3"
    
    echo ""
    echo "▶ Testing: $test_name"
    echo "  Input file: $input_file"
    
    # Create input file
    echo "$input_file" > /tmp/test_input.txt
    
    # Run with input and strip ANSI codes
    output=$(timeout 10s ./mcp_chat < /tmp/test_input.txt 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    
    # Check result (case insensitive)
    if echo "$output" | grep -qi "$expected"; then
        echo "  ✅ PASS"
        rm -f /tmp/test_input.txt
        return 0
    else
        echo "  ❌ FAIL - Expected: $expected"
        rm -f /tmp/test_input.txt
        return 1
    fi
}

# Track results
total=0
passed=0

# Test 1: Help command
((total++))
if run_test "Help Command" "/help" "Available commands"; then
    ((passed++))
fi

# Test 2: Version command
((total++))
if run_test "Version Command" "/version" "MCP Chat"; then
    ((passed++))
fi

# Test 3: Model command
((total++))
if run_test "Model List" "/model" "model"; then
    ((passed++))
fi

# Test 4: Context stats
((total++))
if run_test "Context Stats" "/context stats" "Context"; then
    ((passed++))
fi

# Test 5: Session stats
((total++))
if run_test "Session Stats" "/stats" "Session"; then
    ((passed++))
fi

# Test 6: Cost tracking
((total++))
if run_test "Cost Command" "/cost" "Cost"; then
    ((passed++))
fi

# Test 7: Multiple commands via input
((total++))
test_input="/help
/version
/exit"
if run_input_test "Multiple Commands" "$test_input" "Available commands"; then
    ((passed++))
fi

# Test 8: Alias commands
((total++))
test_input="/alias list
/exit"
if run_input_test "Alias List" "$test_input" "alias"; then
    ((passed++))
fi

# Summary
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo "Total tests: $total"
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