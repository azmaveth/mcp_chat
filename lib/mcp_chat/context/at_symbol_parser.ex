defmodule MCPChat.Context.AtSymbolParser do
  @moduledoc """
  Parser for @ symbol context inclusion syntax.

  Supports:
  - @resource:name or @r:name - Include MCP resource content
  - @prompt:name or @p:name - Execute MCP prompt and include result
  - @tool:name or @t:name - Execute tool and include output
  - @file:path or @f:path - Include local file content
  - @url:address or @u:address - Fetch and include web content
  """

  @type reference_type :: :resource | :prompt | :tool | :file | :url

  @type at_reference :: %{
          type: reference_type(),
          identifier: String.t(),
          full_match: String.t(),
          start_pos: non_neg_integer(),
          end_pos: non_neg_integer()
        }

  @doc """
  Parse text for @ symbol references.

  Returns a list of references found in the text.
  """
  @spec parse(String.t()) :: [at_reference()]
  def parse(text) when is_binary(text) do
    # Regex to match @ symbol patterns
    # Supports: @type:identifier, @t:identifier (short form)
    regex = ~r/@(resource|prompt|tool|file|url|r|p|t|f|u):([^\s@]+)/

    Regex.scan(regex, text, return: :index)
    |> Enum.map(fn matches ->
      [{full_start, full_length} | type_and_id] = matches
      full_match = String.slice(text, full_start, full_length)

      # Extract type and identifier from the match
      {type_match, identifier_match} =
        case type_and_id do
          [{type_start, type_length}, {id_start, id_length}] ->
            type_str = String.slice(text, type_start, type_length)
            id_str = String.slice(text, id_start, id_length)
            {type_str, id_str}

          _ ->
            # Fallback parsing if regex groups don't work as expected
            [_, type_str, id_str] = String.split(full_match, ["@", ":"], parts: 3)
            {type_str, id_str}
        end

      %{
        type: normalize_type(type_match),
        identifier: identifier_match,
        full_match: full_match,
        start_pos: full_start,
        end_pos: full_start + full_length
      }
    end)
    |> Enum.sort_by(& &1.start_pos)
  end

  @doc """
  Remove @ references from text, optionally replacing with placeholders.
  """
  @spec remove_references(String.t(), [at_reference()], String.t() | nil) :: String.t()
  def remove_references(text, references, replacement \\ nil) do
    # Sort references by position in reverse order to maintain indices
    references
    |> Enum.sort_by(& &1.start_pos, :desc)
    |> Enum.reduce(text, fn ref, acc ->
      before = String.slice(acc, 0, ref.start_pos)
      after_pos = ref.start_pos + String.length(ref.full_match)
      after_text = String.slice(acc, after_pos..-1//1)

      replacement_text = replacement || ""
      before <> replacement_text <> after_text
    end)
  end

  @doc """
  Extract unique identifiers for a specific reference type.
  """
  @spec extract_identifiers([at_reference()], reference_type()) :: [String.t()]
  def extract_identifiers(references, type) do
    references
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.identifier)
    |> Enum.uniq()
  end

  @doc """
  Validate @ reference syntax.
  """
  @spec validate_reference(String.t()) :: {:ok, at_reference()} | {:error, String.t()}
  def validate_reference(ref_text) do
    case parse(ref_text) do
      [reference] ->
        validate_single_reference(reference)

      [] ->
        {:error, "No valid @ reference found"}

      _multiple ->
        {:error, "Multiple @ references found, expected single reference"}
    end
  end

  defp validate_single_reference(reference) do
    with :ok <- validate_identifier(reference.identifier),
         :ok <- validate_reference_type(reference) do
      {:ok, reference}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_identifier(identifier) do
    if String.trim(identifier) == "" do
      {:error, "Empty identifier in @ reference"}
    else
      :ok
    end
  end

  defp validate_reference_type(reference) do
    case reference.type do
      :file ->
        if valid_file_path?(reference.identifier) do
          :ok
        else
          {:error, "Invalid file path in @ reference"}
        end

      :url ->
        if valid_url?(reference.identifier) do
          :ok
        else
          {:error, "Invalid URL in @ reference"}
        end

      _ ->
        :ok
    end
  end

  @doc """
  Get suggestions for @ symbol completion.
  """
  @spec get_completion_suggestions(String.t()) :: [String.t()]
  # Completion suggestion mappings
  @completion_prefixes %{
    ["@r", "@resource"] => ["@resource:", "@r:"],
    ["@p", "@prompt"] => ["@prompt:", "@p:"],
    ["@t", "@tool"] => ["@tool:", "@t:"],
    ["@f", "@file"] => ["@file:", "@f:"],
    ["@u", "@url"] => ["@url:", "@u:"]
  }

  @all_completions ["@resource:", "@r:", "@prompt:", "@p:", "@tool:", "@t:", "@file:", "@f:", "@url:", "@u:"]

  def get_completion_suggestions(partial) do
    cond do
      String.starts_with?(partial, "@") and String.length(partial) == 1 ->
        @all_completions

      String.starts_with?(partial, "@") ->
        find_matching_completions(partial)

      true ->
        []
    end
  end

  defp find_matching_completions(partial) do
    @completion_prefixes
    |> Enum.find_value([], fn {prefixes, completions} ->
      if Enum.any?(prefixes, &String.starts_with?(partial, &1)) do
        completions
      end
    end)
  end

  # Private functions

  defp normalize_type("resource"), do: :resource
  defp normalize_type("r"), do: :resource
  defp normalize_type("prompt"), do: :prompt
  defp normalize_type("p"), do: :prompt
  defp normalize_type("tool"), do: :tool
  defp normalize_type("t"), do: :tool
  defp normalize_type("file"), do: :file
  defp normalize_type("f"), do: :file
  defp normalize_type("url"), do: :url
  defp normalize_type("u"), do: :url
  defp normalize_type(_), do: :unknown

  defp valid_file_path?(path) do
    # Basic file path validation
    String.length(path) > 0 and
      not String.contains?(path, ["<", ">", "|", "\"", "\0"]) and
      not String.starts_with?(path, " ") and
      not String.ends_with?(path, " ")
  end

  defp valid_url?(url) do
    # Basic URL validation
    String.starts_with?(url, ["http://", "https://", "ftp://", "ftps://"]) and
      String.length(url) > 7
  end
end
