import Foundation

public enum CopySeparator: String, CaseIterable, Sendable {
    case newline
    case blankLine
    case space
    case comma

    public var value: String {
        switch self {
        case .newline: "\n"
        case .blankLine: "\n\n"
        case .space: " "
        case .comma: ", "
        }
    }

    public var displayName: String {
        switch self {
        case .newline: "换行"
        case .blankLine: "空行"
        case .space: "空格"
        case .comma: "逗号"
        }
    }
}

public enum AppendEngine {
    public static func combine(
        previous: String,
        selection: String,
        separator: CopySeparator
    ) -> String {
        guard !previous.isEmpty else { return selection }
        guard !selection.isEmpty else { return previous }
        return previous + separator.value + selection
    }
}
