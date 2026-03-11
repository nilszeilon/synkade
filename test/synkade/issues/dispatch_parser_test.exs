defmodule Synkade.Issues.DispatchParserTest do
  use ExUnit.Case, async: true

  alias Synkade.Issues.DispatchParser

  describe "parse/1" do
    test "extracts agent name and instruction" do
      assert {"researcher", "look into how we can do X"} =
               DispatchParser.parse("@researcher look into how we can do X")
    end

    test "handles agent names with hyphens" do
      assert {"code-reviewer", "check the PR"} =
               DispatchParser.parse("@code-reviewer check the PR")
    end

    test "handles agent names with underscores" do
      assert {"my_agent", "do something"} =
               DispatchParser.parse("@my_agent do something")
    end

    test "returns nil agent when no @ prefix" do
      assert {nil, "just some instructions"} =
               DispatchParser.parse("just some instructions")
    end

    test "handles multiline instructions" do
      assert {"researcher", "look into\nmultiple lines"} =
               DispatchParser.parse("@researcher look into\nmultiple lines")
    end

    test "trims whitespace" do
      assert {"agent", "do work"} =
               DispatchParser.parse("  @agent do work  ")
    end

    test "returns nil agent for @ without space after name" do
      assert {nil, "@"} = DispatchParser.parse("@")
    end

    test "handles empty instruction after agent name" do
      assert {nil, "@agent"} = DispatchParser.parse("@agent")
    end
  end
end
