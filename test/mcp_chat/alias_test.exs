defmodule MCPChat.AliasTest do
  use ExUnit.Case
  alias ExAliasAdapter, as: Alias

  setup do
    # Start ExAlias if not already started
    case Process.whereis(ExAlias) do
      nil -> {:ok, _} = ExAlias.start_link()
      _ -> :ok
    end

    # Start the Alias adapter if not already started
    case Process.whereis(Alias) do
      nil -> {:ok, _} = Alias.start_link()
      _ -> :ok
    end

    # Clean up any existing aliases
    aliases = Alias.list_aliases()

    Enum.each(aliases, fn %{name: name, commands: _commands} ->
      Alias.remove_alias(name)
    end)

    :ok
  end

  describe "define_alias/2" do
    test "defines a simple alias" do
      assert :ok = Alias.define_alias("test", ["/help", "/config"])

      assert {:ok, commands} = Alias.get_alias("test")
      assert commands == ["/help", "/config"]
    end

    test "rejects empty alias name" do
      assert {:error, {:validation_error, {:name, "cannot be empty"}}} =
               Alias.define_alias("", ["/help"])
    end

    test "rejects alias name with spaces" do
      assert {:error, {:validation_error, {:name, "cannot contain spaces"}}} =
               Alias.define_alias("my alias", ["/help"])
    end

    test "rejects reserved command names" do
      assert {:error, {:validation_error, {:name, "cannot override built-in command 'help'"}}} =
               Alias.define_alias("help", ["/config"])
    end

    test "rejects empty command list" do
      assert {:error, {:validation_error, {:commands, "cannot be empty"}}} =
               Alias.define_alias("test", [])
    end

    test "rejects non-string commands" do
      assert {:error, {:validation_error, {:commands, "must all be strings"}}} =
               Alias.define_alias("test", ["/help", 123])
    end
  end

  describe "remove_alias/1" do
    test "removes an existing alias" do
      :ok = Alias.define_alias("test", ["/help"])
      assert :ok = Alias.remove_alias("test")
      assert {:error, _} = Alias.get_alias("test")
    end

    test "returns error for non-existent alias" do
      assert {:error, :not_found} =
               Alias.remove_alias("nonexistent")
    end
  end

  describe "get_alias/1" do
    test "returns alias definition" do
      :ok = Alias.define_alias("test", ["/help", "/config"])

      assert {:ok, ["/help", "/config"]} = Alias.get_alias("test")
    end

    test "returns error for non-existent alias" do
      assert {:error, :not_found} =
               Alias.get_alias("nonexistent")
    end
  end

  describe "list_aliases/0" do
    test "returns empty list when no aliases" do
      assert [] = Alias.list_aliases()
    end

    test "returns all defined aliases sorted by name" do
      :ok = Alias.define_alias("beta", ["/help"])
      :ok = Alias.define_alias("alpha", ["/config"])
      :ok = Alias.define_alias("gamma", ["/servers"])

      aliases = Alias.list_aliases()

      assert length(aliases) == 3

      assert [
               %{name: "alpha", commands: ["/config"]},
               %{name: "beta", commands: ["/help"]},
               %{name: "gamma", commands: ["/servers"]}
             ] = aliases
    end
  end

  describe "expand_alias/1" do
    test "expands simple alias" do
      :ok = Alias.define_alias("test", ["/help", "/config"])

      assert {:ok, ["/help", "/config"]} = Alias.expand_alias("test")
    end

    test "expands nested aliases" do
      :ok = Alias.define_alias("inner", ["/help"])
      :ok = Alias.define_alias("outer", ["inner", "/config"])

      assert {:ok, ["/help", "/config"]} = Alias.expand_alias("outer")
    end

    test "prevents circular references" do
      :ok = Alias.define_alias("a", ["b"])
      :ok = Alias.define_alias("b", ["a"])

      # Should not expand infinitely - when circular reference is detected,
      # it stops expansion and returns the command that would cause the cycle
      assert {:ok, ["a"]} = Alias.expand_alias("a")
      assert {:ok, ["b"]} = Alias.expand_alias("b")
    end

    test "returns error for non-existent alias" do
      assert {:error, :not_found} =
               Alias.expand_alias("nonexistent")
    end
  end

  describe "is_alias?/1" do
    test "returns true for existing alias" do
      :ok = Alias.define_alias("test", ["/help"])
      assert Alias.is_alias?("test")
    end

    test "returns false for non-existent alias" do
      refute Alias.is_alias?("nonexistent")
    end
  end
end
