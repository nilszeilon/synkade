defmodule SynkadeWeb.Api.StateControllerTest do
  use SynkadeWeb.ConnCase

  describe "GET /api/v1/state" do
    test "returns state snapshot", %{conn: conn} do
      conn = get(conn, "/api/v1/state")
      assert json = json_response(conn, 200)
      assert is_map(json["running"])
      assert is_map(json["agent_totals"])
    end
  end

  describe "GET /api/v1/projects" do
    test "returns projects list", %{conn: conn} do
      conn = get(conn, "/api/v1/projects")
      assert json = json_response(conn, 200)
      assert is_list(json["projects"])
    end
  end

  describe "GET /api/v1/projects/:name" do
    test "returns 404 for unknown project", %{conn: conn} do
      conn = get(conn, "/api/v1/projects/nonexistent")
      assert json_response(conn, 404)["error"] == "project not found"
    end
  end

  describe "POST /api/v1/refresh" do
    test "returns ok", %{conn: conn} do
      conn = post(conn, "/api/v1/refresh")
      assert json_response(conn, 200)["status"] == "ok"
    end
  end
end
