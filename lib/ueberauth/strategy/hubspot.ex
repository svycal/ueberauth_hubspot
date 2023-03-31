defmodule Ueberauth.Strategy.Hubspot do
  @moduledoc """
  Provides the strategy callbacks for hubspot
  """

  use Ueberauth.Strategy,
    default_scope: "oauth"

  alias Ueberauth.Auth.{Credentials, Extra, Info}
  alias Ueberauth.Strategy.Hubspot

  @doc """
  Handles initial request for Salesforce authentication.
  """
  @impl Ueberauth.Strategy
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    params =
      [scope: scopes]
      |> with_optional(:optional_scope, conn)
      |> with_optional(:state, conn)
      |> with_param(:optional_scope, conn)
      |> with_param(:state, conn)
      |> with_state_param(conn)

    opts = oauth_client_options_from_conn(conn)

    redirect!(conn, Hubspot.OAuth.authorize_url!(params, opts))
  end

  @doc """
  Handles the callback after authentication and saves the relevant info into the conn
  """
  @impl Ueberauth.Strategy
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    with {:ok, token} <- fetch_token(conn, code),
         {:ok, info} <- fetch_user(conn, token) do
      conn
      |> put_private(:hs_token, token)
      |> put_private(:hs_info, info)
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  Handles the cleanup after the ueberauth structs have been built with the info set by
  the callback
  """
  @impl Ueberauth.Strategy
  def handle_cleanup!(conn) do
    conn
    |> put_private(:hs_token, nil)
    |> put_private(:hs_info, nil)
  end

  # -- Auth Fillup -- #

  @impl Ueberauth.Strategy
  def credentials(%{private: %{hs_token: token, hs_info: info}}) do
    %Credentials{
      expires: !!token.expires_at,
      expires_at: token.expires_at,
      scopes: info["scopes"],
      refresh_token: token.refresh_token,
      token: token.access_token,
      token_type: token.token_type
    }
  end

  @impl Ueberauth.Strategy
  def extra(%{private: %{hs_info: info}}) do
    %Extra{
      raw_info: %{
        hub_id: maybe_to_string(info["hub_id"])
      }
    }
  end

  @impl Ueberauth.Strategy
  def info(%{private: %{hs_info: info}}) do
    %Info{
      email: info["user"]
    }
  end

  # -- Helpers -- #

  defp with_param(opts, key, conn) do
    if value = conn.params[to_string(key)], do: Keyword.put(opts, key, value), else: opts
  end

  defp with_optional(opts, key, conn) do
    if option(conn, key), do: Keyword.put(opts, key, option(conn, key)), else: opts
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(val), do: to_string(val)

  defp oauth_client_options_from_conn(conn) do
    base_options = [redirect_uri: callback_url(conn)]
    request_options = conn.private[:ueberauth_request_options].options

    case {request_options[:client_id], request_options[:client_secret]} do
      {nil, _} -> base_options
      {_, nil} -> base_options
      {id, secret} -> [client_id: id, client_secret: secret] ++ base_options
    end
  end

  defp fetch_token(conn, code) do
    params = [grant_type: :authorization_code, code: code]
    opts = oauth_client_options_from_conn(conn)

    case Hubspot.OAuth.get_access_token(params, opts) do
      {:ok, token} ->
        {:ok, token}

      {:error, {error_code, error_description}} ->
        set_errors!(conn, [error(error_code, error_description)])
    end
  end

  @base_url "https://api.hubapi.com/oauth/v1/access-tokens/"
  defp fetch_user(conn, %OAuth2.AccessToken{access_token: access_token}) do
    Hubspot.OAuth.client()
    |> OAuth2.Client.get(@base_url <> access_token)
    |> then(fn
      {:ok, %OAuth2.Response{status_code: 401, body: _body}} ->
        set_errors!(conn, [error("token", "unauthorized")])

      {:ok, %OAuth2.Response{status_code: status_code, body: body}} when status_code in 200..399 ->
        {:ok, body}

      {:error, %OAuth2.Error{reason: reason}} ->
        set_errors!(conn, [error("OAuth2", reason)])
    end)
  end
end
