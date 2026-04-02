defmodule SynkadeWeb.IdeDispatchHelpersTest do
  use ExUnit.Case, async: true

  alias SynkadeWeb.IdeDispatchHelpers

  describe "build_dispatch_message/3" do
    test "returns message when no attachments or uploads" do
      assert IdeDispatchHelpers.build_dispatch_message("hello", [], []) == "hello"
    end

    test "trims whitespace from message" do
      assert IdeDispatchHelpers.build_dispatch_message("  hello  ", [], []) == "hello"
    end

    test "prepends code comment attachments" do
      attachments = [
        %{type: :comment, file: "lib/foo.ex", line: "42", text: "fix this"}
      ]

      result = IdeDispatchHelpers.build_dispatch_message("please fix", attachments, [])
      assert result == "[lib/foo.ex:42] fix this\n\nplease fix"
    end

    test "combines multiple comment attachments" do
      attachments = [
        %{type: :comment, file: "a.ex", line: "1", text: "first"},
        %{type: :comment, file: "b.ex", line: "2", text: "second"}
      ]

      result = IdeDispatchHelpers.build_dispatch_message("msg", attachments, [])
      assert result =~ "[a.ex:1] first"
      assert result =~ "[b.ex:2] second"
      assert result =~ "\n\nmsg"
    end

    test "appends image upload references" do
      uploads = [%{path: ".synkade/uploads/screenshot.png"}]

      result = IdeDispatchHelpers.build_dispatch_message("check this", [], uploads)
      assert result == "[image: .synkade/uploads/screenshot.png]\n\ncheck this"
    end

    test "skips uploads with nil path" do
      uploads = [%{path: nil}, %{path: ".synkade/uploads/img.png"}]

      result = IdeDispatchHelpers.build_dispatch_message("", [], uploads)
      assert result == "[image: .synkade/uploads/img.png]"
    end

    test "returns only context when message is empty" do
      attachments = [%{type: :comment, file: "a.ex", line: "1", text: "note"}]

      result = IdeDispatchHelpers.build_dispatch_message("", attachments, [])
      assert result == "[a.ex:1] note"
    end

    test "combines attachments and uploads" do
      attachments = [%{type: :comment, file: "a.ex", line: "1", text: "note"}]
      uploads = [%{path: "img.png"}]

      result = IdeDispatchHelpers.build_dispatch_message("msg", attachments, uploads)
      assert result =~ "[a.ex:1] note"
      assert result =~ "[image: img.png]"
      assert result =~ "\n\nmsg"
    end
  end
end
