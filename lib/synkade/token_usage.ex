defmodule Synkade.TokenUsage do
  @moduledoc false

  import Ecto.Query
  alias Synkade.Repo
  alias Synkade.TokenUsage.Record

  @doc "Record token usage for a completed agent run."
  def record_usage(attrs) do
    %Record{}
    |> Record.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get aggregated totals across all projects."
  def get_totals do
    from(r in Record,
      select: %{
        input_tokens: type(coalesce(sum(r.input_tokens), 0), :integer),
        output_tokens: type(coalesce(sum(r.output_tokens), 0), :integer),
        total_tokens: type(coalesce(sum(r.input_tokens), 0) + coalesce(sum(r.output_tokens), 0), :integer),
        runtime_seconds: coalesce(sum(r.runtime_seconds), 0.0),
        session_count: count(r.id)
      }
    )
    |> Repo.one()
  end

  @doc "Get aggregated totals grouped by project."
  def get_totals_by_project do
    from(r in Record,
      group_by: r.project_name,
      select: {r.project_name, %{
        input_tokens: type(coalesce(sum(r.input_tokens), 0), :integer),
        output_tokens: type(coalesce(sum(r.output_tokens), 0), :integer),
        total_tokens: type(coalesce(sum(r.input_tokens), 0) + coalesce(sum(r.output_tokens), 0), :integer),
        runtime_seconds: coalesce(sum(r.runtime_seconds), 0.0),
        session_count: count(r.id)
      }}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Get aggregated totals grouped by model."
  def get_totals_by_model do
    from(r in Record,
      group_by: r.model,
      select: {r.model, %{
        input_tokens: type(coalesce(sum(r.input_tokens), 0), :integer),
        output_tokens: type(coalesce(sum(r.output_tokens), 0), :integer),
        total_tokens: type(coalesce(sum(r.input_tokens), 0) + coalesce(sum(r.output_tokens), 0), :integer),
        runtime_seconds: coalesce(sum(r.runtime_seconds), 0.0),
        session_count: count(r.id)
      }}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Get aggregated totals grouped by auth mode (api_key vs oauth)."
  def get_totals_by_auth_mode do
    from(r in Record,
      group_by: r.auth_mode,
      select: {r.auth_mode, %{
        input_tokens: type(coalesce(sum(r.input_tokens), 0), :integer),
        output_tokens: type(coalesce(sum(r.output_tokens), 0), :integer),
        total_tokens: type(coalesce(sum(r.input_tokens), 0) + coalesce(sum(r.output_tokens), 0), :integer),
        runtime_seconds: coalesce(sum(r.runtime_seconds), 0.0),
        session_count: count(r.id)
      }}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Get detailed breakdown: model x auth_mode."
  def get_detailed_breakdown do
    from(r in Record,
      group_by: [r.model, r.auth_mode],
      select: %{
        model: r.model,
        auth_mode: r.auth_mode,
        input_tokens: type(coalesce(sum(r.input_tokens), 0), :integer),
        output_tokens: type(coalesce(sum(r.output_tokens), 0), :integer),
        total_tokens: type(coalesce(sum(r.input_tokens), 0) + coalesce(sum(r.output_tokens), 0), :integer),
        runtime_seconds: coalesce(sum(r.runtime_seconds), 0.0),
        session_count: count(r.id)
      }
    )
    |> Repo.all()
  end

  @doc "Get usage for a specific project with model breakdown."
  def get_project_usage(project_name) do
    from(r in Record,
      where: r.project_name == ^project_name,
      group_by: [r.model, r.auth_mode],
      select: %{
        model: r.model,
        auth_mode: r.auth_mode,
        input_tokens: type(coalesce(sum(r.input_tokens), 0), :integer),
        output_tokens: type(coalesce(sum(r.output_tokens), 0), :integer),
        total_tokens: type(coalesce(sum(r.input_tokens), 0) + coalesce(sum(r.output_tokens), 0), :integer),
        runtime_seconds: coalesce(sum(r.runtime_seconds), 0.0),
        session_count: count(r.id)
      }
    )
    |> Repo.all()
  end

  @doc "Get full usage summary suitable for the dashboard."
  def get_usage_summary do
    %{
      totals: get_totals(),
      by_project: get_totals_by_project(),
      by_model: get_totals_by_model(),
      by_auth_mode: get_totals_by_auth_mode()
    }
  end
end
