defmodule Lunar.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        LunarWeb.Telemetry,
        Lunar.Repo,
        {DNSCluster, query: Application.get_env(:lunar, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Lunar.PubSub},
        # Start the Finch HTTP client for sending emails
        {Finch, name: Lunar.Finch},
        # MongoDB connection (replaces PostgreSQL/Ecto)
        {Lunar.Mongo, []},
        # Auto-rotating item shop (configurable via runtime.exs)
        Lunar.ShopRotator,
        # Start a worker by calling: Lunar.Worker.start_link(arg)
        # {Lunar.Worker, arg},
        # Start to serve requests, typically the last entry
        LunarWeb.Endpoint
      ]
      |> start_nostrum(Application.get_env(:lunar, :nostrum, []))

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lunar.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Create MongoDB indexes in background after startup
    Lunar.MongoIndexes.create_all()

    result
  end

  defp start_nostrum(children, _config), do: children ++ [LunarDiscord.Consumer]

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LunarWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
