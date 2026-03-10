defmodule Synkade.Issues.ChildParserTest do
  use ExUnit.Case, async: true

  alias Synkade.Issues.ChildParser

  describe "parse/1" do
    test "parses children from agent output" do
      output = """
      Here are the results of my research.

      <!-- SYNKADE:CHILDREN
      - title: "Implement auth module"
        kind: task
        description: "Create the authentication module"
        priority: 1
      - title: "Fix login bug"
        kind: bug
        description: "Login fails on mobile"
        priority: 2
      SYNKADE:CHILDREN -->

      That's my analysis.
      """

      children = ChildParser.parse(output)
      assert length(children) == 2

      [first, second] = children
      assert first.title == "Implement auth module"
      assert first.description == "Create the authentication module"
      assert first.priority == 1

      assert second.title == "Fix login bug"
      assert second.description == "Login fails on mobile"
      assert second.priority == 2
    end

    test "returns empty list when no markers present" do
      assert ChildParser.parse("Just some regular output") == []
    end

    test "returns empty list for nil input" do
      assert ChildParser.parse(nil) == []
    end

    test "returns empty list for empty string" do
      assert ChildParser.parse("") == []
    end

    test "defaults priority to 0" do
      output = """
      <!-- SYNKADE:CHILDREN
      - title: "Do the thing"
        kind: task
      SYNKADE:CHILDREN -->
      """

      [child] = ChildParser.parse(output)
      assert child.priority == 0
    end

    test "filters out items without title" do
      output = """
      <!-- SYNKADE:CHILDREN
      - kind: task
        description: "no title here"
      - title: "Has title"
        kind: task
      SYNKADE:CHILDREN -->
      """

      children = ChildParser.parse(output)
      assert length(children) == 1
      assert hd(children).title == "Has title"
    end

    test "handles unquoted values" do
      output = """
      <!-- SYNKADE:CHILDREN
      - title: Implement feature
        kind: task
        description: Do the thing
        priority: 3
      SYNKADE:CHILDREN -->
      """

      [child] = ChildParser.parse(output)
      assert child.title == "Implement feature"
      assert child.priority == 3
    end
  end
end
