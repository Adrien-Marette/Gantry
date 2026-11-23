import Foundation

public enum MarkdownAlignment: String, Hashable, Sendable {
    case leading
    case center
    case trailing
    case none
}

public struct MarkdownListItem: Hashable, Sendable {
    public var text: String
    public var checked: Bool?
    public var depth: Int

    public init(text: String, checked: Bool? = nil, depth: Int = 0) {
        self.text = text
        self.checked = checked
        self.depth = depth
    }
}

public enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [MarkdownListItem])
    case code(language: String?, code: String, isClosed: Bool)
    case quote(String)
    case table(headers: [String], alignments: [MarkdownAlignment], rows: [[String]])
    case divider
}

public enum MarkdownParser {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = fenceStart(trimmed) {
                flushParagraph()
                var codeLines: [String] = []
                var closed = false
                index += 1
                while index < lines.count {
                    let candidate = lines[index]
                    if isFenceEnd(candidate, char: fence.char, minimumCount: fence.count) {
                        closed = true
                        index += 1
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }
                blocks.append(.code(
                    language: fence.language,
                    code: codeLines.joined(separator: "\n"),
                    isClosed: closed
                ))
                continue
            }

            if let heading = headingBlock(trimmed) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if isTableStart(at: index, lines: lines) {
                flushParagraph()
                let table = parseTable(at: index, lines: lines)
                blocks.append(table.block)
                index = table.nextIndex
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    let content = candidate.dropFirst()
                        .trimmingCharacters(in: .whitespaces)
                    quoteLines.append(content)
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if listItem(line, ordered: false) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                while index < lines.count, let item = listItem(lines[index], ordered: false) {
                    items.append(item.item)
                    index += 1
                }
                blocks.append(.list(ordered: false, items: items))
                continue
            }

            if listItem(line, ordered: true) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                while index < lines.count, let item = listItem(lines[index], ordered: true) {
                    items.append(item.item)
                    index += 1
                }
                blocks.append(.list(ordered: true, items: items))
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func fenceStart(_ line: String) -> (char: Character, count: Int, language: String?)? {
        let stripped = stripUpToThreeSpaces(line)
        guard let first = stripped.first, first == "`" || first == "~" else { return nil }
        let fenceCount = stripped.prefix(while: { $0 == first }).count
        guard fenceCount >= 3 else { return nil }
        let rest = stripped.dropFirst(fenceCount).trimmingCharacters(in: .whitespaces)
        guard !rest.contains(String(first)) else { return nil }
        let language = rest.split(whereSeparator: \.isWhitespace).first.map(String.init)
        return (first, fenceCount, language)
    }

    private static func isFenceEnd(_ line: String, char: Character, minimumCount: Int) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard stripped.first == char else { return false }
        let count = stripped.prefix(while: { $0 == char }).count
        guard count >= minimumCount else { return false }
        return stripped.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func headingBlock(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let content = rest.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return .heading(level: hashes, text: content)
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return ["---", "***", "___"].contains(String(compact.prefix(3)))
            && compact.allSatisfy { $0 == compact.first }
    }

    private static func isTableStart(at index: Int, lines: [String]) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index]
        let delimiter = lines[index + 1]
        guard header.contains("|"), delimiter.contains("|") else { return false }
        let cells = splitTableRow(delimiter)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 1 else { return false }
            let dashes = trimmed.replacingOccurrences(of: ":", with: "")
            return !dashes.isEmpty && dashes.allSatisfy { $0 == "-" } && trimmed.contains("-")
        }
    }

    private static func parseTable(at index: Int, lines: [String]) -> (block: MarkdownBlock, nextIndex: Int) {
        let headers = splitTableRow(lines[index]).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let delimiters = splitTableRow(lines[index + 1]).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let alignments = delimiters.map { cell -> MarkdownAlignment in
            let leading = cell.hasPrefix(":")
            let trailing = cell.hasSuffix(":")
            switch (leading, trailing) {
            case (true, true): return .center
            case (true, false): return .leading
            case (false, true): return .trailing
            case (false, false): return .none
            }
        }
        var rows: [[String]] = []
        var cursor = index + 2
        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }
            var cells = splitTableRow(line).map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.count < headers.count {
                cells.append(contentsOf: Array(repeating: "", count: headers.count - cells.count))
            }
            if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            cursor += 1
        }
        return (.table(headers: headers, alignments: alignments, rows: rows), cursor)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        var inCode = false
        for character in line.trimmingCharacters(in: .whitespaces) {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                current.append(character)
                continue
            }
            if character == "`" {
                inCode.toggle()
                current.append(character)
                continue
            }
            if character == "|", !inCode {
                cells.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        if !current.isEmpty {
            cells.append(current)
        }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("|"), cells.first?.isEmpty == true {
            cells.removeFirst()
        }
        if line.trimmingCharacters(in: .whitespaces).hasSuffix("|"), cells.last?.isEmpty == true {
            cells.removeLast()
        }
        return cells
    }

    private static func listItem(_ line: String, ordered: Bool) -> (item: MarkdownListItem, consumed: Bool)? {
        let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { count, char in
            count + (char == "\t" ? 4 : 1)
        }
        let depth = max(0, leadingSpaces / 2)
        let stripped = line.dropFirst(leadingSpaces)
        guard !stripped.isEmpty else { return nil }

        let markerLength: Int
        if ordered {
            let digits = stripped.prefix(while: \.isNumber)
            guard !digits.isEmpty,
                  stripped.dropFirst(digits.count).first == ".",
                  stripped.dropFirst(digits.count + 1).first == " " else { return nil }
            markerLength = digits.count + 2
        } else {
            guard let first = stripped.first, ["-", "*", "+"].contains(first),
                  stripped.dropFirst().first == " " else { return nil }
            markerLength = 2
        }

        var content = String(stripped.dropFirst(markerLength))
            .trimmingCharacters(in: .whitespaces)
        var checked: Bool?
        if content.hasPrefix("[ ] ") {
            checked = false
            content = String(content.dropFirst(4))
        } else if content.lowercased().hasPrefix("[x] ") {
            checked = true
            content = String(content.dropFirst(4))
        }
        return (MarkdownListItem(text: content, checked: checked, depth: depth), true)
    }

    private static func stripUpToThreeSpaces(_ line: String) -> String {
        var result = line
        var removed = 0
        while removed < 3, result.first == " " {
            result.removeFirst()
            removed += 1
        }
        return result
    }
}
