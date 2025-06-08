defmodule MCPChat.Types do
  @moduledoc """
  Shared type definitions used across MCPChat modules.

  This module contains struct definitions and types that are used by multiple
  modules, helping to avoid circular dependencies.
  """

  defmodule Session do
    @moduledoc """
    Represents a chat session with conversation history and metadata.
    """
    @enforce_keys [:id, :created_at, :updated_at]
    defstruct [
      :id,
      :llm_backend,
      :messages,
      :context,
      :created_at,
      :updated_at,
      :token_usage,
      :metadata
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            llm_backend: String.t() | nil,
            messages: [message()],
            context: map(),
            created_at: DateTime.t(),
            updated_at: DateTime.t(),
            token_usage: token_usage(),
            metadata: map() | nil
          }

    @type message :: %{
            required(:role) => String.t(),
            required(:content) => String.t(),
            optional(:timestamp) => DateTime.t(),
            optional(atom()) => any()
          }

    @type token_usage :: %{
            input_tokens: non_neg_integer(),
            output_tokens: non_neg_integer()
          }
  end

  defmodule LLMResponse do
    @moduledoc """
    Standard response format from LLM adapters.
    """
    defstruct [:content, :model, :usage, :finish_reason]

    @type t :: %__MODULE__{
            content: String.t(),
            model: String.t() | nil,
            usage: Session.token_usage() | nil,
            finish_reason: String.t() | nil
          }
  end

  defmodule MCPRequest do
    @moduledoc """
    Standard MCP protocol request format.
    """
    defstruct [:id, :method, :params]

    @type t :: %__MODULE__{
            id: String.t() | integer(),
            method: String.t(),
            params: map() | nil
          }
  end

  defmodule MCPResponse do
    @moduledoc """
    Standard MCP protocol response format.
    """
    defstruct [:id, :result, :error]

    @type t :: %__MODULE__{
            id: String.t() | integer(),
            result: any() | nil,
            error: mcp_error() | nil
          }

    @type mcp_error :: %{
            code: integer(),
            message: String.t(),
            data: any() | nil
          }
  end
end
