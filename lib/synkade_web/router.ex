defmodule SynkadeWeb.Router do
  use SynkadeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SynkadeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :agent_api do
    plug :accepts, ["json"]
    plug SynkadeWeb.Plugs.AgentAuth
  end

  scope "/", SynkadeWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/issues", IssuesLive
    live "/settings", SettingsLive
    live "/projects", ProjectsLive
    live "/logs", LogsLive
  end

  scope "/api/v1", SynkadeWeb.Api do
    pipe_through :api

    get "/state", StateController, :index
    get "/projects", StateController, :projects
    get "/projects/:name", StateController, :project
    post "/refresh", StateController, :refresh
  end

  scope "/api/v1/agent", SynkadeWeb.Api do
    pipe_through :agent_api

    get "/issues", AgentIssuesController, :index
    post "/issues", AgentIssuesController, :create
    get "/issues/:id", AgentIssuesController, :show
    patch "/issues/:id", AgentIssuesController, :update
    post "/issues/:id/children", AgentIssuesController, :create_children
  end

  scope "/github", SynkadeWeb.GitHub do
    pipe_through :api
    post "/webhooks", WebhookController, :handle
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:synkade, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SynkadeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
