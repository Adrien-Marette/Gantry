import Testing
@testable import GantryCore

@Test func parsesPlainTextMarkdown() {
    let blocks = MarkdownParser.parse("Hello **world**.\n\nSecond paragraph.")
    #expect(blocks == [.paragraph("Hello **world**."), .paragraph("Second paragraph.")])
}

@Test func parsesFencedCodeWithLanguage() {
    let text = """
    Before

    ```swift
    let answer = 42
    print(answer)
    ```

    After
    """
    let blocks = MarkdownParser.parse(text)
    #expect(blocks.count == 3)
    #expect(blocks[1] == .code(language: "swift", code: "let answer = 42\nprint(answer)", isClosed: true))
}

@Test func treatsOpenFenceAsCode() {
    let blocks = MarkdownParser.parse("```sh\necho hello")
    #expect(blocks == [.code(language: "sh", code: "echo hello", isClosed: false)])
}

@Test func parsesListsAndTaskItems() {
    let blocks = MarkdownParser.parse("""
    - One
    - [x] Done
      - Nested
    """)
    guard case .list(let ordered, let items) = blocks.first else {
        Issue.record("Expected a list")
        return
    }
    #expect(!ordered)
    #expect(items.count == 3)
    #expect(items[1].checked == true)
    #expect(items[2].depth == 1)
}

@Test func parsesTable() {
    let text = """
    | Name | Value |
    | :--- | ---: |
    | One | 1 |
    | Two | 2 |
    """
    let blocks = MarkdownParser.parse(text)
    guard case .table(let headers, let alignments, let rows) = blocks.first else {
        Issue.record("Expected a table")
        return
    }
    #expect(headers == ["Name", "Value"])
    #expect(alignments == [.leading, .trailing])
    #expect(rows.count == 2)
    #expect(rows[1] == ["Two", "2"])
}
