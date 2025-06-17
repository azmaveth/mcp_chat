defmodule MCPChat.CLI.Alias do
  @moduledoc """
  Alias management CLI commands.

  Handles commands for creating and managing command aliases:
  - Creating new aliases
  - Removing aliases
  - Listing all aliases
  - Executing aliased commands
  """

  use MCPChat.CLI.Base

  alias MCPChat.Alias.ExAliasAdapter, as: Alias

  @impl true
  def commands do
    %{
      "alias" => "Manage command aliases (usage: /alias [add|remove|list] ...)"
    }
  end

  @impl true
  def handle_command("alias", args) do
    handle_alias_command(args)
  end

  def handle_command(cmd, _args) do
    {:error, "Unknown alias command: #{cmd}"}
  end

  # Command implementations

  defp handle_alias_command(args) do
    case args do
      [] ->
        list_aliases()

      ["list"] ->
        list_aliases()

      ["add", name | command_parts] ->
        add_alias(name, command_parts)

      ["remove", name] ->
        remove_alias(name)

      ["rm", name] ->
        remove_alias(name)

      _ ->
        show_error("Usage: /alias [add|remove|list] ...")
        show_info("  /alias list - Show all aliases")
        show_info("  /alias add <name> <command> - Create new alias")
        show_info("  /alias remove <name> - Remove alias")
    end
  end

  defp list_aliases do
    aliases = Alias.list_aliases()

    if Enum.empty?(aliases) do
      show_info("No aliases defined")
      show_info("Create one with: /alias add <name> <command>")
    else
      show_info("Command aliases:")

      aliases
      |> Enum.sort_by(fn %{name: name, commands: _} -> name end)
      |> Enum.each(fn %{name: name, commands: commands} ->
        command_str = Enum.join(commands, " ")
        IO.puts("  #{name} → #{command_str}")
      end)
    end

    :ok
  end

  defp add_alias(name, command_parts) do
    if Enum.empty?(command_parts) do
      show_error("Usage: /alias add <name> <command>")
    else
      command = Enum.join(command_parts, " ")

      case Alias.define_alias(name, [command]) do
        :ok ->
          show_success("Alias created: #{name} → #{command}")

        {:error, msg} when is_binary(msg) ->
          show_error(msg)

        {:error, reason} ->
          show_error("Failed to create alias: #{inspect(reason)}")
      end
    end
  end

  defp remove_alias(name) do
    case Alias.remove_alias(name) do
      :ok ->
        show_success("Alias removed: #{name}")

      {:error, :not_found} ->
        show_error("Alias not found: #{name}")

      {:error, reason} ->
        show_error("Failed to remove alias: #{inspect(reason)}")
    end
  end

  @doc """
  Execute an aliased command.
  This is called from the main command handler when an alias is detected.
  """
  def execute_alias(alias_name, _args) do
    case Alias.expand_alias(alias_name) do
      {:ok, expanded_command} ->
        # The expanded command needs to be handled by the main command router
        {:execute, expanded_command}

      {:error, reason} ->
        show_error("Failed to expand alias: #{inspect(reason)}")
    end
  end
end
