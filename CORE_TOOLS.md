# Core Tools Implementation Guide

## Overview

This document outlines the implementation approach for adding core file and command execution tools to MCP Chat. The design prioritizes security and performance equally while maintaining architectural consistency with the existing MCP infrastructure.

## Architecture Decision

### Chosen Approach: Hybrid Synchronous-Async with Privileged Local Peer

After extensive analysis, we've selected a **Hybrid Synchronous-Async Architecture** with a **Privileged Local Peer** pattern that:

1. **Maintains architectural consistency** by implementing tools as an internal MCP server
2. **Preserves responsive UX** for fast operations (file I/O)
3. **Ensures security** for dangerous operations (command execution)
4. **Reduces complexity** compared to fully async approaches

### Core Components

```
MCPChat Application
├── ServerManager (existing)
│   ├── External MCP Servers
│   └── @core (CoreToolsServer) ← New privileged peer
├── CoreToolsServer ← New GenServer
├── PathSanitizer ← New security module
├── ExecutionSandbox ← New sandboxing module
└── UI Permission Handler ← New user confirmation system
```

## Implementation Phases

### Phase 1: Read-Only Foundation (Priority: High)
**Deliverable:** Safe file reading with path sanitization
**Timeline:** 1-2 weeks

**Components to implement:**
1. `CoreToolsServer` GenServer
2. `PathSanitizer` security module  
3. Integration with existing `ServerManager`
4. `read_file` tool implementation

### Phase 2: Secure Writes (Priority: Medium)
**Deliverable:** File writing with user confirmation
**Timeline:** 1 week

**Components to implement:**
1. `PermissionHandler` for user confirmations
2. `write_file` tool with size/quota limits
3. CLI integration for permission prompts

### Phase 3: Command Execution (Priority: High Risk)
**Deliverable:** Sandboxed command execution
**Timeline:** 2-3 weeks

**Components to implement:**
1. `ExecutionSandbox` with MuonTrap integration
2. Cross-platform strategy pattern
3. `execute_command` tool implementation

## Security Model

### Multi-Layer Defense Strategy

1. **Path Sanitization**: Prevent directory traversal attacks
2. **Workspace Isolation**: All file operations confined to `~/.mcp_chat/workspace/`
3. **User Confirmation**: Interactive prompts for dangerous operations
4. **Process Sandboxing**: cgroup-based containment (Linux) with fallback
5. **Resource Limits**: Timeouts, output size limits, memory constraints

### Threat Model

**Protected Against:**
- Directory traversal attacks (`../../../etc/passwd`)
- Command injection via shell metacharacters
- Resource exhaustion (CPU, memory, disk)
- Runaway processes
- Privilege escalation

**Not Protected Against (Out of Scope):**
- Network-based attacks from executed commands
- Side-channel attacks
- Physical access to the machine
- Bugs in the Erlang/Elixir runtime

## Detailed Implementation Specs

### 1. CoreToolsServer

```elixir
defmodule MCPChat.MCP.CoreToolsServer do
  use GenServer
  
  @workspace_root Path.expand("~/.mcp_chat/workspace/")
  @max_file_size 10 * 1024 * 1024  # 10MB
  @max_output_size 1 * 1024 * 1024  # 1MB
  
  # Registration with ServerManager
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    File.mkdir_p!(@workspace_root)
    # Register with ServerManager as "@core"
    MCPChat.MCP.ServerManager.register_builtin_server(self(), "@core")
    {:ok, %{operations: %{}}}
  end
  
  # Tool implementations
  def call_tool("read_file", %{"path" => path}) do
    # Synchronous - fast operation
    with {:ok, safe_path} <- PathSanitizer.safe_join(@workspace_root, path),
         {:ok, content} <- File.read(safe_path) do
      {:ok, %{"content" => content}}
    else
      {:error, :enoent} -> {:error, "File not found"}
      {:error, :path_traversal_attempt} -> {:error, "Invalid path"}
      error -> error
    end
  end
  
  def call_tool("write_file", %{"path" => path, "content" => content}) do
    # Requires user confirmation
    case request_permission("write_file", %{path: path, size: byte_size(content)}) do
      :granted ->
        with {:ok, safe_path} <- PathSanitizer.safe_join(@workspace_root, path),
             :ok <- validate_file_size(content),
             :ok <- File.write(safe_path, content) do
          {:ok, %{"message" => "File written successfully"}}
        end
      :denied -> {:error, "Permission denied by user"}
    end
  end
  
  def call_tool("execute_command", %{"command" => cmd, "args" => args}) do
    # Always async due to security sensitivity
    operation_id = generate_operation_id()
    
    case request_permission("execute_command", %{command: cmd, args: args}) do
      :granted ->
        spawn_supervised_execution(operation_id, cmd, args)
        {:async, operation_id, "Execution started. Use '/mcp progress #{operation_id}' to check status."}
      :denied -> 
        {:error, "Permission denied by user"}
    end
  end
end
```

### 2. Path Sanitization Module

```elixir
defmodule MCPChat.Security.PathSanitizer do
  @moduledoc """
  Provides secure path joining and validation to prevent directory traversal attacks.
  
  Critical security component - handles user-provided paths safely.
  """
  
  @doc """
  Safely joins a root path with a user-provided relative path.
  
  Prevents directory traversal attacks by ensuring the final path
  remains within the root directory after resolving all symbolic links
  and relative path components.
  
  ## Examples
  
      iex> PathSanitizer.safe_join("/workspace", "file.txt")
      {:ok, "/workspace/file.txt"}
      
      iex> PathSanitizer.safe_join("/workspace", "../../../etc/passwd")
      {:error, :path_traversal_attempt}
  """
  def safe_join(root_path, user_path) do
    # 1. Expand root to canonical absolute path
    abs_root = Path.expand(root_path) |> Path.absname()
    
    # 2. Join with user path - Path.join handles basic ".." resolution
    combined_path = Path.join(abs_root, user_path)
    
    # 3. Canonicalize to resolve all "..", ".", and symlinks
    final_path = Path.expand(combined_path) |> Path.absname()
    
    # 4. Verify final path is still within root
    if String.starts_with?(final_path, abs_root) do
      {:ok, final_path}
    else
      {:error, :path_traversal_attempt}
    end
  end
  
  @doc """
  Validates that a filename contains only safe characters.
  Rejects filenames with shell metacharacters or control characters.
  """
  def safe_filename?(filename) do
    # Allow alphanumeric, dots, dashes, underscores, spaces
    Regex.match?(~r/^[a-zA-Z0-9._\-\s]+$/, filename) and
    not String.contains?(filename, ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"])
  end
end
```

### 3. Execution Sandbox Architecture

```elixir
defmodule MCPChat.MCP.ExecutionSandbox do
  @moduledoc """
  Provides secure command execution with platform-specific sandboxing.
  
  Uses a Strategy pattern to apply the best available sandboxing
  technology for the current platform.
  """
  
  defmodule Strategy do
    @callback execute(String.t(), [String.t()], keyword()) :: 
      {:ok, binary()} | {:error, atom()}
  end
  
  def execute(command, args, opts \\ []) do
    strategy = select_strategy()
    Logger.info("Executing command with strategy: #{inspect(strategy)}")
    strategy.execute(command, args, opts)
  end
  
  defp select_strategy do
    case :os.type() do
      {:unix, :linux} -> 
        if muontrap_available?() do
          MCPChat.MCP.ExecutionSandbox.MuonTrapStrategy
        else
          MCPChat.MCP.ExecutionSandbox.DefaultStrategy
        end
      _ -> 
        MCPChat.MCP.ExecutionSandbox.DefaultStrategy
    end
  end
end

defmodule MCPChat.MCP.ExecutionSandbox.DefaultStrategy do
  @behaviour MCPChat.MCP.ExecutionSandbox.Strategy
  
  @max_output_size 1_000_000  # 1MB
  @default_timeout 5_000      # 5 seconds
  
  def execute(command, args, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    
    # Never use shell - direct execution only
    case System.cmd(command, args, 
           stderr_to_stdout: true,
           into: IO.stream(:stdio, :line),
           max_buffer: @max_output_size) do
      {output, 0} -> {:ok, output}
      {output, exit_code} -> {:error, {:exit_code, exit_code, output}}
    end
  rescue
    error -> {:error, {:exception, error}}
  end
end

defmodule MCPChat.MCP.ExecutionSandbox.MuonTrapStrategy do
  @behaviour MCPChat.MCP.ExecutionSandbox.Strategy
  
  def execute(command, args, opts) do
    cgroup_opts = [
      cgroup_controllers: ["cpu", "memory"],
      cgroup_base: "mcp_chat",
      cpu_shares: 512,        # Limit CPU usage
      memory_limit: 100_000_000  # 100MB memory limit
    ]
    
    muontrap_opts = cgroup_opts ++ [
      stderr_to_stdout: true,
      into: IO.stream(:stdio, :line)
    ]
    
    case MuonTrap.cmd(command, args, muontrap_opts) do
      {output, 0} -> {:ok, output}
      {output, exit_code} -> {:error, {:exit_code, exit_code, output}}
    end
  rescue
    error -> {:error, {:exception, error}}
  end
end
```

### 4. Permission System

```elixir
defmodule MCPChat.UI.PermissionHandler do
  @moduledoc """
  Handles user permission requests for dangerous operations.
  
  Provides interactive confirmation prompts with clear risk information.
  """
  
  def request_permission(operation, params) do
    message = format_permission_request(operation, params)
    
    IO.puts("\n" <> IO.ANSI.yellow() <> "⚠️  PERMISSION REQUEST" <> IO.ANSI.reset())
    IO.puts(message)
    IO.puts(IO.ANSI.red() <> "This action could be dangerous." <> IO.ANSI.reset())
    
    response = IO.gets("Allow this operation? [y/N]: ")
    
    case String.trim(String.downcase(response)) do
      "y" -> :granted
      "yes" -> :granted
      _ -> :denied
    end
  end
  
  defp format_permission_request("write_file", %{path: path, size: size}) do
    """
    The agent wants to write a file:
    📝 Path: #{path}
    📊 Size: #{format_size(size)}
    """
  end
  
  defp format_permission_request("execute_command", %{command: cmd, args: args}) do
    full_command = Enum.join([cmd | args], " ")
    """
    The agent wants to execute a command:
    💻 Command: #{full_command}
    """
  end
  
  defp format_size(bytes) when bytes < 1024, do: "#{bytes} bytes"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp format_size(bytes), do: "#{div(bytes, 1024 * 1024)} MB"
end
```

### 5. ServerManager Integration

```elixir
# Additions to MCPChat.MCP.ServerManager

def register_builtin_server(pid, name) do
  GenServer.call(__MODULE__, {:register_builtin, pid, name})
end

def handle_call({:register_builtin, pid, name}, _from, state) do
  new_state = put_in(state.builtin_servers[name], pid)
  {:reply, :ok, new_state}
end

def handle_call({:call_tool, "@core", tool_name, arguments}, from, state) do
  # Direct call to CoreToolsServer
  result = MCPChat.MCP.CoreToolsServer.call_tool(tool_name, arguments)
  {:reply, result, state}
end

def handle_call({:call_tool, server_name, tool_name, arguments}, from, state) do
  # Existing logic for external servers
  # ...
end
```

## Dependencies

### Required Libraries

Add to `mix.exs`:

```elixir
defp deps do
  [
    # Existing dependencies...
    {:muontrap, "~> 1.5", optional: true},  # Linux cgroup sandboxing
    {:erlexec, "~> 2.0", optional: true}    # Advanced process control
  ]
end
```

### System Requirements

**Linux (Recommended):**
- `cgroup-tools` package for MuonTrap
- `libcap-dev` for erlexec privilege management

**macOS/Windows:**
- Basic sandboxing via process timeouts and output limits

## Security Considerations

### Implementation Checklist

- [ ] **Path Sanitization**: All file paths validated with `PathSanitizer.safe_join/2`
- [ ] **No Shell Execution**: Commands executed directly, never through shell
- [ ] **Resource Limits**: Timeouts, memory limits, output size limits enforced
- [ ] **User Confirmation**: All dangerous operations require explicit user approval
- [ ] **Workspace Isolation**: All file operations confined to designated workspace
- [ ] **Input Validation**: All user inputs validated and sanitized
- [ ] **Error Handling**: Secure error messages that don't leak system information
- [ ] **Logging**: All operations logged for security audit trail

### Security Testing

Create test cases for:

1. **Path Traversal Prevention**
   ```elixir
   test "rejects directory traversal attempts" do
     assert {:error, :path_traversal_attempt} = 
       PathSanitizer.safe_join("/workspace", "../../../etc/passwd")
   end
   ```

2. **Command Injection Prevention**
   ```elixir
   test "rejects shell metacharacters in commands" do
     assert {:error, _} = 
       CoreToolsServer.call_tool("execute_command", %{
         "command" => "echo", 
         "args" => ["hello; rm -rf /"]
       })
   end
   ```

3. **Resource Exhaustion Protection**
   ```elixir
   test "limits output size" do
     # Test command that generates large output
     assert {:error, {:resource_limit, :output_size}} = 
       ExecutionSandbox.execute("yes", [], timeout: 1000)
   end
   ```

## Performance Considerations

### Optimization Strategies

1. **Workspace Caching**: Cache workspace path resolution
2. **Permission Batching**: Allow "yes to all" for series of related operations
3. **Process Pooling**: Reuse sandbox processes for repeated operations
4. **Streaming I/O**: Use streaming for large file operations

### Monitoring

Track metrics for:
- Operation latency (read_file, write_file, execute_command)
- Permission request frequency and approval rates
- Resource usage (CPU, memory, disk)
- Security events (path traversal attempts, command rejections)

## Error Handling

### Error Categories

1. **Security Errors**: Path traversal, command injection attempts
2. **Permission Errors**: User denied permission, insufficient privileges
3. **Resource Errors**: File not found, disk full, timeout exceeded
4. **System Errors**: Process spawn failures, sandbox setup failures

### Error Response Format

```elixir
# Success
{:ok, %{"content" => "file contents"}}

# Error with user-safe message
{:error, "File not found"}

# Async operation started
{:async, "op_123", "Execution started..."}
```

## Testing Strategy

### Unit Tests
- Path sanitization edge cases
- Permission handler user inputs
- Error conditions and edge cases

### Integration Tests
- Full tool execution flow
- ServerManager routing to @core
- Permission prompt integration

### Security Tests
- Penetration testing with malicious inputs
- Resource exhaustion scenarios
- Privilege escalation attempts

### Performance Tests
- Large file handling
- Concurrent operation stress testing
- Memory usage profiling

## Deployment Considerations

### Configuration

Add to `config/config.exs`:

```elixir
config :mcp_chat, :core_tools,
  workspace_root: "~/.mcp_chat/workspace",
  max_file_size: 10 * 1024 * 1024,      # 10MB
  max_output_size: 1 * 1024 * 1024,     # 1MB
  default_timeout: 5_000,                # 5 seconds
  enable_sandboxing: true,
  require_permissions: true
```

### Docker Considerations

When running in containers:
- Mount workspace as volume for persistence
- Configure cgroup access for MuonTrap
- Set appropriate security context

## Future Enhancements

### Phase 4: Advanced Features (Future)
- **Capability Tokens**: Fine-grained permission system
- **Audit Logging**: Comprehensive security event logging
- **Remote Workspaces**: Support for remote file systems
- **Collaboration**: Multi-user permission workflows

### Integration Opportunities
- **Git Integration**: Version control for workspace files
- **Cloud Storage**: Sync workspace with cloud providers
- **IDE Integration**: Deep integration with development tools

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - Check file system permissions on workspace directory
   - Verify user has access to execute requested commands

2. **Sandboxing Failures**
   - Ensure cgroup-tools installed on Linux
   - Check MuonTrap dependencies and configuration

3. **Path Resolution Issues**
   - Verify workspace directory exists and is accessible
   - Check for symlink resolution problems

### Debug Commands

```bash
# Test workspace access
ls -la ~/.mcp_chat/workspace/

# Check cgroup availability (Linux)
mount | grep cgroup

# Test MuonTrap installation
mix deps.get
mix deps.compile muontrap
```

## Conclusion

This implementation provides a robust, secure foundation for core tools in MCP Chat. The hybrid synchronous-async approach balances security, performance, and user experience while maintaining architectural consistency.

The phased rollout allows for incremental value delivery and risk management, starting with safe read operations and progressing to more complex and potentially dangerous operations only after the security foundation is proven.

Key success factors:
1. **Security First**: Every operation validated and sandboxed
2. **User Control**: Explicit permission for dangerous operations  
3. **Platform Awareness**: Optimal sandboxing for each platform
4. **Performance**: Responsive UX for common operations
5. **Maintainability**: Clear separation of concerns and comprehensive testing

This design positions MCP Chat to safely provide powerful file and command execution capabilities while maintaining the security and reliability expected of a production system.