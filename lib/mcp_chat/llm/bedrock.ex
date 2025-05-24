defmodule MCPChat.LLM.Bedrock do
  @moduledoc """
  AWS Bedrock adapter for multiple LLM providers.
  Supports Claude, Titan, Llama, Cohere, and others through Bedrock.
  """
  @behaviour MCPChat.LLM.Adapter

  require Logger

  @default_region "us-east-1"

  # Model ID mappings for different providers
  @model_mappings %{
    # Anthropic
    "claude-instant-v1" => "anthropic.claude-instant-v1",
    "claude-v2" => "anthropic.claude-v2",
    "claude-v2.1" => "anthropic.claude-v2:1",
    "claude-3-sonnet" => "anthropic.claude-3-sonnet-20240229-v1:0",
    "claude-3-haiku" => "anthropic.claude-3-haiku-20240307-v1:0",
    # Amazon
    "titan-lite" => "amazon.titan-text-lite-v1",
    "titan-express" => "amazon.titan-text-express-v1",
    # Meta
    "llama2-13b" => "meta.llama2-13b-chat-v1",
    "llama2-70b" => "meta.llama2-70b-chat-v1",
    # Cohere
    "command" => "cohere.command-text-v14",
    "command-light" => "cohere.command-light-text-v14",
    # AI21
    "jurassic-2-mid" => "ai21.j2-mid-v1",
    "jurassic-2-ultra" => "ai21.j2-ultra-v1",
    # Mistral
    "mistral-7b" => "mistral.mistral-7b-instruct-v0:2",
    "mixtral-8x7b" => "mistral.mixtral-8x7b-instruct-v0:1"
  }

  @impl true
  def chat(messages, options \\ []) do
    with {:ok, client} <- get_bedrock_client(),
         {:ok, model_id} <- get_model_id(options),
         {:ok, request_body} <- build_request_body(model_id, messages, options),
         {:ok, response} <- invoke_model(client, model_id, request_body) do
      parse_response(model_id, response)
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    with {:ok, client} <- get_bedrock_client(),
         {:ok, model_id} <- get_model_id(options),
         {:ok, request_body} <- build_request_body(model_id, messages, options) do
      stream_model(client, model_id, request_body)
    end
  end

  @impl true
  def configured? do
    case get_aws_credentials() do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def default_model() do
    config = get_config()
    config[:model] || "claude-3-sonnet"
  end

  @impl true
  def list_models() do
    # List available models from Bedrock
    with {:ok, client} <- get_bedrock_client() do
      case list_foundation_models(client) do
        {:ok, models} -> {:ok, format_model_list(models)}
        error -> error
      end
    end
  end

  # Private functions

  defp get_config() do
    MCPChat.Config.get([:llm, :bedrock]) || %{}
  end

  defp get_aws_credentials() do
    config = get_config()

    cond do
      # Check for explicit credentials in config
      config[:access_key_id] && config[:secret_access_key] ->
        {:ok,
         %{
           access_key_id: config[:access_key_id],
           secret_access_key: config[:secret_access_key],
           session_token: config[:session_token]
         }}

      # Check environment variables
      System.get_env("AWS_ACCESS_KEY_ID") && System.get_env("AWS_SECRET_ACCESS_KEY") ->
        {:ok,
         %{
           access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
           secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
           session_token: System.get_env("AWS_SESSION_TOKEN")
         }}

      # Check for profile
      profile = config[:profile] || System.get_env("AWS_PROFILE") ->
        load_profile_credentials(profile)

      # Try to use IAM role or instance credentials
      true ->
        load_instance_credentials()
    end
  end

  defp get_bedrock_client() do
    config = get_config()
    region = config[:region] || System.get_env("AWS_REGION") || @default_region

    case get_aws_credentials() do
      {:ok, credentials} ->
        client =
          AWS.Client.create(
            credentials.access_key_id,
            credentials.secret_access_key,
            credentials.session_token,
            region
          )

        {:ok, client}

      error ->
        error
    end
  end

  defp get_model_id(options) do
    config = get_config()
    model = Keyword.get(options, :model, config[:model] || default_model())

    # Map friendly names to Bedrock model IDs
    model_id = Map.get(@model_mappings, model, model)
    {:ok, model_id}
  end

  defp build_request_body(model_id, messages, options) do
    # Different providers have different request formats
    provider = get_provider_from_model_id(model_id)

    body =
      case provider do
        "anthropic" ->
          build_anthropic_request(messages, options)

        "amazon" ->
          build_titan_request(messages, options)

        "meta" ->
          build_llama_request(messages, options)

        "cohere" ->
          build_cohere_request(messages, options)

        _ ->
          {:error, "Unsupported model provider: #{provider}"}
      end

    case body do
      {:error, _} = error -> error
      body -> {:ok, Jason.encode!(body)}
    end
  end

  defp get_provider_from_model_id(model_id) do
    model_id
    |> String.split(".")
    |> hd()
  end

  defp build_anthropic_request(messages, options) do
    %{
      messages: format_messages_for_anthropic(messages),
      max_tokens: Keyword.get(options, :max_tokens, 4_096),
      temperature: Keyword.get(options, :temperature, 0.7),
      anthropic_version: "bedrock-2023-05-31"
    }
  end

  defp build_titan_request(messages, options) do
    %{
      inputText: messages_to_text(messages),
      textGenerationConfig: %{
        maxTokenCount: Keyword.get(options, :max_tokens, 4_096),
        temperature: Keyword.get(options, :temperature, 0.7),
        topP: Keyword.get(options, :top_p, 0.9)
      }
    }
  end

  defp build_llama_request(messages, options) do
    %{
      prompt: format_llama_prompt(messages),
      max_gen_len: Keyword.get(options, :max_tokens, 512),
      temperature: Keyword.get(options, :temperature, 0.7),
      top_p: Keyword.get(options, :top_p, 0.9)
    }
  end

  defp build_cohere_request(messages, options) do
    %{
      prompt: messages_to_text(messages),
      max_tokens: Keyword.get(options, :max_tokens, 1_000),
      temperature: Keyword.get(options, :temperature, 0.7)
    }
  end

  defp format_messages_for_anthropic(messages) do
    messages
    |> Enum.map(fn msg ->
      %{
        role: msg["role"],
        content: msg["content"]
      }
    end)
  end

  defp messages_to_text(messages) do
    messages
    |> Enum.map(fn msg ->
      "#{String.capitalize(msg["role"])}: #{msg["content"]}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_llama_prompt(messages) do
    # Llama uses specific prompt format
    messages
    |> Enum.map_join(
      fn msg ->
        case msg["role"] do
          "system" -> "<s>[INST] <<SYS>>\n#{msg["content"]}\n<</SYS>>\n\n"
          "user" -> "#{msg["content"]} [/INST]"
          "assistant" -> " #{msg["content"]} </s><s>[INST] "
        end
      end,
      ""
    )
  end

  defp invoke_model(client, model_id, request_body) do
    # Make the actual Bedrock API call
    case AWS.BedrockRuntime.invoke_model(client, model_id, %{
           "body" => request_body,
           "contentType" => "application/json",
           "accept" => "application/json"
         }) do
      {:ok, response, _http_response} ->
        {:ok, response}

      {:error, {:unexpected_response, %{status_code: status, body: body}}} ->
        Logger.error("Bedrock API error: #{status} - #{body}")
        {:error, "Bedrock API error: #{status}"}

      {:error, reason} ->
        Logger.error("Bedrock API error: #{inspect(reason)}")
        {:error, "Failed to invoke model: #{inspect(reason)}"}
    end
  end

  defp stream_model(client, model_id, request_body) do
    # Create a streaming response
    case AWS.BedrockRuntime.invoke_model_with_response_stream(client, model_id, %{
           "body" => request_body,
           "contentType" => "application/json",
           "accept" => "application/json"
         }) do
      {:ok, response_stream, _http_response} ->
        # Transform AWS stream to our format
        stream =
          Stream.map(response_stream, fn chunk ->
            parse_streaming_chunk(model_id, chunk)
          end)
          |> Stream.filter(&(&1 != nil))

        {:ok, stream}

      {:error, reason} ->
        Logger.error("Bedrock streaming error: #{inspect(reason)}")
        {:error, "Failed to stream model: #{inspect(reason)}"}
    end
  end

  defp parse_response(model_id, response) do
    provider = get_provider_from_model_id(model_id)

    # Parse the response body
    case Jason.decode(response["body"]) do
      {:ok, body} ->
        content =
          case provider do
            "anthropic" ->
              # Anthropic format
              body["content"] |> List.first() |> Map.get("text", "")

            "amazon" ->
              # Titan format
              body["results"] |> List.first() |> Map.get("outputText", "")

            "meta" ->
              # Llama format
              body["generation"]

            "cohere" ->
              # Cohere format
              body["generations"] |> List.first() |> Map.get("text", "")

            _ ->
              # Try to find common fields
              body["text"] || body["content"] || body["output"] || ""
          end

        {:ok, content}

      {:error, reason} ->
        Logger.error("Failed to parse Bedrock response: #{inspect(reason)}")
        {:error, "Failed to parse response"}
    end
  end

  defp parse_streaming_chunk(model_id, chunk) do
    provider = get_provider_from_model_id(model_id)

    case Jason.decode(chunk) do
      {:ok, data} ->
        case provider do
          "anthropic" ->
            # Parse Anthropic streaming format
            if data["type"] == "content_block_delta" do
              %{
                delta: data["delta"]["text"],
                finish_reason: nil
              }
            else
              %{
                delta: "",
                finish_reason: data["type"]
              }
            end

          "amazon" ->
            # Parse Titan streaming format
            %{
              delta: data["outputText"] || "",
              finish_reason: if(data["completionReason"], do: "stop", else: nil)
            }

          _ ->
            # Generic streaming format
            %{
              delta: data["text"] || data["content"] || "",
              finish_reason: data["finish_reason"]
            }
        end

      {:error, _} ->
        nil
    end
  end

  defp list_foundation_models(client) do
    # Call Bedrock ListFoundationModels API
    case AWS.Bedrock.list_foundation_models(client, %{}) do
      {:ok, response, _http_response} ->
        models =
          response["modelSummaries"]
          |> Enum.map(fn model ->
            %{
              id: model["modelId"],
              name: model["modelName"],
              provider: model["providerName"]
            }
          end)

        {:ok, models}

      {:error, _reason} ->
        # Fallback to known models if API fails
        models =
          @model_mappings
          |> Enum.map(fn {friendly_name, model_id} ->
            %{
              id: model_id,
              name: friendly_name,
              provider: get_provider_from_model_id(model_id)
            }
          end)

        {:ok, models}
    end
  end

  defp format_model_list(models) do
    models
    |> Enum.map(fn model ->
      %{
        id: model.name,
        name: "#{model.name} (#{model.provider})"
      }
    end)
  end

  defp load_profile_credentials(profile) do
    # Load from ~/.aws/credentials
    credentials_path = Path.expand("~/.aws/credentials")

    if File.exists?(credentials_path) do
      case File.read(credentials_path) do
        {:ok, content} ->
          parse_aws_credentials_file(content, profile)

        {:error, _} ->
          {:error, "Failed to read AWS credentials file"}
      end
    else
      {:error, "AWS credentials file not found"}
    end
  end

  defp load_instance_credentials() do
    # Try EC2 instance metadata service
    metadata_url = "http://169.254.169.254/latest/meta-data/iam/security-credentials/"

    case Req.get(metadata_url, receive_timeout: 1_000) do
      {:ok, %{status: 200, body: role_name}} ->
        # Get credentials for the role
        creds_url = metadata_url <> role_name

        case Req.get(creds_url) do
          {:ok, %{status: 200, body: creds}} ->
            {:ok,
             %{
               access_key_id: creds["AccessKeyId"],
               secret_access_key: creds["SecretAccessKey"],
               session_token: creds["Token"]
             }}

          _ ->
            {:error, "Failed to retrieve instance credentials"}
        end

      _ ->
        # Not on EC2, try ECS task role
        load_ecs_task_credentials()
    end
  end

  defp load_ecs_task_credentials() do
    # Check for ECS task role
    relative_uri = System.get_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

    if relative_uri do
      url = "http://169.254.170.2" <> relative_uri

      case Req.get(url) do
        {:ok, %{status: 200, body: creds}} ->
          {:ok,
           %{
             access_key_id: creds["AccessKeyId"],
             secret_access_key: creds["SecretAccessKey"],
             session_token: creds["Token"]
           }}

        _ ->
          {:error, "Failed to retrieve ECS task credentials"}
      end
    else
      {:error, "No AWS credentials found"}
    end
  end

  defp parse_aws_credentials_file(content, profile) do
    # Simple parser for AWS credentials file
    lines = String.split(content, "\n")
    profile_section = "[#{profile}]"

    case find_profile_section(lines, profile_section) do
      {:ok, section_lines} ->
        access_key = find_credential(section_lines, "aws_access_key_id")
        secret_key = find_credential(section_lines, "aws_secret_access_key")
        session_token = find_credential(section_lines, "aws_session_token")

        if access_key && secret_key do
          {:ok,
           %{
             access_key_id: access_key,
             secret_access_key: secret_key,
             session_token: session_token
           }}
        else
          {:error, "Incomplete credentials for profile #{profile}"}
        end

      :error ->
        {:error, "Profile #{profile} not found"}
    end
  end

  defp find_profile_section(lines, profile_header) do
    case Enum.find_index(lines, &(&1 == profile_header)) do
      nil ->
        :error

      index ->
        # Extract lines until next profile or end
        section_lines =
          lines
          |> Enum.drop(index + 1)
          |> Enum.take_while(&(!String.starts_with?(&1, "[")))

        {:ok, section_lines}
    end
  end

  defp find_credential(lines, key) do
    lines
    |> Enum.find_value(fn line ->
      case String.split(line, "=", parts: 2) do
        [k, v] ->
          if String.trim(k) == key do
            String.trim(v)
          else
            nil
          end

        _ ->
          nil
      end
    end)
  end
end
