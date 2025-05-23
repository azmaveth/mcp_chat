defmodule MCPChat.MCP.Protocol do
  @moduledoc """
  MCP protocol message encoding and decoding.
  Implements the Model Context Protocol specification.
  """

  @protocol_version "2_024-11-05"

  # Message Types
  def encode_initialize(client_info) do
    %{
      jsonrpc: "2.0",
      method: "initialize",
      params: %{
        protocolVersion: @protocol_version,
        capabilities: %{
          roots: %{},
          sampling: %{}
        },
        clientInfo: client_info
      },
      id: generate_id()
    }
  end

  def encode_initialized() do
    %{
      jsonrpc: "2.0",
      method: "notifications/initialized",
      params: %{}
    }
  end

  def encode_list_tools() do
    %{
      jsonrpc: "2.0",
      method: "tools/list",
      params: %{},
      id: generate_id()
    }
  end

  def encode_call_tool(name, arguments) do
    %{
      jsonrpc: "2.0",
      method: "tools/call",
      params: %{
        name: name,
        arguments: arguments
      },
      id: generate_id()
    }
  end

  def encode_list_resources() do
    %{
      jsonrpc: "2.0",
      method: "resources/list",
      params: %{},
      id: generate_id()
    }
  end

  def encode_read_resource(uri) do
    %{
      jsonrpc: "2.0",
      method: "resources/read",
      params: %{
        uri: uri
      },
      id: generate_id()
    }
  end

  def encode_list_prompts() do
    %{
      jsonrpc: "2.0",
      method: "prompts/list",
      params: %{},
      id: generate_id()
    }
  end

  def encode_get_prompt(name, arguments \\ %{}) do
    %{
      jsonrpc: "2.0",
      method: "prompts/get",
      params: %{
        name: name,
        arguments: arguments
      },
      id: generate_id()
    }
  end

  def encode_complete(ref, params) do
    %{
      jsonrpc: "2.0",
      method: "completion/complete",
      params: Map.merge(%{ref: ref}, params),
      id: generate_id()
    }
  end

  # Response parsing
  def parse_response(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> parse_response(decoded)
      error -> error
    end
  end

  def parse_response(%{"jsonrpc" => "2.0", "method" => method, "params" => params}) do
    {:notification, method, params}
  end

  def parse_response(%{"jsonrpc" => "2.0", "result" => result, "id" => id}) do
    {:result, result, id}
  end

  def parse_response(%{"jsonrpc" => "2.0", "error" => error, "id" => id}) do
    {:error, error, id}
  end

  def parse_response(_), do: {:error, :invalid_response}

  # Helpers
  defp generate_id() do
    System.unique_integer([:positive, :monotonic])
  end

  def encode_message(message) do
    Jason.encode!(message)
  end
end
