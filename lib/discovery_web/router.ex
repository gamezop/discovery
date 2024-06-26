defmodule DiscoveryWeb.Router do
  use DiscoveryWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {DiscoveryWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug CORSPlug, origin: "*"
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug CORSPlug, origin: "*"
    plug :accepts, ["json"]
  end

  scope "/", DiscoveryWeb do
    pipe_through :browser

    live "/", PageLive, :index
  end

  get "/ping", DiscoveryWeb.BaseController, :ping, log: false

  # Other scopes may use custom stacks.
  scope "/api", DiscoveryWeb do
    pipe_through :api
    get "/get-endpoint", EndpointController, :get_endpoint

    get "/apps", BaseController, :list_app
    get "/:app_name/deployments", BaseController, :list_app_deployments
    post "/create-app", BaseController, :create_app
    post "/deploy-build", BaseController, :deploy_build
    delete "/delete-app", BaseController, :delete_app
    delete "/delete-deployment", BaseController, :delete_deployment
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: DiscoveryWeb.Telemetry
    end
  end
end
