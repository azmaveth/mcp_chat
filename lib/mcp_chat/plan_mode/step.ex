defmodule MCPChat.PlanMode.Step do
  @moduledoc """
  Represents a single step in an execution plan.

  Steps can be tool executions, messages, commands, checkpoints, or conditionals.
  Each step includes safety information and rollback capabilities.
  """

  @type step_type :: :tool | :message | :command | :checkpoint | :conditional
  @type risk_level :: :safe | :moderate | :dangerous
  @type status :: :pending | :approved | :executing | :completed | :failed | :skipped | :rolled_back

  @type action :: tool_action() | message_action() | command_action() | checkpoint_action() | conditional_action()

  @type tool_action :: %{
          type: :tool,
          server: String.t(),
          tool_name: String.t(),
          arguments: map()
        }

  @type message_action :: %{
          type: :message,
          content: String.t(),
          model: String.t() | nil
        }

  @type command_action :: %{
          type: :command,
          command: String.t(),
          args: [String.t()],
          working_dir: String.t() | nil
        }

  @type checkpoint_action :: %{
          type: :checkpoint,
          name: String.t(),
          save_state: boolean()
        }

  @type conditional_action :: %{
          type: :conditional,
          condition: String.t(),
          true_step: String.t(),
          false_step: String.t() | nil
        }

  @type rollback_info :: %{
          type: atom(),
          data: map()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          type: step_type(),
          description: String.t(),
          action: action(),
          prerequisites: [String.t()] | nil,
          rollback_info: rollback_info() | nil,
          risk_level: risk_level(),
          estimated_cost: map(),
          status: status(),
          result: any(),
          error: any(),
          metadata: map()
        }

  defstruct [
    :id,
    :type,
    :description,
    :action,
    :prerequisites,
    :rollback_info,
    :risk_level,
    :estimated_cost,
    :status,
    :result,
    :error,
    :metadata
  ]

  @doc """
  Creates a new tool execution step.
  """
  def new_tool(description, server, tool_name, arguments, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      type: :tool,
      description: description,
      action: %{
        type: :tool,
        server: server,
        tool_name: tool_name,
        arguments: arguments
      },
      prerequisites: Keyword.get(opts, :prerequisites),
      rollback_info: Keyword.get(opts, :rollback_info),
      risk_level: assess_tool_risk(tool_name, arguments),
      estimated_cost: estimate_tool_cost(tool_name),
      status: :pending,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a new message step for LLM interaction.
  """
  def new_message(description, content, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      type: :message,
      description: description,
      action: %{
        type: :message,
        content: content,
        model: Keyword.get(opts, :model)
      },
      prerequisites: Keyword.get(opts, :prerequisites),
      # Messages typically can't be rolled back
      rollback_info: nil,
      risk_level: :safe,
      estimated_cost: estimate_message_cost(content, Keyword.get(opts, :model)),
      status: :pending,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a new command execution step.
  """
  def new_command(description, command, args \\ [], opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      type: :command,
      description: description,
      action: %{
        type: :command,
        command: command,
        args: args,
        working_dir: Keyword.get(opts, :working_dir)
      },
      prerequisites: Keyword.get(opts, :prerequisites),
      rollback_info: Keyword.get(opts, :rollback_info),
      risk_level: assess_command_risk(command, args),
      estimated_cost: %{tokens: 0, amount: 0.0},
      status: :pending,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a checkpoint step for saving state.
  """
  def new_checkpoint(name, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      type: :checkpoint,
      description: "Checkpoint: #{name}",
      action: %{
        type: :checkpoint,
        name: name,
        save_state: Keyword.get(opts, :save_state, true)
      },
      prerequisites: Keyword.get(opts, :prerequisites),
      rollback_info: nil,
      risk_level: :safe,
      estimated_cost: %{tokens: 0, amount: 0.0},
      status: :pending,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a conditional step that branches execution.
  """
  def new_conditional(description, condition, true_step, false_step \\ nil, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      type: :conditional,
      description: description,
      action: %{
        type: :conditional,
        condition: condition,
        true_step: true_step,
        false_step: false_step
      },
      prerequisites: Keyword.get(opts, :prerequisites),
      rollback_info: nil,
      risk_level: :safe,
      estimated_cost: %{tokens: 0, amount: 0.0},
      status: :pending,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Updates the step status.
  """
  def update_status(%__MODULE__{} = step, status)
      when status in [:pending, :approved, :executing, :completed, :failed, :skipped, :rolled_back] do
    %{step | status: status}
  end

  @doc """
  Sets the execution result.
  """
  def set_result(%__MODULE__{} = step, result) do
    %{step | result: result, status: :completed}
  end

  @doc """
  Sets an execution error.
  """
  def set_error(%__MODULE__{} = step, error) do
    %{step | error: error, status: :failed}
  end

  @doc """
  Checks if the step is safe to execute.
  """
  def safe?(%__MODULE__{risk_level: :safe}), do: true
  def safe?(_), do: false

  @doc """
  Checks if the step modifies state.
  """
  def modifies_state?(%__MODULE__{type: :message}), do: false
  def modifies_state?(%__MODULE__{type: :checkpoint}), do: false
  def modifies_state?(%__MODULE__{type: :conditional}), do: false

  def modifies_state?(%__MODULE__{type: :tool, action: %{tool_name: tool_name}}) do
    tool_name not in ["list", "read", "get", "search", "query"]
  end

  def modifies_state?(%__MODULE__{type: :command, action: %{command: command}}) do
    command not in ["ls", "cat", "grep", "find", "echo", "pwd"]
  end

  @doc """
  Checks if the step can be rolled back.
  """
  def can_rollback?(%__MODULE__{rollback_info: nil}), do: false
  def can_rollback?(%__MODULE__{rollback_info: _}), do: true

  # Private functions

  defp generate_id do
    "step_#{System.system_time(:millisecond)}_#{:rand.uniform(9999)}"
  end

  defp assess_tool_risk(tool_name, arguments) do
    cond do
      tool_name in ["delete", "remove", "destroy"] -> :dangerous
      tool_name in ["write", "update", "create", "modify"] -> :moderate
      tool_name in ["execute", "run", "eval"] -> assess_execution_risk(arguments)
      true -> :safe
    end
  end

  defp assess_command_risk(command, args) do
    dangerous_commands = ["rm", "del", "format", "dd", "mkfs"]
    moderate_commands = ["mv", "cp", "mkdir", "touch", "chmod", "chown"]

    cond do
      command in dangerous_commands -> :dangerous
      command in moderate_commands -> :moderate
      String.contains?(command, "sudo") -> :dangerous
      Enum.any?(args, &String.contains?(&1, "*")) -> :moderate
      true -> :safe
    end
  end

  defp assess_execution_risk(%{"code" => code}) when is_binary(code) do
    cond do
      String.contains?(code, "File.rm") -> :dangerous
      String.contains?(code, "System.cmd") -> :moderate
      true -> :safe
    end
  end

  defp assess_execution_risk(_), do: :moderate

  defp estimate_tool_cost(tool_name) do
    # Rough estimates based on typical tool usage
    tokens =
      case tool_name do
        "analyze_code" -> 500
        "write_file" -> 100
        "read_file" -> 50
        _ -> 100
      end

    # Rough token pricing
    %{tokens: tokens, amount: tokens * 0.00002}
  end

  defp estimate_message_cost(content, model) do
    # Simple estimation based on content length
    # Input + expected output
    tokens = div(String.length(content), 4) + 500
    rate = if model && String.contains?(model, "gpt-4"), do: 0.00003, else: 0.00002

    %{tokens: tokens, amount: tokens * rate}
  end
end
