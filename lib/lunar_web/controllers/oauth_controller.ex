defmodule LunarWeb.TokenController do
  use LunarWeb, :controller
  alias Lunar.Mongo
  alias Lunar.Database.Tables.{Accounts, Tokens}
  alias Joken
  alias Errors

  @token_expiry 28800
  @refresh_expiry 86400

  def token(conn, %{"grant_type" => grant_type} = params) do
    case grant_type do
      "password" ->
        user = Mongo.find_one(Accounts.collection(), %{email: params["username"]})

        cond do
          is_nil(user) ->
            conn |> put_status(:not_found)
            |> json(Errors.account() |> Map.get(:account_not_found))

          params["password"] != user[:password] ->
            conn |> put_status(:not_found)
            |> json(Errors.account() |> Map.get(:invalid_credentials))

          true ->
            access_token = generate_access_token(user)
            refresh_token = generate_refresh_token(user)

            # Delete old tokens for this account.
            old_tokens = Mongo.find(Tokens.collection(), %{account_id: user[:account_id]})
            Enum.each(old_tokens, fn t -> Mongo.delete_one(Tokens.collection(), %{_id: t[:_id]}) end)

            # Insert new tokens.
            Mongo.insert_one(Tokens.collection(), %{
              account_id: user[:account_id],
              token: access_token,
              type: "access"
            })
            Mongo.insert_one(Tokens.collection(), %{
              account_id: user[:account_id],
              token: refresh_token,
              type: "refresh"
            })

            json(conn, token_response(access_token, refresh_token, user))
        end

      "client_credentials" ->
        claims = %{
          "sub" => params["client_id"],
          "type" => "client_credentials",
          "exp" => DateTime.utc_now() |> DateTime.add(@token_expiry, :second) |> DateTime.to_unix()
        }

        access_token = Joken.generate_and_sign!(claims)

        json(conn, %{
          access_token: access_token,
          expires_in: @token_expiry,
          expires_at: DateTime.utc_now() |> DateTime.add(@token_expiry, :second)
                     |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
          token_type: "bearer",
          client_id: "client_id",
          internal_client: true,
          client_service: "fortnite",
          device_id: UUID.uuid4()
        })

      "refresh_token" ->
        token_doc = Mongo.find_one(Tokens.collection(), %{
          token: params["refresh_token"],
          type: "refresh"
        })

        case token_doc do
          nil ->
            conn |> put_status(:not_found)
            |> json(Errors.authentication().oauth() |> Map.get(:invalid_refresh))

          _ ->
            user = Mongo.find_one(Accounts.collection(), %{account_id: token_doc[:account_id]})

            case user do
              nil ->
                conn |> put_status(:not_found)
                |> json(Errors.account() |> Map.get(:account_not_found))

              _ ->
                access_token = generate_access_token(user)
                refresh_token = generate_refresh_token(user)

                # Delete old refresh token.
                Mongo.delete_one(Tokens.collection(), %{_id: token_doc[:_id]})

                # Insert new tokens.
                Mongo.insert_one(Tokens.collection(), %{
                  account_id: user[:account_id],
                  token: refresh_token,
                  type: "refresh"
                })

                json(conn, token_response(access_token, refresh_token, user))
            end
        end

      "device_auth" ->
        user = Mongo.find_one(Accounts.collection(), %{account_id: params["account_id"]})

        cond do
          is_nil(user) ->
            conn |> put_status(:not_found)
            |> json(Errors.account() |> Map.get(:account_not_found))

          params["secret"] != user[:password] ->
            conn |> put_status(:not_found)
            |> json(Errors.authentication().oauth() |> Map.get(:invalid_refresh))

          true ->
            access_token = generate_access_token(user)

            json(conn, %{
              access_token: access_token,
              expires_in: @token_expiry,
              expires_at: DateTime.utc_now() |> DateTime.add(@token_expiry, :second)
                         |> DateTime.to_iso8601(),
              token_type: "bearer",
              client_id: "client_id",
              internal_client: true,
              client_service: "fortnite",
              device_id: UUID.uuid4(),
              displayName: user[:username]
            })
        end

      _ ->
        conn |> put_status(:bad_request)
        |> json(Errors.authentication() |> Map.get(:wrong_grant_type))
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp generate_access_token(user) do
    claims = %{
      "sub" => user[:email],
      "type" => "access",
      "exp" => DateTime.utc_now() |> DateTime.add(@token_expiry, :second) |> DateTime.to_unix()
    }
    Joken.generate_and_sign!(claims)
  end

  defp generate_refresh_token(user) do
    claims = %{
      "sub" => user[:account_id],
      "exp" => DateTime.utc_now() |> DateTime.add(@refresh_expiry, :second) |> DateTime.to_unix()
    }
    Joken.generate_and_sign!(claims)
  end

  defp token_response(access_token, refresh_token, user) do
    %{
      access_token: access_token,
      expires_in: 28800,
      expires_at: DateTime.utc_now() |> DateTime.add(28800, :second)
                 |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      token_type: "bearer",
      refresh_token: refresh_token,
      refresh_expires: 86400,
      refresh_expires_at: DateTime.utc_now() |> DateTime.add(86400, :second)
                          |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      client_id: "client_id",
      internal_client: true,
      account_id: "#{user[:account_id]}",
      client_service: "fortnite",
      app: "fortnite",
      in_app_id: "#{user[:account_id]}",
      device_id: UUID.uuid4(),
      displayName: user[:username]
    }
  end
end
