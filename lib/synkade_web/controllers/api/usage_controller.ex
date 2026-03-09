defmodule SynkadeWeb.Api.UsageController do
  use SynkadeWeb, :controller

  alias Synkade.TokenUsage

  def index(conn, _params) do
    json(conn, %{
      totals: TokenUsage.get_totals(),
      by_project: TokenUsage.get_totals_by_project(),
      by_model: TokenUsage.get_totals_by_model(),
      by_auth_mode: TokenUsage.get_totals_by_auth_mode(),
      breakdown: TokenUsage.get_detailed_breakdown()
    })
  end

  def project(conn, %{"project_name" => project_name}) do
    json(conn, %{
      project: project_name,
      breakdown: TokenUsage.get_project_usage(project_name)
    })
  end
end
