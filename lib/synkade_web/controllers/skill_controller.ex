defmodule SynkadeWeb.SkillController do
  use SynkadeWeb, :controller

  @skill_path Path.join(:code.priv_dir(:synkade) |> to_string(), "../skills")

  def show(conn, %{"name" => name}) do
    path = Path.join([@skill_path, name, "SKILL.md"])
    normalized = Path.expand(path)

    if String.starts_with?(normalized, Path.expand(@skill_path)) and File.exists?(normalized) do
      conn
      |> put_resp_content_type("text/markdown")
      |> send_file(200, normalized)
    else
      conn
      |> put_status(404)
      |> text("Skill not found")
    end
  end
end
