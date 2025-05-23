# Credo Auto-fix Scripts

This directory contains scripts to automatically fix common Credo issues.

## Scripts

### credo_autofix.exs

Basic auto-fixes for common issues:
- Trailing whitespace
- Missing trailing blank lines
- Large numbers without underscores (with special handling for model names)
- `Enum.map |> Enum.join` to `Enum.map_join`
- Missing parentheses on zero-arity function definitions

### credo_advanced_autofix.exs

Advanced auto-fixes:
- Converts `IO.inspect` calls to `Logger.debug`
- Adds missing `@moduledoc`
- Fixes `length/1` checks to use `Enum.empty?`
- Suggests module aliases for frequently used nested modules

## Model Name Handling

The autofix scripts have special logic to preserve model names that contain dates in YYYYMMDD format:
- `claude-sonnet-4-20250514`
- `claude-3-5-sonnet-20241022`
- `gpt-4-turbo-20240409`

These will NOT have underscores added to their numeric parts.

## Usage

The basic autofix script runs automatically as part of the pre-commit hook.

To run manually:
```bash
elixir scripts/credo_autofix.exs
```

To run advanced fixes:
```bash
elixir scripts/credo_advanced_autofix.exs
```

## Adding New Fixes

When adding new auto-fix rules:
1. Add the fix function to the appropriate script
2. Document the fix in this README
3. Test thoroughly to ensure it doesn't break existing code
4. Consider edge cases, especially around string literals and model names