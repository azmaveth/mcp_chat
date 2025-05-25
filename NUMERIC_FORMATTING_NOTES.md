# Numeric Formatting in Tests

## Issue

The Elixir formatter automatically adds underscores to numeric literals for readability:
- `1000000` becomes `1_000_000`
- `0.000875` becomes `0.000_875`

This behavior cannot be disabled in the formatter configuration and causes issues in tests that assert exact numeric values, particularly in cost formatting tests where we expect specific string representations of numbers.

## Solution

We've implemented a multi-pronged approach:

### 1. Disabled Credo Check
- Disabled `Credo.Check.Readability.LargeNumbers` in `.credo.exs`
- This prevents Credo from complaining about numbers without underscores

### 2. Use Arithmetic Expressions in Tests
Instead of using literal numeric values that the formatter will modify, we use arithmetic expressions:

```elixir
# Instead of:
assert cost_info.input_cost == 0.00025  # Will become 0.000_25

# We use:
assert cost_info.input_cost == 25 / 100_000  # 0.00025
```

### 3. Documentation
- Added comments in affected test files explaining the approach
- Added notes to `.formatter.exs` explaining why we can't disable the behavior
- Added comments to `.credo.exs` explaining why the check is disabled

## Files Modified

1. **`.credo.exs`** - Disabled `LargeNumbers` check
2. **`.formatter.exs`** - Added explanatory comment
3. **`test/mcp_chat/cost_test.exs`** - Updated to use arithmetic expressions

## Benefits

- Tests remain stable and don't break when formatted
- Numeric values are still readable with inline comments
- No need to fight against the formatter's default behavior