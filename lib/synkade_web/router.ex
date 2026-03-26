defmodule SynkadeWeb.Router do
  use SynkadeWeb, :router

  import SynkadeWeb.UserAuth

  # Health check for kamal-proxy (no auth, no pipeline)
  get "/up", SynkadeWeb.HealthController, :index

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SynkadeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug SynkadeWeb.Plugs.Theme
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :agent_api do
    plug :accepts, ["json"]
    plug SynkadeWeb.Plugs.AgentAuth
  end

  scope "/", SynkadeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated,
      on_mount: [{SynkadeWeb.UserAuth, :require_authenticated}] do
      live "/", DashboardLive
      live "/projects/:name", DashboardLive
      live "/issues", IssuesLive
      live "/issues/:id", IdeLive
      live "/chat/:project_name", IdeLive
      live "/settings", SettingsLive
      live "/projects", ProjectsLive
    end
  end

  scope "/api/v1/agent", SynkadeWeb.Api do
    pipe_through :agent_api

    get "/me", AgentMeController, :show
    get "/issues", AgentIssuesController, :index
    post "/issues", AgentIssuesController, :create
    get "/issues/:id", AgentIssuesController, :show
    patch "/issues/:id", AgentIssuesController, :update
    post "/issues/:id/checkout", AgentIssuesController, :checkout
    post "/issues/:id/children", AgentIssuesController, :create_children
    post "/heartbeat", AgentHeartbeatController, :create

    get "/state", StateController, :index
    get "/projects", StateController, :projects
    get "/projects/:name", StateController, :project
    post "/refresh", StateController, :refresh
  end

  scope "/skills", SynkadeWeb do
    get "/:name/SKILL.md", SkillController, :show
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

  ## Setup route (first-time admin account creation)

  scope "/", SynkadeWeb do
    pipe_through [:browser]

    get "/setup", SetupController, :new
    post "/setup", SetupController, :create
  end

  ## Authentication routes

  scope "/", SynkadeWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", SynkadeWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
