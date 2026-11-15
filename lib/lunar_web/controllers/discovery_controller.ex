defmodule LunarWeb.DiscoveryController do
  use LunarWeb, :controller

  @discovery_path Path.join(["assets", "discovery_frontend.json"])

  defp load_discovery do
    case File.read(@discovery_path) do
      {:ok, raw} -> Jason.decode!(raw)
      _ -> %{"v1" => %{"Panels" => [], "TestCohorts" => [], "ModeSets" => %{}},
              "v2" => %{"Panels" => []}}
    end
  end

  # ---------------------------------------------------------------------------
  # POST */api/v2/discovery/surface/*  (new versions, v20+)
  # ---------------------------------------------------------------------------
  def surface_v2(conn, _params) do
    discovery = load_discovery()
    conn |> put_status(200) |> json(Map.get(discovery, "v2", %{}))
  end

  # ---------------------------------------------------------------------------
  # POST */discovery/surface/*  (older versions)
  # ---------------------------------------------------------------------------
  def surface_v1(conn, _params) do
    discovery = load_discovery()
    conn |> put_status(200) |> json(Map.get(discovery, "v1", %{}))
  end

  # ---------------------------------------------------------------------------
  # GET /fortnite/api/discovery/accessToken/:branch
  # ---------------------------------------------------------------------------
  def access_token(conn, %{"branch" => branch}) do
    conn |> put_status(200) |> json(%{
      "branchName" => branch,
      "appId"      => "Fortnite",
      "token"      => "lunar-discovery-token"
    })
  end

  # ---------------------------------------------------------------------------
  # POST /links/api/fn/mnemonic — returns all link data entries
  # ---------------------------------------------------------------------------
  def mnemonic_list(conn, _params) do
    discovery = load_discovery()
    panels = get_in(discovery, ["v2", "Panels"]) || []

    # Get the ByEpicWoven panel pages (index 1 matches LawinServer behaviour)
    results =
      panels
      |> Enum.find(%{}, fn p -> Map.get(p, "PanelName") == "ByEpicWoven" end)
      |> Map.get("Pages", [])
      |> List.first(%{})
      |> Map.get("results", [])

    link_data = Enum.flat_map(results, fn r ->
      case Map.get(r, "linkData") do
        nil -> []
        ld  -> [ld]
      end
    end)

    conn |> put_status(200) |> json(link_data)
  end

  # ---------------------------------------------------------------------------
  # GET /links/api/fn/mnemonic/:playlist/related
  # ---------------------------------------------------------------------------
  def mnemonic_related(conn, %{"playlist" => playlist}) do
    discovery = load_discovery()
    panels = get_in(discovery, ["v2", "Panels"]) || []

    results =
      panels
      |> Enum.find(%{}, fn p -> Map.get(p, "PanelName") == "ByEpicWoven" end)
      |> Map.get("Pages", [])
      |> List.first(%{})
      |> Map.get("results", [])

    links =
      Enum.reduce(results, %{}, fn r, acc ->
        ld = Map.get(r, "linkData", %{})
        if Map.get(ld, "mnemonic") == playlist do
          Map.put(acc, playlist, ld)
        else
          acc
        end
      end)

    conn |> put_status(200) |> json(%{"parentLinks" => [], "links" => links})
  end

  # ---------------------------------------------------------------------------
  # GET /links/api/fn/mnemonic/:mnemonic  (single link lookup)
  # ---------------------------------------------------------------------------
  def mnemonic_get(conn, %{"mnemonic" => mnemonic}) do
    discovery = load_discovery()
    panels = get_in(discovery, ["v2", "Panels"]) || []

    result =
      panels
      |> Enum.find(%{}, fn p -> Map.get(p, "PanelName") == "ByEpicWoven" end)
      |> Map.get("Pages", [])
      |> List.first(%{})
      |> Map.get("results", [])
      |> Enum.find(fn r ->
        get_in(r, ["linkData", "mnemonic"]) == mnemonic
      end)

    case result do
      nil -> conn |> put_status(404) |> json(%{"error" => "not found"})
      r   -> conn |> put_status(200) |> json(Map.get(r, "linkData", %{}))
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/links/lock-status/:accountId/check
  # ---------------------------------------------------------------------------
  def lock_status(conn, %{"accountId" => account_id}) do
    link_codes = Map.get(conn.body_params, "linkCodes") || []

    results =
      Enum.map(link_codes, fn code ->
        %{
          "playerId"        => account_id,
          "linkCode"        => code,
          "lockStatus"      => "UNLOCKED",
          "lockStatusReason"=> "NONE",
          "isVisible"       => true
        }
      end)

    conn |> put_status(200) |> json(%{"results" => results, "hasMore" => false})
  end
end
