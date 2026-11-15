defmodule LunarWeb.TimelineController do
  use LunarWeb, :controller

  # ---------------------------------------------------------------------------
  # GET /fortnite/api/calendar/v1/timeline
  # Returns active event flags for the detected season/build.
  # ---------------------------------------------------------------------------
  def timeline(conn, _params) do
    ua  = get_req_header(conn, "user-agent") |> List.first() || ""
    ver = Lunar.Version.get(%{headers: %{"user-agent" => ua}})

    base_events = [
      event("EventFlag.Season#{ver.season}"),
      event("EventFlag.#{ver.lobby}")
    ]

    season_events = season_events(ver.season, ver.build)
    active_events = base_events ++ season_events

    response = %{
      channels: %{
        "client-matchmaking" => %{
          states: [],
          cacheExpire: "9999-01-01T00:00:00.000Z"
        },
        "client-events" => %{
          states: [
            %{
              validFrom: "0001-01-01T00:00:00.000Z",
              activeEvents: active_events,
              state: %{
                activeStorefronts: [],
                eventNamedWeights: %{},
                seasonNumber: "#{ver.season}",
                seasonTemplateId: "AthenaSeason:athenaseason#{ver.season}",
                matchXpBonusPoints: 0,
                seasonBegin: "2020-01-01T00:00:00Z",
                seasonEnd: "9999-01-01T00:00:00Z",
                seasonDisplayedEnd: "9999-01-01T00:00:00Z",
                weeklyStoreEnd: "9999-01-01T00:00:00Z",
                stwEventStoreEnd: "9999-01-01T00:00:00.000Z",
                stwWeeklyStoreEnd: "9999-01-01T00:00:00.000Z",
                sectionStoreEnds: %{"Featured" => "9999-01-01T00:00:00.000Z"},
                dailyStoreEnd: "9999-01-01T00:00:00.000Z"
              }
            }
          ],
          cacheExpire: "9999-01-01T00:00:00.000Z"
        }
      },
      eventsTimeOffsetHrs: 0,
      cacheIntervalMins: 10,
      currentTime: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    conn |> put_status(:ok) |> json(response)
  end

  # ---------------------------------------------------------------------------
  # Lightswitch endpoints
  # ---------------------------------------------------------------------------

  def lightswitch_status(conn, _params) do
    conn |> put_status(200) |> json(%{
      "serviceInstanceId" => "fortnite",
      "status"            => "UP",
      "message"           => "Fortnite is online",
      "maintenanceUri"    => nil,
      "overrideCatalogIds"=> ["a7f138b2e51945ffbfdacc1af0541053"],
      "allowedActions"    => [],
      "banned"            => false,
      "launcherInfoDTO"   => %{
        "appName"       => "Fortnite",
        "catalogItemId" => "4fe75bbc5a674f4f9b356b5c90567da5",
        "namespace"     => "fn"
      }
    })
  end

  def lightswitch_bulk(conn, _params) do
    conn |> put_status(200) |> json([%{
      "serviceInstanceId" => "fortnite",
      "status"            => "UP",
      "message"           => "fortnite is up.",
      "maintenanceUri"    => nil,
      "overrideCatalogIds"=> ["a7f138b2e51945ffbfdacc1af0541053"],
      "allowedActions"    => ["PLAY", "DOWNLOAD"],
      "banned"            => false,
      "launcherInfoDTO"   => %{
        "appName"       => "Fortnite",
        "catalogItemId" => "4fe75bbc5a674f4f9b356b5c90567da5",
        "namespace"     => "fn"
      }
    }])
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp event(type) do
    %{
      eventType:   type,
      activeUntil: "9999-01-01T00:00:00.000Z",
      activeSince: "2020-01-01T00:00:00.000Z"
    }
  end

  defp events(types), do: Enum.map(types, &event/1)

  # ---------------------------------------------------------------------------
  # Per-season event flags — ported directly from LawinServer timeline.js
  # ---------------------------------------------------------------------------
  defp season_events(season, build) do
    case season do
      3 ->
        base = events(["EventFlag.Spring2018Phase1"])
        base = if build >= 3.1, do: base ++ events(["EventFlag.Spring2018Phase2"]), else: base
        base = if build >= 3.3, do: base ++ events(["EventFlag.Spring2018Phase3"]), else: base
        if build >= 3.4, do: base ++ events(["EventFlag.Spring2018Phase4"]), else: base

      4 ->
        base = events(["EventFlag.Blockbuster2018", "EventFlag.Blockbuster2018Phase1"])
        base = if build >= 4.3, do: base ++ events(["EventFlag.Blockbuster2018Phase2"]), else: base
        base = if build >= 4.4, do: base ++ events(["EventFlag.Blockbuster2018Phase3"]), else: base
        if build >= 4.5, do: base ++ events(["EventFlag.Blockbuster2018Phase4"]), else: base

      5 ->
        base = events(["EventFlag.RoadTrip2018", "EventFlag.Horde",
                        "EventFlag.Anniversary2018_BR", "EventFlag.LTM_Heist"])
        if build == 5.10, do: base ++ events(["EventFlag.BirthdayBattleBus"]), else: base

      6 ->
        base = events(["EventFlag.LTM_Fortnitemares", "EventFlag.LTM_LilKevin"])
        base =
          if build >= 6.20 do
            base ++ events(["EventFlag.Fortnitemares", "EventFlag.FortnitemaresPhase1", "POI0"])
          else
            base
          end
        base =
          if build >= 6.22 do
            base ++ events(["EventFlag.FortnitemaresPhase2"])
          else
            base
          end
        if build == 6.20 or build == 6.21 do
          base ++ events(["EventFlag.LobbySeason6Halloween", "EventFlag.HalloweenBattleBus"])
        else
          base
        end

      7 ->
        events(["EventFlag.Frostnite", "EventFlag.LTM_14DaysOfFortnite",
                "EventFlag.LTE_Festivus", "EventFlag.LTM_WinterDeimos",
                "EventFlag.LTE_S7_OverTime"])

      8 ->
        base = events(["EventFlag.Spring2019", "EventFlag.Spring2019.Phase1",
                        "EventFlag.LTM_Ashton", "EventFlag.LTM_Goose",
                        "EventFlag.LTM_HighStakes", "EventFlag.LTE_BootyBay"])
        if build >= 8.2, do: base ++ events(["EventFlag.Spring2019.Phase2"]), else: base

      9 ->
        base = events(["EventFlag.Season9.Phase1", "EventFlag.Anniversary2019_BR",
                        "EventFlag.LTM_14DaysOfSummer", "EventFlag.LTM_Mash",
                        "EventFlag.LTM_Wax"])
        if build >= 9.2, do: base ++ events(["EventFlag.Season9.Phase2"]), else: base

      10 ->
        events([
          "EventFlag.Mayday", "EventFlag.Season10.Phase2", "EventFlag.Season10.Phase3",
          "EventFlag.LTE_BlackMonday", "EventFlag.S10_Oak", "EventFlag.S10_Mystery",
          "EventFlag.Season10_UrgentMission_1", "EventFlag.Season10_UrgentMission_2",
          "EventFlag.Season10_UrgentMission_3", "EventFlag.Season10_UrgentMission_4",
          "EventFlag.Season10_UrgentMission_5", "EventFlag.Season10_UrgentMission_6",
          "EventFlag.Season10_UrgentMission_7", "EventFlag.Season10_UrgentMission_8",
          "EventFlag.Season10_UrgentMission_9", "EventFlag.Season10_UrgentMission_10"
        ])

      11 ->
        base = events(["EventFlag.LTE_CoinCollectXP", "EventFlag.LTE_Fortnitemares2019",
                        "EventFlag.LTE_Galileo_Feats", "EventFlag.LTE_Galileo",
                        "EventFlag.LTE_WinterFest2019"])

        base = if build >= 11.2, do: base ++ events(["EventFlag.Starlight"]), else: base

        base =
          if build < 11.3 do
            b = if build >= 11.01,
              do: base ++ events(["EventFlag.Season11.Fortnitemares.Quests.Phase1"]),
              else: base
            if build >= 11.10 do
              b ++ events(["EventFlag.Season11.Fortnitemares.Quests.Phase2",
                            "EventFlag.Season11.Fortnitemares.Quests.Phase3",
                            "EventFlag.Season11.Fortnitemares.Quests.Phase4",
                            "EventFlag.StormKing.Landmark"])
            else
              b
            end
          else
            base ++ events(["EventFlag.HolidayDeco",
                             "EventFlag.Season11.WinterFest.Quests.Phase1",
                             "EventFlag.Season11.WinterFest.Quests.Phase2",
                             "EventFlag.Season11.WinterFest.Quests.Phase3",
                             "EventFlag.Season11.Frostnite"])
          end

        # Winterfest tree flags (11.31 / 11.40)
        if build == 11.31 or build == 11.40 do
          base ++ events(["EventFlag.Winterfest.Tree", "EventFlag.LTE_WinterFest",
                           "EventFlag.LTE_WinterFest2019"])
        else
          base
        end

      12 ->
        events(["EventFlag.LTE_SpyGames", "EventFlag.LTE_JerkyChallenges",
                "EventFlag.LTE_Oro", "EventFlag.LTE_StormTheAgency"])

      14 ->
        events(["EventFlag.LTE_Fortnitemares_2020"])

      15 ->
        events([
          "EventFlag.LTQ_S15_Legendary_Week_01", "EventFlag.LTQ_S15_Legendary_Week_02",
          "EventFlag.LTQ_S15_Legendary_Week_03", "EventFlag.LTQ_S15_Legendary_Week_04",
          "EventFlag.LTQ_S15_Legendary_Week_05", "EventFlag.LTQ_S15_Legendary_Week_06",
          "EventFlag.LTQ_S15_Legendary_Week_07", "EventFlag.LTQ_S15_Legendary_Week_08",
          "EventFlag.LTQ_S15_Legendary_Week_09", "EventFlag.LTQ_S15_Legendary_Week_10",
          "EventFlag.LTQ_S15_Legendary_Week_11", "EventFlag.LTQ_S15_Legendary_Week_12",
          "EventFlag.LTQ_S15_Legendary_Week_13", "EventFlag.LTQ_S15_Legendary_Week_14",
          "EventFlag.LTQ_S15_Legendary_Week_15", "EventFlag.Event_HiddenRole",
          "EventFlag.Event_OperationSnowdown", "EventFlag.Event_PlumRetro"
        ])

      16 ->
        events([
          "EventFlag.LTQ_S16_Legendary_Week_01", "EventFlag.LTQ_S16_Legendary_Week_02",
          "EventFlag.LTQ_S16_Legendary_Week_03", "EventFlag.LTQ_S16_Legendary_Week_04",
          "EventFlag.LTQ_S16_Legendary_Week_05", "EventFlag.LTQ_S16_Legendary_Week_06",
          "EventFlag.LTQ_S16_Legendary_Week_07", "EventFlag.LTQ_S16_Legendary_Week_08",
          "EventFlag.LTQ_S16_Legendary_Week_09", "EventFlag.LTQ_S16_Legendary_Week_10",
          "EventFlag.LTQ_S16_Legendary_Week_11", "EventFlag.LTQ_S16_Legendary_Week_12",
          "EventFlag.Event_NBA_Challenges", "EventFlag.Event_Spire_Challenges"
        ])

      17 ->
        events([
          "EventFlag.Event_TheMarch", "EventFlag.Event_O2_Challenges",
          "EventFlag.LTE_Buffet_PreQuests", "EventFlag.LTE_Buffet_Attend",
          "EventFlag.LTE_Buffet_PostQuests", "EventFlag.LTE_Buffet_Cosmetics",
          "EventFlag.Event_CosmicSummer", "EventFlag.Event_IslandGames",
          "EventFlag.LTQ_S17_Legendary_Week_01", "EventFlag.LTQ_S17_Legendary_Week_02",
          "EventFlag.LTQ_S17_Legendary_Week_03", "EventFlag.LTQ_S17_Legendary_Week_04",
          "EventFlag.LTQ_S17_Legendary_Week_05", "EventFlag.LTQ_S17_Legendary_Week_06",
          "EventFlag.LTQ_S17_Legendary_Week_07", "EventFlag.LTQ_S17_Legendary_Week_08",
          "EventFlag.LTQ_S17_Legendary_Week_09"
        ])

      18 ->
        events([
          "EventFlag.LTQ_S18_Legendary_Week_01", "EventFlag.LTQ_S18_Legendary_Week_02",
          "EventFlag.LTQ_S18_Legendary_Week_03", "EventFlag.LTQ_S18_Legendary_Week_04",
          "EventFlag.LTQ_S18_Legendary_Week_05", "EventFlag.LTQ_S18_Legendary_Week_06",
          "EventFlag.LTQ_S18_Legendary_Week_07", "EventFlag.LTQ_S18_Legendary_Week_08",
          "EventFlag.LTQ_S18_Legendary_Week_09", "EventFlag.LTQ_S18_Legendary_Week_10",
          "EventFlag.LTQ_S18_Legendary_Week_11", "EventFlag.Event_Fortnitemares_2021"
        ])

      19 ->
        base = events([
          "EventFlag.LTQ_S19_Legendary_Week_01", "EventFlag.LTQ_S19_Legendary_Week_02",
          "EventFlag.LTQ_S19_Legendary_Week_03", "EventFlag.LTQ_S19_Legendary_Week_04",
          "EventFlag.LTQ_S19_Legendary_Week_05", "EventFlag.LTQ_S19_Legendary_Week_06",
          "EventFlag.LTQ_S19_Legendary_Week_07", "EventFlag.LTQ_S19_Legendary_Week_08",
          "EventFlag.LTQ_S19_Legendary_Week_09", "EventFlag.LTQ_S19_Legendary_Week_10",
          "EventFlag.S19_WinterfestCrewGrant"
        ])
        # 19.01 Winterfest
        if build == 19.01 do
          base ++ events(["EventFlag.LTE_WinterFest", "EventFlag.LTE_WinterFestTab"])
        else
          base
        end

      20 ->
        events([
          "EventFlag.LTQ_S20_Legendary_Week_01", "EventFlag.LTQ_S20_Legendary_Week_02",
          "EventFlag.LTQ_S20_Legendary_Week_03", "EventFlag.LTQ_S20_Legendary_Week_04",
          "EventFlag.LTQ_S20_Legendary_Week_05", "EventFlag.LTQ_S20_Legendary_Week_06",
          "EventFlag.LTQ_S20_Legendary_Week_07", "EventFlag.LTQ_S20_Legendary_Week_08",
          "EventFlag.LTQ_S20_Legendary_Week_09"
        ])

      21 ->
        events([
          "EventFlag.LTQ_S21_Legendary_Week_01", "EventFlag.LTQ_S21_Legendary_Week_02",
          "EventFlag.LTQ_S21_Legendary_Week_03", "EventFlag.LTQ_S21_Legendary_Week_04",
          "EventFlag.LTQ_S21_Legendary_Week_05", "EventFlag.LTQ_S21_Legendary_Week_06",
          "EventFlag.LTQ_S21_Legendary_Week_07", "EventFlag.LTQ_S21_Legendary_Week_08",
          "EventFlag.LTQ_S21_Legendary_Week_09"
        ])

      22 ->
        events([
          "EventFlag.LTQ_S22_Legendary_Week_01", "EventFlag.LTQ_S22_Legendary_Week_02",
          "EventFlag.LTQ_S22_Legendary_Week_03", "EventFlag.LTQ_S22_Legendary_Week_04",
          "EventFlag.LTQ_S22_Legendary_Week_05", "EventFlag.LTQ_S22_Legendary_Week_06",
          "EventFlag.LTQ_S22_Legendary_Week_07", "EventFlag.LTQ_S22_Legendary_Week_08",
          "EventFlag.LTQ_S22_Legendary_Week_09", "EventFlag.Event_Fortnitemares_2022"
        ])

      23 ->
        base = events([
          "EventFlag.LTQ_S23_Legendary_Week_01", "EventFlag.LTQ_S23_Legendary_Week_02",
          "EventFlag.LTQ_S23_Legendary_Week_03", "EventFlag.LTQ_S23_Legendary_Week_04",
          "EventFlag.LTQ_S23_Legendary_Week_05", "EventFlag.LTQ_S23_Legendary_Week_06",
          "EventFlag.LTQ_S23_Legendary_Week_07", "EventFlag.LTQ_S23_Legendary_Week_08",
          "EventFlag.LTQ_S23_Legendary_Week_09"
        ])
        # 23.10 Winterfest
        if build == 23.10 do
          base ++ events(["EventFlag.LTE_WinterFest", "EventFlag.LTE_WinterFestTab"])
        else
          base
        end

      28 ->
        events(["EventFlag.Event_S28_Winterfest"])

      33 ->
        base = events([
          "EventFlag.LTQ_S33_Legendary_Week_01", "EventFlag.LTQ_S33_Legendary_Week_02",
          "EventFlag.LTQ_S33_Legendary_Week_03", "EventFlag.LTQ_S33_Legendary_Week_04",
          "EventFlag.LTQ_S33_Legendary_Week_05", "EventFlag.LTQ_S33_Legendary_Week_06",
          "EventFlag.LTQ_S33_Legendary_Week_07", "EventFlag.LTQ_S33_Legendary_Week_08",
          "EventFlag.LTQ_S33_Legendary_Week_09"
        ])
        # 33.11 Winterfest
        if build == 33.11 do
          base ++ events(["EventFlag.Winterfest_S33_CabinRewards",
                           "EventFlag.S33_WinterFestTab", "EventFlag.S33_WinterFest"])
        else
          base
        end

      39 ->
        base = events([
          "EventFlag.LTQ_S39_Legendary_Week_01", "EventFlag.LTQ_S39_Legendary_Week_02",
          "EventFlag.LTQ_S39_Legendary_Week_03", "EventFlag.LTQ_S39_Legendary_Week_04",
          "EventFlag.LTQ_S39_Legendary_Week_05", "EventFlag.LTQ_S39_Legendary_Week_06",
          "EventFlag.LTQ_S39_Legendary_Week_07", "EventFlag.LTQ_S39_Legendary_Week_08",
          "EventFlag.LTQ_S39_Legendary_Week_09"
        ])
        # 39.11 Winterfest
        if build == 39.11 do
          base ++ events(["EventFlag.Winterfest_S39_CabinRewards",
                           "EventFlag.S39_WinterFestTab", "EventFlag.S39_WinterFest"])
        else
          base
        end

      _ ->
        []
    end
  end
end
