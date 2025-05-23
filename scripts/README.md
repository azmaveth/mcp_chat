# MCP Chat Scripts

This directory contains utility scripts for maintaining code quality.

## Credo Auto-fix Scripts

### `credo_autofix.exs`

Basic auto-fixes for common Credo issues:
- Removes trailing whitespace
- Adds missing trailing blank lines
- Adds underscores to large numbers (10_000 instead of 10000)
- Converts `Enum.map |> Enum.join` to `Enum.map_join`
- Adds parentheses to zero-arity function definitions

Run manually:
```bash
elixir scripts/credo_autofix.exs
```

### `credo_advanced_autofix.exs`

Advanced auto-fixes (use with caution):
- Converts `IO.inspect` to `Logger.debug`
- Adds missing `@moduledoc` to modules
- Converts `length(list) == 0` to `Enum.empty?(list)`
- Suggests module aliases for frequently used nested modules

Run manually:
```bash
elixir scripts/credo_advanced_autofix.exs
```

## Pre-commit Hook

The pre-commit hook automatically runs:
1. `credo_autofix.exs` - Auto-fixes basic issues
2. `mix format` - Formats code according to `.formatter.exs`
3. `mix credo --strict` - Checks for remaining issues

If Credo finds issues that can't be auto-fixed, the commit will be blocked.

To bypass the pre-commit hook (not recommended):
```bash
git commit --no-verify
```

## Manual Code Quality Checks

Run Credo with explanations:
```bash
# Check all files
mix credo --strict

# Explain a specific issue
mix credo explain lib/some_file.ex:42

# Show only specific categories
mix credo --strict --only readability
```

Run formatter:
```bash
# Format all files
mix format

# Check if files are formatted
mix format --check-formatted
```

## Tips

1. Run `mix format` before `mix credo` for best results
2. Some Credo issues require manual intervention (complexity, naming, etc.)
3. Use `@moduledoc false` for internal modules that don't need documentation
4. Use `# credo:disable-for-next-line` to disable specific checks when necessary