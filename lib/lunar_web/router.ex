defmodule LunarWeb.Router do
  use LunarWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LunarWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LunarWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/catalog/api/shared/bulk/offers", StorefrontController, :offers
    get "/socialban/api/public/v1/:accountId", DataController, :social_ban
    get "/presence/api/v1/_/:accountId/settings/subscriptions", DataController, :subscriptions
    get "/fortnite/api/game/v2/privacy/account/:accountId", DataController, :privacy_settings
    get "/content-controls/:accountId", DataController, :content_controls
  end

  scope "/account/api", LunarWeb do
    pipe_through :api

    post "/oauth/token", TokenController, :token
    delete "/oauth/sessions", DataController, :enabled
    delete "/oauth/sessions/*path", DataController, :enabled
    get "/oauth/verify", DataController, :enabled

    get "/public/account", AccountController, :public2
    get "/public/account/:accountId", AccountController, :public
    get "/public/account/:accountId/*path", AccountController, :externalauths

    get "/epicdomains/ssodomains", AccountController, :ssodomains
  end

  scope "/fortnite/api", LunarWeb do
    pipe_through :api

    post "/feedback/Bug", DataController, :feedback
    get "/game/v2/world/info", DataController, :theater
    get "/matchmaking/session/findPlayer/:accountId", MatchmakingController, :findplayer
    get "/game/v2/matchmakingservice/ticket/player/:accountId", DataController, :access
    post "/game/v2/tryPlayOnPlatform/account/:accountId", DataController, :tryplayonplatform
    get "/versioncheck", DataController, :versioncheck
    get "/v2/versioncheck", DataController, :versioncheck
    get "/v2/versioncheck/*path", DataController, :versioncheck
    post "/game/v2/grant_access/*path", DataController, :access
    get "/game/v2/enabled_features", DataController, :access
    get "/receipts/v1/account/:accountId/receipts", StorefrontController, :receipts
    get "/game/v2/twitch/*path", DataController, :access
    get "/calendar/v1/timeline", TimelineController, :timeline

    # CloudStorage — system .ini files (served from priv/static/cloudstorage)
    get "/cloudstorage/system", CloudStorageController, :system_list
    get "/cloudstorage/system/config", CloudStorageController, :system_list
    get "/cloudstorage/system/:filename", CloudStorageController, :system_file

    # CloudStorage — per-user ClientSettings.Sav (saved per build CL)
    get "/cloudstorage/user/:accountId", CloudStorageController, :user_list
    get "/cloudstorage/user/:accountId/:file", CloudStorageController, :user_file
    put "/cloudstorage/user/:accountId/:file", CloudStorageController, :user_file_put
  end

  scope "/fortnite/api/game/v2", LunarWeb do
    pipe_through :api

    post "/profileToken/verify/:accountId", DataController, :enabled

    # QueryProfile family
    post "/profile/:accountId/client/QueryProfile", ProfileController, :queryprofile
    post "/profile/:accountId/client/RefreshExpeditions", ProfileController, :queryprofile
    post "/profile/:accountId/client/IncrementNamedCounterStat", ProfileController, :queryprofile
    post "/profile/:accountId/client/SetMtxPlatform", ProfileController, :queryprofile
    post "/profile/:accountId/client/GetMcpTimeForLogin", ProfileController, :queryprofile

    # Daily challenges + discovery quests
    post "/profile/:accountId/client/ClientQuestLogin", ProfileController, :clientquestlogin
    post "/profile/:accountId/client/FortRerollDailyQuest", ProfileController, :fortrerolldailyquest
    post "/profile/:accountId/client/MarkNewQuestNotificationSent", ProfileController, :marknewquestnotificationsent

    # Favoriting items
    post "/profile/:accountId/client/SetItemFavoriteStatus", ProfileController, :setitemfavoritestatus
    post "/profile/:accountId/client/SetItemFavoriteStatusBatch", ProfileController, :setitemfavoritestatusbatch

    # Marking items as seen
    post "/profile/:accountId/client/MarkItemSeen", ProfileController, :markitemseen

    # Banner icon and color
    post "/profile/:accountId/client/SetBattleRoyaleBanner", ProfileController, :setbattleroyalebanner
    post "/profile/:accountId/client/SetCosmeticLockerBanner", ProfileController, :setcosmeticlockerbanneraction

    # Changing items in Locker (new-style and old-style)
    post "/profile/:accountId/client/SetCosmeticLockerSlot", ProfileController, :setcosmeticlockerslot
    post "/profile/:accountId/client/EquipBattleRoyaleCustomization", ProfileController, :equipbattleroyalecustomization

    # Edit styles / variant attributes
    post "/profile/:accountId/client/SetItemArchivedStatusRequest", ProfileController, :markitemseen
    post "/profile/:accountId/client/SetVariantAttrs", ProfileController, :setvariantattrs

    # Lobby background skin
    post "/profile/:accountId/client/SetLobbyBackground", ProfileController, :setlobbybackground

    # Item Shop — purchase & refund
    post "/profile/:accountId/client/PurchaseCatalogEntry", ProfileController, :purchasecatalogentry
    post "/profile/:accountId/client/RefundMtxPurchase", ProfileController, :refundmtxpurchase

    # Winterfest presents
    post "/profile/:accountId/client/UnlockRewardNode", ProfileController, :unlockrewardnode
    post "/profile/:accountId/client/RemoveGiftBox", ProfileController, :removegiftbox

    # Gifting
    post "/profile/:accountId/client/GiftCatalogEntry", ProfileController, :giftcatalogentry

    get "/events/tournamentandhistory/:accountId/:region/*path", DataController, :enabled
  end

  scope "/fortnite/api/storefront/v2", LunarWeb do
    pipe_through :api
    get "/catalog", StorefrontController, :catalog
    get "/keychain", StorefrontController, :keychain

    # Gift eligibility check
    get "/gift/check_eligibility/recipient/:recipientId/offer/:offerId", StorefrontController, :gift_eligibility
  end

  scope "/datarouter/api/v1/public", LunarWeb do
    pipe_through :api

    post "/data", DataController, :datarouter
  end

  scope "/lightswitch/api", LunarWeb do
    pipe_through :api

    get "/service/bulk/status", TimelineController, :lightswitch_bulk
    get "/service/Fortnite/status", TimelineController, :lightswitch_status
  end

  scope "/socialban/api", LunarWeb do
    pipe_through :api

    get "/public/v1/:accountId/ban", DataController, :socialban
  end

  scope "/waitingroom/api", LunarWeb do
    get "/waitingroom", DataController, :waitingroom
  end

  scope "/content/api/pages", LunarWeb do
    pipe_through :api

    get "/fortnite-game", DataController, :fortnite_game
  end

  scope "/friends/api", LunarWeb do
    pipe_through :api

    get "/public/blocklist/:accountId", FriendsController, :blocklist
    get "/public/friends/:accountId", FriendsController, :public_friends
    get "/public/list/fortnite/:accountId/recentPlayers", FriendsController, :recent_players
    get "/v1/:accountId/blocklist", FriendsController, :blocklist
    get "/v1/:accountId/settings", FriendsController, :settings
    get "/v1/:accountId/recent/fortnite", FriendsController, :recent_players
    get "/v1/:accountId/summary", FriendsController, :summary

    # Friend request / accept / unfriend
    post "/v1/:accountId/friends/:receiverId", FriendsController, :send_or_accept
    delete "/v1/:accountId/friends/:receiverId", FriendsController, :delete_friend

    # Block / unblock
    post "/v1/:accountId/blocklist/:receiverId", FriendsController, :block_friend
    delete "/v1/:accountId/blocklist/:receiverId", FriendsController, :unblock_friend

    # Alias management
    put "/v1/:accountId/friends/:friendId/alias", FriendsController, :friend_alias
    delete "/v1/:accountId/friends/:friendId/alias", FriendsController, :friend_alias
  end

  # ---------------------------------------------------------------------------
  # Discovery Tab — game mode selection panel + link metadata
  # ---------------------------------------------------------------------------
  scope "/", LunarWeb do
    pipe_through :api

    # v2 surface (Season 20+)
    post "/api/v2/discovery/surface/:surface", DiscoveryController, :surface_v2
    post "/fortnite/api/v2/discovery/surface/:surface", DiscoveryController, :surface_v2

    # v1 surface (older seasons)
    post "/fortnite/discovery/surface/:surface", DiscoveryController, :surface_v1

    # Access token for discovery
    get "/fortnite/api/discovery/accessToken/:branch", DiscoveryController, :access_token

    # Links / mnemonic endpoints
    post "/links/api/fn/mnemonic", DiscoveryController, :mnemonic_list
    get  "/links/api/fn/mnemonic/:playlist/related", DiscoveryController, :mnemonic_related
    get  "/links/api/fn/mnemonic/:mnemonic", DiscoveryController, :mnemonic_get

    # Lock-status check
    post "/api/v1/links/lock-status/:accountId/check", DiscoveryController, :lock_status
  end

  # ---------------------------------------------------------------------------
  # V-Bucks API (kill/win rewards)
  # ---------------------------------------------------------------------------
  scope "/api/lunar", LunarWeb do
    pipe_through :api

    get "/vbucks", ApiController, :grant_vbucks
  end

  # Other scopes may use custom stacks.
  # scope "/api", LunarWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:lunar, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LunarWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
