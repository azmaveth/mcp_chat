defmodule MCPChat.Security.MCPSecurityAdapter do
  @moduledoc """
  Security adapter for MCP (Model Context Protocol) operations.

  This module provides secure execution of MCP tools by integrating with the
  capability-based security system. It validates permissions before executing
  any MCP operations and logs all security-relevant events.

  ## Integration Points

  - Wraps MCP tool execution with capability validation
  - Provides secure resource access for MCP servers
  - Implements permission delegation for agent workflows
  - Integrates with audit logging for compliance

  ## Usage

  The adapter is designed to be a drop-in replacement for direct MCP calls:

      # Instead of calling MCP directly
      ExMCP.call_tool(session, tool_name, args)
      
      # Use the security adapter
      MCPSecurityAdapter.call_tool_secure(session, tool_name, args, capability)
  """

  require Logger
  alias MCPChat.Security
  alias MCPChat.Security.{Capability, AuditLogger}

  @type mcp_session :: any()
  @type tool_name :: String.t()
  @type tool_args :: map()
  @type resource_path :: String.t()

  @doc """
  Securely executes an MCP tool with capability validation.

  ## Parameters
  - `session`: The MCP session
  - `tool_name`: Name of the tool to execute
  - `args`: Arguments for the tool
  - `capability`: Capability granting permission for this operation

  ## Returns
  - `{:ok, result}` on successful execution
  - `{:error, :permission_denied}` if capability validation fails
  - `{:error, reason}` for other failures
  """
  @spec call_tool_secure(mcp_session(), tool_name(), tool_args(), Capability.t()) ::
          {:ok, any()} | {:error, atom()}
  def call_tool_secure(session, tool_name, args, capability) do
    with :ok <- validate_inputs(session, tool_name, args),
         :ok <- validate_tool_permission(capability, tool_name, args),
         {:ok, result} <- execute_mcp_tool(session, tool_name, args) do
      # Log successful execution
      Security.log_security_event(:mcp_tool_executed, %{
        tool_name: tool_name,
        args: sanitize_args(args),
        capability_id: capability.id
      })

      {:ok, result}
    else
      {:error, reason} = error ->
        # Log security violation
        Security.log_security_event(:mcp_tool_denied, %{
          tool_name: tool_name,
          args: sanitize_args(args),
          capability_id: capability.id,
          reason: reason
        })

        error
    end
  end

  @doc """
  Securely reads an MCP resource with capability validation.

  ## Parameters
  - `session`: The MCP session
  - `resource_uri`: URI of the resource to read
  - `capability`: Capability granting permission for this operation

  ## Returns
  - `{:ok, content}` on successful read
  - `{:error, :permission_denied}` if capability validation fails
  - `{:error, reason}` for other failures
  """
  @spec read_resource_secure(mcp_session(), String.t(), Capability.t()) ::
          {:ok, any()} | {:error, atom()}
  def read_resource_secure(session, resource_uri, capability) do
    with :ok <- validate_resource_permission(capability, :read, resource_uri),
         {:ok, content} <- execute_mcp_read_resource(session, resource_uri) do
      # Log successful read
      Security.log_security_event(:mcp_resource_read, %{
        resource_uri: resource_uri,
        capability_id: capability.id
      })

      {:ok, content}
    else
      {:error, reason} = error ->
        # Log security violation
        Security.log_security_event(:mcp_resource_read_denied, %{
          resource_uri: resource_uri,
          capability_id: capability.id,
          reason: reason
        })

        error
    end
  end

  @doc """
  Creates a temporary capability for MCP tool execution.

  This is a convenience function for creating short-lived capabilities
  for specific MCP operations.

  ## Parameters
  - `tool_name`: Name of the tool
  - `constraints`: Additional constraints for the capability
  - `duration_seconds`: How long the capability should be valid

  ## Returns
  - `{:ok, capability}` on success
  - `{:error, reason}` on failure
  """
  @spec create_tool_capability(tool_name(), map(), non_neg_integer()) ::
          {:ok, Capability.t()} | {:error, atom()}
  def create_tool_capability(tool_name, constraints \\ %{}, duration_seconds \\ 300) do
    tool_constraints =
      Map.merge(constraints, %{
        allowed_tools: [tool_name],
        operations: [:execute]
      })

    Security.request_temporary_capability(:mcp_tool, tool_constraints, duration_seconds)
  end

  @doc """
  Creates a filesystem access capability for MCP filesystem operations.

  ## Parameters
  - `allowed_paths`: List of allowed filesystem paths
  - `operations`: List of allowed operations (:read, :write, :execute)
  - `duration_seconds`: How long the capability should be valid

  ## Returns
  - `{:ok, capability}` on success
  - `{:error, reason}` on failure
  """
  @spec create_filesystem_capability([String.t()], [atom()], non_neg_integer()) ::
          {:ok, Capability.t()} | {:error, atom()}
  def create_filesystem_capability(allowed_paths, operations, duration_seconds \\ 3600) do
    constraints = %{
      paths: allowed_paths,
      operations: operations
    }

    Security.request_temporary_capability(:filesystem, constraints, duration_seconds)
  end

  @doc """
  Validates that a principal has permission to execute an MCP tool.

  This is a convenience function that checks existing capabilities
  without requiring a specific capability to be passed.

  ## Parameters
  - `principal_id`: The principal requesting access
  - `tool_name`: Name of the tool to execute
  - `args`: Arguments for the tool

  ## Returns
  - `:ok` if permission is granted
  - `{:error, reason}` if permission is denied
  """
  @spec check_tool_permission(String.t(), tool_name(), tool_args()) ::
          :ok | {:error, atom()}
  def check_tool_permission(principal_id, tool_name, args) do
    # Extract resource information from tool args for validation
    resource = extract_resource_from_args(tool_name, args)
    operation = get_operation_for_tool(tool_name)

    Security.check_permission(principal_id, :mcp_tool, operation, resource)
  end

  @doc """
  Wraps an MCP session with security context.

  This function sets up the security context for an entire MCP session,
  establishing the principal identity and available capabilities.

  ## Parameters
  - `session`: The MCP session
  - `principal_id`: The principal identity for this session
  - `capabilities`: List of capabilities available to this session
  - `fun`: Function to execute in the security context

  ## Returns
  - The result of the function execution
  """
  @spec with_secure_mcp_context(mcp_session(), String.t(), [Capability.t()], (-> any())) ::
          any()
  def with_secure_mcp_context(session, principal_id, capabilities, fun) do
    # Set up security context
    Security.set_current_principal(principal_id)

    Security.with_capabilities(capabilities, fun)
  end

  ## Private Functions

  defp validate_inputs(session, tool_name, args) do
    cond do
      is_nil(session) -> {:error, :invalid_session}
      is_nil(tool_name) or tool_name == "" -> {:error, :invalid_tool_name}
      not is_map(args) -> {:error, :invalid_args}
      true -> :ok
    end
  end

  defp validate_tool_permission(capability, tool_name, args) do
    # Check if the capability allows MCP tool execution
    case capability.resource_type do
      :mcp_tool ->
        with :ok <- check_tool_allowed(capability, tool_name),
             :ok <- check_tool_args_allowed(capability, args) do
          # For MCP tools, the resource is the tool name itself
          operation = get_operation_for_tool(tool_name)

          Capability.permits?(capability, operation, tool_name)
        end

      :filesystem when tool_name in ["read_file", "write_file", "list_directory"] ->
        # Filesystem tools can use filesystem capabilities
        resource = extract_filesystem_resource(args)
        operation = get_filesystem_operation(tool_name)

        Capability.permits?(capability, operation, resource)

      _ ->
        {:error, :capability_resource_type_mismatch}
    end
  end

  defp validate_resource_permission(capability, operation, resource_uri) do
    case capability.resource_type do
      :mcp_tool ->
        Capability.permits?(capability, operation, resource_uri)

      :filesystem ->
        # For filesystem resources, extract the actual path
        path = extract_path_from_uri(resource_uri)
        Capability.permits?(capability, operation, path)

      _ ->
        {:error, :capability_resource_type_mismatch}
    end
  end

  defp check_tool_allowed(capability, tool_name) do
    # Ensure constraints is a map
    if is_map(capability.constraints) do
      case Map.get(capability.constraints, :allowed_tools) do
        # No tool restrictions
        nil ->
          :ok

        allowed_tools when is_list(allowed_tools) ->
          if tool_name in allowed_tools do
            :ok
          else
            {:error, :tool_not_allowed}
          end

        _ ->
          {:error, :invalid_tool_constraint}
      end
    else
      {:error, :invalid_constraints}
    end
  end

  defp check_tool_args_allowed(capability, args) do
    # Basic validation of tool arguments
    # Could be extended to validate specific argument constraints
    if is_map(args) do
      :ok
    else
      {:error, :invalid_tool_args}
    end
  end

  defp extract_resource_from_args(tool_name, args) do
    case tool_name do
      "read_file" -> Map.get(args, "path", "unknown")
      "write_file" -> Map.get(args, "path", "unknown")
      "list_directory" -> Map.get(args, "path", "unknown")
      "execute_command" -> Map.get(args, "command", "unknown")
      _ -> "#{tool_name}:unknown"
    end
  end

  defp extract_filesystem_resource(args) do
    Map.get(args, "path", "unknown")
  end

  defp extract_path_from_uri("file://" <> path), do: path
  defp extract_path_from_uri(uri), do: uri

  defp get_operation_for_tool(tool_name) do
    case tool_name do
      "read_file" -> :read
      "write_file" -> :write
      "list_directory" -> :list
      "execute_command" -> :execute
      _ -> :execute
    end
  end

  defp get_filesystem_operation(tool_name) do
    case tool_name do
      "read_file" -> :read
      "write_file" -> :write
      "list_directory" -> :list
      _ -> :read
    end
  end

  defp execute_mcp_tool(session, tool_name, args) do
    # This would integrate with the actual MCP client
    # For now, we'll simulate the call
    Logger.info("Executing MCP tool", tool: tool_name, session: inspect(session))

    # In reality, this would call:
    # ExMCP.call_tool(session, tool_name, args)
    {:ok, %{result: "tool_executed", tool: tool_name, args: args}}
  end

  defp execute_mcp_read_resource(session, resource_uri) do
    # This would integrate with the actual MCP client
    # For now, we'll simulate the call
    Logger.info("Reading MCP resource", resource: resource_uri, session: inspect(session))

    # In reality, this would call:
    # ExMCP.read_resource(session, resource_uri)
    {:ok, %{content: "resource_content", uri: resource_uri}}
  end

  defp sanitize_args(args) when is_map(args) do
    # Remove sensitive information from args for logging
    args
    |> Map.drop(["password", "token", "secret", "key"])
    |> Enum.map(fn {k, v} ->
      {k, if(is_binary(v) and String.length(v) > 100, do: String.slice(v, 0, 100) <> "...", else: v)}
    end)
    |> Map.new()
  end

  defp sanitize_args(args), do: args
end
