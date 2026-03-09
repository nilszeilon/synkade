defmodule Synkade.TokenUsageTest do
  use Synkade.DataCase

  alias Synkade.TokenUsage

  defp insert_usage(attrs) do
    defaults = %{
      project_name: "default",
      issue_id: "1",
      issue_identifier: "#1",
      model: "claude-sonnet-4-5-20250929",
      auth_mode: "api_key",
      input_tokens: 1000,
      output_tokens: 500,
      runtime_seconds: 10.0
    }

    {:ok, record} = TokenUsage.record_usage(Map.merge(defaults, attrs))
    record
  end

  describe "record_usage/1" do
    test "inserts a valid token usage record" do
      assert {:ok, record} =
               TokenUsage.record_usage(%{
                 project_name: "myproject",
                 issue_id: "42",
                 issue_identifier: "#42",
                 model: "claude-opus-4-6",
                 auth_mode: "api_key",
                 input_tokens: 5000,
                 output_tokens: 2000,
                 runtime_seconds: 30.5
               })

      assert record.project_name == "myproject"
      assert record.issue_id == "42"
      assert record.model == "claude-opus-4-6"
      assert record.auth_mode == "api_key"
      assert record.input_tokens == 5000
      assert record.output_tokens == 2000
      assert record.runtime_seconds == 30.5
    end

    test "requires project_name, issue_id, and auth_mode" do
      assert {:error, changeset} = TokenUsage.record_usage(%{})
      errors = errors_on(changeset)
      assert errors[:project_name]
      assert errors[:issue_id]
      assert errors[:auth_mode]
    end

    test "validates auth_mode is api_key or oauth" do
      assert {:error, changeset} =
               TokenUsage.record_usage(%{
                 project_name: "test",
                 issue_id: "1",
                 auth_mode: "invalid"
               })

      assert errors_on(changeset)[:auth_mode]
    end

    test "validates token counts are non-negative" do
      assert {:error, changeset} =
               TokenUsage.record_usage(%{
                 project_name: "test",
                 issue_id: "1",
                 auth_mode: "api_key",
                 input_tokens: -1
               })

      assert errors_on(changeset)[:input_tokens]
    end

    test "defaults token counts to 0" do
      {:ok, record} =
        TokenUsage.record_usage(%{
          project_name: "test",
          issue_id: "1",
          auth_mode: "api_key"
        })

      assert record.input_tokens == 0
      assert record.output_tokens == 0
    end
  end

  describe "get_totals/0" do
    test "returns zeros when no records exist" do
      totals = TokenUsage.get_totals()
      assert totals.input_tokens == 0
      assert totals.output_tokens == 0
      assert totals.total_tokens == 0
      assert totals.session_count == 0
    end

    test "aggregates all records" do
      insert_usage(%{input_tokens: 1000, output_tokens: 500})
      insert_usage(%{input_tokens: 2000, output_tokens: 1500})

      totals = TokenUsage.get_totals()
      assert totals.input_tokens == 3000
      assert totals.output_tokens == 2000
      assert totals.total_tokens == 5000
      assert totals.session_count == 2
    end
  end

  describe "get_totals_by_project/0" do
    test "groups by project name" do
      insert_usage(%{project_name: "frontend", input_tokens: 1000, output_tokens: 500})
      insert_usage(%{project_name: "frontend", input_tokens: 2000, output_tokens: 1000})
      insert_usage(%{project_name: "backend", input_tokens: 3000, output_tokens: 1500})

      by_project = TokenUsage.get_totals_by_project()

      assert by_project["frontend"].input_tokens == 3000
      assert by_project["frontend"].output_tokens == 1500
      assert by_project["frontend"].total_tokens == 4500
      assert by_project["frontend"].session_count == 2

      assert by_project["backend"].input_tokens == 3000
      assert by_project["backend"].output_tokens == 1500
      assert by_project["backend"].total_tokens == 4500
      assert by_project["backend"].session_count == 1
    end

    test "returns empty map when no records" do
      assert TokenUsage.get_totals_by_project() == %{}
    end
  end

  describe "get_totals_by_model/0" do
    test "groups by model" do
      insert_usage(%{model: "claude-sonnet-4-5-20250929", input_tokens: 1000, output_tokens: 500})
      insert_usage(%{model: "claude-opus-4-6", input_tokens: 5000, output_tokens: 3000})
      insert_usage(%{model: "claude-opus-4-6", input_tokens: 4000, output_tokens: 2000})

      by_model = TokenUsage.get_totals_by_model()

      assert by_model["claude-sonnet-4-5-20250929"].input_tokens == 1000
      assert by_model["claude-sonnet-4-5-20250929"].total_tokens == 1500
      assert by_model["claude-sonnet-4-5-20250929"].session_count == 1

      assert by_model["claude-opus-4-6"].input_tokens == 9000
      assert by_model["claude-opus-4-6"].total_tokens == 14000
      assert by_model["claude-opus-4-6"].session_count == 2
    end
  end

  describe "get_totals_by_auth_mode/0" do
    test "groups by auth mode" do
      insert_usage(%{auth_mode: "api_key", input_tokens: 1000, output_tokens: 500})
      insert_usage(%{auth_mode: "api_key", input_tokens: 2000, output_tokens: 1000})
      insert_usage(%{auth_mode: "oauth", input_tokens: 5000, output_tokens: 3000})

      by_auth = TokenUsage.get_totals_by_auth_mode()

      assert by_auth["api_key"].input_tokens == 3000
      assert by_auth["api_key"].total_tokens == 4500
      assert by_auth["api_key"].session_count == 2

      assert by_auth["oauth"].input_tokens == 5000
      assert by_auth["oauth"].total_tokens == 8000
      assert by_auth["oauth"].session_count == 1
    end
  end

  describe "get_detailed_breakdown/0" do
    test "groups by model x auth_mode" do
      insert_usage(%{model: "claude-sonnet-4-5-20250929", auth_mode: "api_key", input_tokens: 1000, output_tokens: 500})
      insert_usage(%{model: "claude-sonnet-4-5-20250929", auth_mode: "oauth", input_tokens: 2000, output_tokens: 1000})
      insert_usage(%{model: "claude-opus-4-6", auth_mode: "api_key", input_tokens: 5000, output_tokens: 3000})

      breakdown = TokenUsage.get_detailed_breakdown()
      assert length(breakdown) == 3

      sonnet_api = Enum.find(breakdown, &(&1.model == "claude-sonnet-4-5-20250929" && &1.auth_mode == "api_key"))
      assert sonnet_api.input_tokens == 1000
      assert sonnet_api.total_tokens == 1500

      sonnet_oauth = Enum.find(breakdown, &(&1.model == "claude-sonnet-4-5-20250929" && &1.auth_mode == "oauth"))
      assert sonnet_oauth.input_tokens == 2000
      assert sonnet_oauth.total_tokens == 3000
    end
  end

  describe "get_project_usage/1" do
    test "returns model breakdown for a specific project" do
      insert_usage(%{project_name: "frontend", model: "claude-sonnet-4-5-20250929", auth_mode: "api_key", input_tokens: 1000, output_tokens: 500})
      insert_usage(%{project_name: "frontend", model: "claude-opus-4-6", auth_mode: "oauth", input_tokens: 5000, output_tokens: 3000})
      insert_usage(%{project_name: "backend", model: "claude-sonnet-4-5-20250929", auth_mode: "api_key", input_tokens: 9000, output_tokens: 4000})

      usage = TokenUsage.get_project_usage("frontend")
      assert length(usage) == 2

      # Backend data should not appear
      assert Enum.all?(usage, fn row -> row.model != nil end)
    end

    test "returns empty list for non-existent project" do
      assert TokenUsage.get_project_usage("nonexistent") == []
    end
  end

  describe "get_usage_summary/0" do
    test "returns combined summary" do
      insert_usage(%{project_name: "frontend", model: "claude-sonnet-4-5-20250929", auth_mode: "api_key"})
      insert_usage(%{project_name: "backend", model: "claude-opus-4-6", auth_mode: "oauth"})

      summary = TokenUsage.get_usage_summary()

      assert summary.totals.session_count == 2
      assert map_size(summary.by_project) == 2
      assert map_size(summary.by_model) == 2
      assert map_size(summary.by_auth_mode) == 2
    end
  end
end
