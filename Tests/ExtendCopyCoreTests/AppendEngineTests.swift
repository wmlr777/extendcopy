import Testing
@testable import ExtendCopyCore

@Test func firstCopyDoesNotAddSeparator() {
    #expect(AppendEngine.combine(previous: "", selection: "第一段", separator: .newline) == "第一段")
}

@Test func appendsUsingSelectedSeparator() {
    #expect(AppendEngine.combine(previous: "第一段", selection: "第二段", separator: .newline) == "第一段\n第二段")
    #expect(AppendEngine.combine(previous: "A", selection: "B", separator: .blankLine) == "A\n\nB")
    #expect(AppendEngine.combine(previous: "A", selection: "B", separator: .space) == "A B")
    #expect(AppendEngine.combine(previous: "A", selection: "B", separator: .comma) == "A, B")
}

@Test func emptySelectionKeepsPreviousClipboard() {
    #expect(AppendEngine.combine(previous: "已有内容", selection: "", separator: .newline) == "已有内容")
}
