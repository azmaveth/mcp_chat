# Terminal Behavior Analysis

## Issue

The `/help` command and other commands are not working when running via `mix mcp_chat.run`, but work fine in IEx mode (`iex -S mix` then `MCPChat.main()`).

## Root Cause

When running via Mix task, the terminal detection logic in `ExReadlineAdapter` detects `:ebadf` (bad file descriptor) for the terminal option, which causes it to use the `:simple` reader implementation instead of the `:advanced` reader.

### Terminal Detection Results

1. **Mix Task Mode (`mix mcp_chat.run`)**
   - `:io.getopts(:standard_io)` returns: `terminal: :ebadf`
   - `tty` command fails with "not a tty"
   - `:io.columns()` returns `{:error, :enotsup}`
   - Detection result: `:simple` reader

2. **IEx Mode**
   - IEx is detected via `IEx.started?()`
   - Detection result: `:simple` reader (to avoid conflicts with IEx's own line editing)

3. **Direct Elixir Script**
   - Similar behavior to Mix task mode
   - Detection result: `:simple` reader

## Why Commands Work

The commands DO work even with the simple reader. The issue with immediate exit is that when running `mix mcp_chat.run` without a proper TTY, the application immediately receives EOF on stdin and exits gracefully.

### Test Results

```bash
# This shows /help command working correctly
echo "/help" | mix mcp_chat.run
```

## Solution Options

1. **Environment Variable Override**
   The Mix task now sets `MCP_READLINE_MODE=advanced` to force advanced mode. However, this doesn't solve the EOF issue when running without stdin.

2. **Use IEx Mode**
   For interactive use, run:
   ```bash
   iex -S mix
   iex> MCPChat.main()
   ```

3. **Proper TTY Allocation**
   When running the Mix task, ensure it's run in an interactive terminal, not in a script or CI environment.

## Implementation Details

The terminal detection logic in `lib/mcp_chat/cli/ex_readline_adapter.ex`:

1. First checks if running in IEx (uses simple reader to avoid conflicts)
2. Checks for `MCP_READLINE_MODE` environment variable override
3. Falls back to terminal detection via `:io.getopts(:standard_io)`
4. Uses `:simple` reader when terminal is `:ebadf` or `false`
5. Uses `:advanced` reader when a proper terminal is detected

## Recommendations

1. For interactive use, prefer running via IEx: `iex -S mix` then `MCPChat.main()`
2. The Mix task `mix mcp_chat.run` is best suited for scripted/piped input
3. Commands work correctly in both modes - the issue is only with terminal allocation and EOF handling