#!/usr/bin/env elixir

# Demo Dynamic MCP Server for E2E Testing
# A server that can add/remove tools dynamically to test notifications

defmodule DemoDynamicServer do
  @moduledoc """
  A demo MCP server that supports dynamic tool management and notifications.
  Used for testing change notifications and progress features.
  """

  use GenServer

  defstruct [:server, :custom_tools, :custom_resources]

  def main(_args) do
    # Start the GenServer to manage state
    {:ok, pid} = GenServer.start_link(__MODULE__, [], name: __MODULE__)

    # Keep the process alive
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end

  @impl true
  def init(_args) do
    # Start the MCP server with notification capabilities
    {:ok, server} =
      ExMCP.Server.start_link(
        name: "demo-dynamic-server",
        version: "1.0.0",
        transport: :stdio,
        capabilities: %{
          tools: true,
          resources: true,
          progress: true,
          notifications: %{
            tools_changed: true,
            resources_changed: true,
            progress: true
          }
        }
      )

    # Register base tools
    register_base_tools(server)

    # Register base resources
    register_base_resources(server)

    state = %__MODULE__{
      server: server,
      custom_tools: %{},
      custom_resources: %{}
    }

    {:ok, state}
  end

  defp register_base_tools(server) do
    # Tool to list dynamic tools
    ExMCP.Server.add_tool(server, %{
      name: "list_dynamic_tools",
      description: "List all dynamically added tools",
      input_schema: %{type: "object", properties: %{}},
      handler: fn _params ->
        GenServer.call(__MODULE__, :list_tools)
      end
    })

    # Tool to add new tools
    ExMCP.Server.add_tool(server, %{
      name: "add_tool",
      description: "Add a new tool dynamically",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "Tool name"},
          description: %{type: "string", description: "Tool description"}
        },
        required: ["name"]
      },
      handler: fn params ->
        GenServer.call(__MODULE__, {:add_tool, params})
      end
    })

    # Tool to remove tools
    ExMCP.Server.add_tool(server, %{
      name: "remove_tool",
      description: "Remove a dynamically added tool",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "Tool name to remove"}
        },
        required: ["name"]
      },
      handler: fn params ->
        GenServer.call(__MODULE__, {:remove_tool, params})
      end
    })

    # Tool for long-running operations
    ExMCP.Server.add_tool(server, %{
      name: "long_running_task",
      description: "Execute a long-running task with progress updates",
      input_schema: %{
        type: "object",
        properties: %{
          duration: %{type: "integer", description: "Duration in seconds", default: 5},
          with_progress: %{type: "boolean", description: "Send progress updates", default: true}
        }
      },
      handler: fn params ->
        GenServer.call(__MODULE__, {:long_task, params}, 30_000)
      end
    })

    # Tool to trigger notifications
    ExMCP.Server.add_tool(server, %{
      name: "trigger_resource_change",
      description: "Trigger a resource change notification",
      input_schema: %{type: "object", properties: %{}},
      handler: fn _params ->
        GenServer.call(__MODULE__, :trigger_resource_change)
      end
    })

    # Server info tool
    ExMCP.Server.add_tool(server, %{
      name: "get_server_info",
      description: "Get information about the server",
      input_schema: %{type: "object", properties: %{}},
      handler: fn _params ->
        GenServer.call(__MODULE__, :get_server_info)
      end
    })
  end

  defp register_base_resources(server) do
    ExMCP.Server.add_resource(server, %{
      uri: "dynamic://status",
      name: "Server Status",
      description: "Current server status and statistics",
      mime_type: "application/json",
      reader: fn -> GenServer.call(__MODULE__, :read_status_resource) end
    })

    ExMCP.Server.add_resource(server, %{
      uri: "dynamic://tools",
      name: "Dynamic Tools List",
      description: "List of all dynamic tools",
      mime_type: "application/json",
      reader: fn -> GenServer.call(__MODULE__, :read_tools_resource) end
    })
  end

  # GenServer callbacks

  @impl true
  def handle_call(:list_tools, _from, state) do
    tools = Map.keys(state.custom_tools)

    result = %{
      "dynamic_tools" => tools,
      "count" => length(tools),
      "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
    }

    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_call({:add_tool, %{"name" => name} = params}, _from, state) do
    if Map.has_key?(state.custom_tools, name) do
      {:reply, {:error, "Tool '#{name}' already exists"}, state}
    else
      description = Map.get(params, "description", "Dynamic tool")

      # Create a dynamic tool handler
      tool_spec = %{
        name: "dynamic_#{name}",
        description: description,
        input_schema: %{
          type: "object",
          properties: %{
            data: %{type: "string", description: "Input data"}
          }
        },
        handler: fn params ->
          {:ok,
           %{
             "tool" => name,
             "input" => params,
             "result" => "Executed #{name} with #{inspect(params)}",
             "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
           }}
        end
      }

      # Add the tool to the server
      ExMCP.Server.add_tool(state.server, tool_spec)

      # Send tools changed notification
      ExMCP.Server.send_notification(state.server, "tools/changed", %{})

      # Update state
      new_state = %{state | custom_tools: Map.put(state.custom_tools, name, tool_spec)}

      result = %{
        "success" => true,
        "tool" => name,
        "message" => "Tool '#{name}' added successfully"
      }

      {:reply, {:ok, result}, new_state}
    end
  end

  @impl true
  def handle_call({:remove_tool, %{"name" => name}}, _from, state) do
    if Map.has_key?(state.custom_tools, name) do
      # Remove the tool from the server
      ExMCP.Server.remove_tool(state.server, "dynamic_#{name}")

      # Send tools changed notification
      ExMCP.Server.send_notification(state.server, "tools/changed", %{})

      # Update state
      new_state = %{state | custom_tools: Map.delete(state.custom_tools, name)}

      result = %{
        "success" => true,
        "tool" => name,
        "message" => "Tool '#{name}' removed successfully"
      }

      {:reply, {:ok, result}, new_state}
    else
      {:reply, {:error, "Tool '#{name}' not found or is not removable"}, state}
    end
  end

  @impl true
  def handle_call({:long_task, params}, _from, state) do
    duration = Map.get(params, "duration", 5)
    with_progress = Map.get(params, "with_progress", true)

    # Simulate long-running task
    if with_progress do
      Enum.each(1..duration, fn i ->
        progress = i / duration

        ExMCP.Server.send_progress(state.server, %{
          progress: progress,
          message: "Processing step #{i} of #{duration}"
        })

        Process.sleep(1_000)
      end)
    else
      Process.sleep(duration * 1_000)
    end

    result = %{
      "completed" => true,
      "duration" => duration,
      "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
    }

    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_call(:trigger_resource_change, _from, state) do
    # Send resource changed notification
    ExMCP.Server.send_notification(state.server, "resources/changed", %{})

    result = %{
      "success" => true,
      "message" => "Resource change notification sent"
    }

    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_call(:get_server_info, _from, state) do
    info = %{
      "name" => "demo-dynamic-server",
      "version" => "1.0.0",
      "capabilities" => %{
        "tools" => %{
          "base_tools" => 6,
          "dynamic_tools" => map_size(state.custom_tools)
        },
        "notifications" => [
          "tools_changed",
          "resources_changed",
          "progress"
        ]
      },
      "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
    }

    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_call(:read_status_resource, _from, state) do
    status =
      Jason.encode!(%{
        "status" => "running",
        "uptime_seconds" => System.monotonic_time(:second),
        "dynamic_tools" => map_size(state.custom_tools),
        "dynamic_resources" => map_size(state.custom_resources)
      })

    {:reply, status, state}
  end

  @impl true
  def handle_call(:read_tools_resource, _from, state) do
    tools =
      Jason.encode!(%{
        "tools" => Map.keys(state.custom_tools)
      })

    {:reply, tools, state}
  end
end

# Start the server
DemoDynamicServer.main(System.argv())
