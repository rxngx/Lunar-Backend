defmodule LunarWeb.CloudStorageController do
  use LunarWeb, :controller

  @cloudstorage_dir Path.join([:code.priv_dir(:lunar), "static", "cloudstorage"])
  @client_settings_dir Path.join(System.get_env("LOCALAPPDATA") || System.tmp_dir!(), "LunarServer/ClientSettings")

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp ensure_client_settings_dir do
    File.mkdir_p!(@client_settings_dir)
  end

  # Extract the Changelist (build ID) from the User-Agent header.
  # UA format: "Fortnite/++Fortnite+Release-X.XX-CL-XXXXXXX ..."
  defp get_cl(conn) do
    ua = get_req_header(conn, "user-agent") |> List.first() || ""

    cond do
      Regex.match?(~r/-CL-(\d+)/i, ua) ->
        [_, cl] = Regex.run(~r/-CL-(\d+)/i, ua)
        cl

      Regex.match?(~r/-(\d+)[,\s]/i, ua) ->
        [_, cl] = Regex.run(~r/-(\d+)[,\s]/i, ua)
        cl

      true ->
        "unknown"
    end
  end

  # Extract build number (e.g. "23.10") from UA for version-specific logic.
  defp get_build(conn) do
    ua = get_req_header(conn, "user-agent") |> List.first() || ""

    case Regex.run(~r/Release-(\d+\.\d+)/i, ua) do
      [_, build] -> String.to_float(build)
      _ -> 0.0
    end
  end

  defp get_season(conn) do
    build = get_build(conn)
    trunc(build)
  end

  # Compute SHA-1 / SHA-256 and byte length for a binary value.
  defp file_metadata(content) when is_binary(content) do
    %{
      hash: :crypto.hash(:sha, content) |> Base.encode16(case: :lower),
      hash256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
      length: byte_size(content)
    }
  end

  # ---------------------------------------------------------------------------
  # GET /fortnite/api/cloudstorage/system
  # Returns the list of available system .ini files with metadata.
  # ---------------------------------------------------------------------------
  def system_list(conn, _params) do
    build = get_build(conn)

    # Builds 9.40–10.40 don't support system cloud storage
    if build >= 9.40 and build <= 10.40 do
      conn |> put_status(404) |> text("")
    else
      files =
        @cloudstorage_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".ini"))
        |> Enum.map(fn name ->
          path = Path.join(@cloudstorage_dir, name)
          content = File.read!(path)
          stat = File.stat!(path)
          meta = file_metadata(content)

          %{
            "uniqueFilename" => name,
            "filename" => name,
            "hash" => meta.hash,
            "hash256" => meta.hash256,
            "length" => meta.length,
            "contentType" => "application/octet-stream",
            "uploaded" => stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601(),
            "storageType" => "S3",
            "storageIds" => %{},
            "doNotCache" => true
          }
        end)

      conn |> put_status(200) |> json(files)
    end
  end

  # ---------------------------------------------------------------------------
  # GET /fortnite/api/cloudstorage/system/:filename
  # Serves a specific system .ini file, with version-specific patches applied.
  # ---------------------------------------------------------------------------
  def system_file(conn, %{"filename" => filename}) do
    path = Path.join(@cloudstorage_dir, filename)

    if File.exists?(path) do
      content = File.read!(path)
      build = get_build(conn)
      season = get_season(conn)

      # Patch DefaultEngine.ini: disable encryption on season 23+
      content =
        if filename == "DefaultEngine.ini" and season >= 23 do
          content <> "\n[ConsoleVariables]\nnet.AllowEncryption=0\n"
        else
          content
        end

      # Patch DefaultRuntimeOptions.ini: disable direct lobby load on certain builds
      content =
        if filename == "DefaultRuntimeOptions.ini" and build >= 17.50 and build <= 19.30 do
          content <> "\nbLoadDirectlyIntoLobby=false\n"
        else
          content
        end

      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_status(200)
      |> text(content)
    else
      conn |> put_status(200) |> text("")
    end
  end

  # ---------------------------------------------------------------------------
  # GET /fortnite/api/cloudstorage/user/:accountId
  # Returns the metadata list of saved ClientSettings for the current build.
  # ---------------------------------------------------------------------------
  def user_list(conn, %{"accountId" => account_id}) do
    ensure_client_settings_dir()

    cl = get_cl(conn)
    file_path = Path.join(@client_settings_dir, "ClientSettings-#{cl}.Sav")

    if File.exists?(file_path) do
      content = File.read!(file_path)
      stat = File.stat!(file_path)
      meta = file_metadata(content)

      result = [
        %{
          "uniqueFilename" => "ClientSettings.Sav",
          "filename" => "ClientSettings.Sav",
          "hash" => meta.hash,
          "hash256" => meta.hash256,
          "length" => meta.length,
          "contentType" => "application/octet-stream",
          "uploaded" =>
            stat.mtime
            |> NaiveDateTime.from_erl!()
            |> DateTime.from_naive!("Etc/UTC")
            |> DateTime.to_iso8601(),
          "storageType" => "S3",
          "storageIds" => %{},
          "accountId" => account_id,
          "doNotCache" => true
        }
      ]

      conn |> put_status(200) |> json(result)
    else
      conn |> put_status(200) |> json([])
    end
  end

  # ---------------------------------------------------------------------------
  # GET /fortnite/api/cloudstorage/user/:accountId/:file
  # Serves the saved ClientSettings binary for the current build.
  # ---------------------------------------------------------------------------
  def user_file(conn, %{"file" => file}) do
    ensure_client_settings_dir()

    unless String.downcase(file) == "clientsettings.sav" do
      conn
      |> put_status(404)
      |> json(%{"error" => "file not found"})
    else
      cl = get_cl(conn)
      file_path = Path.join(@client_settings_dir, "ClientSettings-#{cl}.Sav")

      conn = put_resp_content_type(conn, "application/octet-stream")

      if File.exists?(file_path) do
        content = File.read!(file_path)
        conn |> put_status(200) |> send_resp(200, content)
      else
        conn |> put_status(200) |> send_resp(200, "")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PUT /fortnite/api/cloudstorage/user/:accountId/ClientSettings.Sav
  # Saves the raw binary ClientSettings for the current build.
  # ---------------------------------------------------------------------------
  def user_file_put(conn, %{"file" => file}) do
    ensure_client_settings_dir()

    unless String.downcase(file) == "clientsettings.sav" do
      conn
      |> put_status(404)
      |> json(%{"error" => "file not found"})
    else
      cl = get_cl(conn)
      file_path = Path.join(@client_settings_dir, "ClientSettings-#{cl}.Sav")

      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 10_000_000)

      File.write!(file_path, body)

      conn |> put_status(204) |> text("")
    end
  end
end
