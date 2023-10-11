defmodule Ueberauth.Strategy.Hubspot.OAuth do
  @moduledoc """
  OAuth2 for Hubspot.
  Add `client_id` and `client_secret` to your configuration:
      config :ueberauth, Ueberauth.Strategy.Hubspot.OAuth,
        client_id: System.get_env("HUBSPOT_APP_ID"),
        client_secret: System.get_env("HUBSPOT_APP_SECRET")
  """
  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    site: "https://app.hubspot.com",
    authorize_url: "/oauth/authorize",
    token_url: "https://api.hubapi.com/oauth/v1/token"
  ]

  @doc """
  Construct a client for requests to Hubspot.
  This will be setup automatically for you in `Ueberauth.Strategy.Hubspot`.
  These options are only useful for usage outside the normal callback phase of Ueberauth.
  """
  def client(opts \\ []) do
    @defaults
    |> Keyword.merge(opts)
    |> Keyword.merge(Application.get_env(:ueberauth, __MODULE__, []))
    |> resolve_values()
    |> OAuth2.Client.new()
    |> OAuth2.Client.put_serializer("application/json", Ueberauth.json_library())
  end


  @impl OAuth2.Strategy
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  @impl OAuth2.Strategy
  def get_token(client, params, headers) do
    client
    |> put_param("client_secret", client.client_secret)
    |> put_header("Accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end

  @doc """
  Provides the authorize url for the request phase of Ueberauth. No need to call this usually.
  """
  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client
    |> OAuth2.Client.authorize_url!(params)
  end


  def get_access_token(params \\ [], opts \\ []) do
    case opts |> client |> OAuth2.Client.get_token(params) do
      {:error, %{body: %{"error" => error, "error_description" => description}}} ->
        {:error, {error, description}}

      {:error, %OAuth2.Error{reason: reason}} ->
        {:error, {:oauth_error, reason}}

      {:ok, %{token: %{access_token: nil} = token}} ->
        %{"error" => error, "error_description" => description} = token.other_params
        {:error, {error, description}}

      {:ok, %{token: token}} ->
        {:ok, token}
    end
  end

  defp resolve_values(list) do
    for {key, value} <- list do
      {key, resolve_value(value)}
    end
  end

  defp resolve_value({m, f, a}) when is_atom(m) and is_atom(f), do: apply(m, f, a)
  defp resolve_value(v), do: v
end
