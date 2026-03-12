defmodule Synkade.Issues.ChildParserTest do
  use ExUnit.Case, async: true

  alias Synkade.Issues.ChildParser

  describe "parse/1" do
    test "parses children from agent output with title+description (backwards compat)" do
      output = """
      Here are the results of my research.

      <!-- SYNKADE:CHILDREN
      - title: "Implement auth module"
        kind: task
        description: "Create the authentication module"
      - title: "Fix login bug"
        kind: bug
        description: "Login fails on mobile"
      SYNKADE:CHILDREN -->

      That's my analysis.
      """

      children = ChildParser.parse(output)
      assert length(children) == 2

      [first, second] = children
      assert first.body == "# Implement auth module\n\nCreate the authentication module"
      assert second.body == "# Fix login bug\n\nLogin fails on mobile"
    end

    test "parses children with body key directly" do
      output = """
      <!-- SYNKADE:CHILDREN
      - body: "# Do the thing\\n\\nDetails here"
      SYNKADE:CHILDREN -->
      """

      [child] = ChildParser.parse(output)
      assert child.body == "# Do the thing\\n\\nDetails here"
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

    test "title-only produces heading body" do
      output = """
      <!-- SYNKADE:CHILDREN
      - title: "Do the thing"
        kind: task
      SYNKADE:CHILDREN -->
      """

      [child] = ChildParser.parse(output)
      assert child.body == "# Do the thing"
    end

    test "filters out items without title or body" do
      output = """
      <!-- SYNKADE:CHILDREN
      - kind: task
      - title: "Has title"
        kind: task
      SYNKADE:CHILDREN -->
      """

      children = ChildParser.parse(output)
      assert length(children) == 1
      assert hd(children).body == "# Has title"
    end

    test "handles unquoted values" do
      output = """
      <!-- SYNKADE:CHILDREN
      - title: Implement feature
        kind: task
        description: Do the thing
      SYNKADE:CHILDREN -->
      """

      [child] = ChildParser.parse(output)
      assert child.body == "# Implement feature\n\nDo the thing"
    end
  end
end
