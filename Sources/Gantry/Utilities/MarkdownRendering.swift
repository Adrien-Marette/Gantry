import Foundation
import SwiftUI

private final class AttributedStringBox {
    let value: AttributedString

    init(_ value: AttributedString) {
        self.value = value
    }
}

private enum MarkdownRenderCache {
    static let inline: NSCache<NSString, AttributedStringBox> = {
        let cache = NSCache<NSString, AttributedStringBox>()
        cache.countLimit = 2_000
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()

    static let code: NSCache<NSString, AttributedStringBox> = {
        let cache = NSCache<NSString, AttributedStringBox>()
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()
}

enum InlineMarkdown {
    static func attributed(_ text: String) -> AttributedString {
        let key = text as NSString
        if let cached = MarkdownRenderCache.inline.object(forKey: key) {
            return cached.value
        }
        let value = parse(text)
        MarkdownRenderCache.inline.setObject(
            AttributedStringBox(value),
            forKey: key,
            cost: text.utf8.count
        )
        return value
    }

    private static func parse(_ text: String) -> AttributedString {
        var result: AttributedString
        do {
            result = try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return AttributedString(text)
        }

        for run in result.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                result[run.range].font = .system(size: 12, weight: .regular, design: .monospaced)
                result[run.range].foregroundColor = Palette.ink
                result[run.range].backgroundColor = Palette.ink.opacity(0.06)
            }
        }
        for run in result.runs {
            if run.link != nil {
                result[run.range].foregroundColor = Palette.accent
                result[run.range].underlineStyle = .single
            }
        }
        return result
    }
}

enum CodeSyntax {
    static func highlighted(_ code: String, language: String?) -> AttributedString {
        let normalizedLanguage = (language ?? "").lowercased()
        let key = "\u{0}\(normalizedLanguage)\u{0}\(code)" as NSString
        if let cached = MarkdownRenderCache.code.object(forKey: key) {
            return cached.value
        }
        let value = highlightedUncached(code, language: language)
        MarkdownRenderCache.code.setObject(
            AttributedStringBox(value),
            forKey: key,
            cost: code.utf8.count
        )
        return value
    }

    private static func highlightedUncached(_ code: String, language: String?) -> AttributedString {
        if code.count > 30_000 {
            var plain = AttributedString(code)
            plain.foregroundColor = Palette.codePlain
            return plain
        }
        let profile = LanguageProfile(language: language)
        var result = AttributedString()
        for (lineIndex, line) in code.components(separatedBy: "\n").enumerated() {
            if lineIndex > 0 {
                result.append(AttributedString("\n"))
            }
            appendLine(line, profile: profile, to: &result)
        }
        return result
    }

    private static func appendLine(
        _ line: String,
        profile: LanguageProfile,
        to result: inout AttributedString
    ) {
        let characters = Array(line)
        var index = 0

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if profile.lineCommentMarkers.contains(where: { trimmed.hasPrefix($0) }) {
            append(String(characters), color: Palette.codeComment, font: commentFont, to: &result)
            return
        }
        if profile.language == "html", trimmed.hasPrefix("<!--") {
            append(line, color: Palette.codeComment, font: commentFont, to: &result)
            return
        }

        while index < characters.count {
            let character = characters[index]

            if character == " " || character == "\t" {
                var end = index
                while end < characters.count, characters[end] == " " || characters[end] == "\t" {
                    end += 1
                }
                append(String(characters[index..<end]), color: Palette.codePlain, to: &result)
                index = end
                continue
            }

            if profile.lineCommentMarkers.contains(where: { marker in
                matches(marker, at: index, in: characters)
            }) {
                append(String(characters[index...]), color: Palette.codeComment, font: commentFont, to: &result)
                break
            }

            if isQuote(character), profile.usesStrings {
                let end = scanString(from: index, in: characters, quote: character)
                append(String(characters[index..<end]), color: Palette.codeString, to: &result)
                index = end
                continue
            }

            if character.isNumber {
                var end = index
                while end < characters.count,
                      characters[end].isNumber || characters[end] == "." || characters[end] == "_"
                        || characters[end] == "x" || characters[end] == "e"
                        || characters[end] == "+" || characters[end] == "-" {
                    if characters[end] == "+" || characters[end] == "-",
                       end > index,
                       !(characters[end - 1] == "e" || characters[end - 1] == "E") {
                        break
                    }
                    end += 1
                }
                append(String(characters[index..<end]), color: Palette.codeNumber, to: &result)
                index = end
                continue
            }

            if isIdentifierStart(character) {
                var end = index
                while end < characters.count, isIdentifierBody(characters[end]) {
                    end += 1
                }
                let word = String(characters[index..<end])
                let color: Color
                if profile.keywords.contains(word) {
                    color = Palette.codeKeyword
                } else if profile.types.contains(word) || (word.first?.isUppercase == true && word.count > 1) {
                    color = Palette.codeType
                } else if nextNonSpaceCharacter(after: end, in: characters) == "(" {
                    color = Palette.codeFunction
                } else {
                    color = Palette.codePlain
                }
                append(
                    word,
                    color: color,
                    font: profile.keywords.contains(word) ? keywordFont : nil,
                    to: &result
                )
                index = end
                continue
            }

            append(String(character), color: Palette.codePlain, to: &result)
            index += 1
        }
    }

    private static let keywordFont = Font.system(size: 12, weight: .medium, design: .monospaced)
    private static let commentFont = Font.system(size: 12, weight: .regular, design: .monospaced)

    private static func append(
        _ string: String,
        color: Color,
        font: Font? = nil,
        to result: inout AttributedString
    ) {
        var piece = AttributedString(string)
        piece.foregroundColor = color
        if let font {
            piece.font = font
        }
        result.append(piece)
    }

    private static func matches(_ marker: String, at index: Int, in characters: [Character]) -> Bool {
        let markerCharacters = Array(marker)
        guard index + markerCharacters.count <= characters.count else { return false }
        for offset in markerCharacters.indices {
            if characters[index + offset] != markerCharacters[offset] { return false }
        }
        return true
    }

    private static func scanString(from start: Int, in characters: [Character], quote: Character) -> Int {
        var index = start + 1
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
                index += 1
                continue
            }
            if character == "\\" {
                escaped = true
                index += 1
                continue
            }
            if character == quote {
                return index + 1
            }
            index += 1
        }
        return characters.count
    }

    private static func isQuote(_ character: Character) -> Bool {
        character == "\"" || character == "'" || character == "`"
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$" || character == "@"
    }

    private static func isIdentifierBody(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    private static func nextNonSpaceCharacter(after index: Int, in characters: [Character]) -> Character? {
        var cursor = index
        while cursor < characters.count {
            let character = characters[cursor]
            if character != " " && character != "\t" { return character }
            cursor += 1
        }
        return nil
    }
}

private struct LanguageProfile {
    let language: String
    let lineCommentMarkers: [String]
    let keywords: Set<String>
    let types: Set<String>
    let usesStrings: Bool

    init(language: String?) {
        let raw = (language ?? "").lowercased()
        let normalized: String
        switch raw {
        case "swift": normalized = "swift"
        case "js", "javascript", "jsx", "mjs", "cjs": normalized = "javascript"
        case "ts", "typescript", "tsx": normalized = "typescript"
        case "py", "python": normalized = "python"
        case "sh", "bash", "zsh", "shell", "console": normalized = "shell"
        case "json": normalized = "json"
        case "html", "xml", "svg": normalized = "html"
        case "css", "scss": normalized = "css"
        case "c", "h": normalized = "c"
        case "cpp", "c++", "hpp", "objc", "objective-c": normalized = "cpp"
        case "rs", "rust": normalized = "rust"
        case "go", "golang": normalized = "go"
        case "sql": normalized = "sql"
        case "yml", "yaml": normalized = "yaml"
        case "md", "markdown": normalized = "markdown"
        default: normalized = raw.isEmpty ? "plain" : raw
        }
        self.language = normalized

        switch normalized {
        case "swift":
            lineCommentMarkers = ["//"]
            keywords = Self.swiftKeywords
            types = Self.swiftTypes
            usesStrings = true
        case "javascript", "typescript":
            lineCommentMarkers = ["//"]
            keywords = normalized == "typescript" ? Self.tsKeywords : Self.jsKeywords
            types = Self.jsTypes
            usesStrings = true
        case "python":
            lineCommentMarkers = ["#"]
            keywords = Self.pythonKeywords
            types = Self.pythonTypes
            usesStrings = true
        case "shell":
            lineCommentMarkers = ["#"]
            keywords = Self.shellKeywords
            types = ["echo", "cd", "ls", "git", "npm", "swift", "claude"]
            usesStrings = true
        case "c", "cpp":
            lineCommentMarkers = ["//"]
            keywords = Self.cKeywords
            types = Self.cTypes
            usesStrings = true
        case "rust":
            lineCommentMarkers = ["//"]
            keywords = Self.rustKeywords
            types = Self.rustTypes
            usesStrings = true
        case "go":
            lineCommentMarkers = ["//"]
            keywords = Self.goKeywords
            types = Self.goTypes
            usesStrings = true
        case "sql":
            lineCommentMarkers = ["--"]
            keywords = Self.sqlKeywords
            types = []
            usesStrings = true
        case "yaml":
            lineCommentMarkers = ["#"]
            keywords = []
            types = []
            usesStrings = true
        case "json":
            lineCommentMarkers = []
            keywords = ["true", "false", "null"]
            types = []
            usesStrings = true
        case "html":
            lineCommentMarkers = []
            keywords = []
            types = []
            usesStrings = true
        case "css":
            lineCommentMarkers = ["//"]
            keywords = []
            types = []
            usesStrings = true
        case "markdown":
            lineCommentMarkers = [">"]
            keywords = []
            types = []
            usesStrings = false
        default:
            lineCommentMarkers = ["//", "#"]
            keywords = []
            types = []
            usesStrings = true
        }
    }

    static let swiftKeywords: Set<String> = [
        "actor", "associatedtype", "async", "await", "break", "case", "catch", "class",
        "continue", "convenience", "default", "defer", "deinit", "do", "else", "enum",
        "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "guard",
        "if", "import", "in", "indirect", "init", "inout", "internal", "is", "let", "mutating",
        "nonisolated", "nil", "open", "operator", "private", "protocol", "public", "repeat",
        "required", "rethrows", "return", "self", "Self", "some", "static", "struct",
        "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias",
        "var", "where", "while", "willSet", "didSet", "any", "consume", "borrowing"
    ]

    static let swiftTypes: Set<String> = [
        "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set",
        "Optional", "Result", "Error", "View", "Color", "URL", "Date", "UUID",
        "Task", "MainActor", "Sendable", "Codable", "Hashable", "Identifiable"
    ]

    static let jsKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue",
        "debugger", "default", "delete", "do", "else", "export", "extends", "false",
        "finally", "for", "from", "function", "get", "if", "import", "in", "instanceof",
        "let", "new", "null", "of", "return", "set", "static", "super", "switch",
        "this", "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "yield"
    ]

    static let tsKeywords: Set<String> = jsKeywords.union([
        "interface", "implements", "enum", "type", "namespace", "public", "private",
        "protected", "readonly", "declare", "abstract", "as", "satisfies", "keyof", "infer"
    ])

    static let jsTypes: Set<String> = [
        "Promise", "Array", "Object", "String", "Number", "Boolean", "Map", "Set",
        "Response", "Request", "Error", "Date", "Record", "Partial", "Readonly"
    ]

    static let pythonKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def",
        "del", "elif", "else", "except", "False", "finally", "for", "from", "global",
        "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass",
        "raise", "return", "True", "try", "while", "with", "yield", "match", "case"
    ]

    static let pythonTypes: Set<String> = [
        "str", "int", "float", "bool", "list", "dict", "tuple", "set", "Exception",
        "Path", "Optional", "Any", "Callable"
    ]

    static let shellKeywords: Set<String> = [
        "if", "then", "elif", "else", "fi", "for", "while", "do", "done", "case",
        "esac", "function", "in", "return", "export", "local", "echo", "set", "unset"
    ]

    static let cKeywords: Set<String> = [
        "auto", "break", "case", "char", "class", "const", "continue", "default",
        "delete", "do", "double", "else", "enum", "explicit", "extern", "false", "float",
        "for", "friend", "goto", "if", "inline", "int", "long", "namespace", "new",
        "nullptr", "operator", "private", "protected", "public", "register", "return",
        "short", "signed", "sizeof", "static", "struct", "switch", "template", "this",
        "throw", "true", "try", "typedef", "typename", "union", "unsigned", "using",
        "virtual", "void", "volatile", "while"
    ]

    static let cTypes: Set<String> = [
        "std", "string", "vector", "map", "shared_ptr", "unique_ptr", "size_t", "uint32_t",
        "int64_t", "Juce", "juce", "String", "Component"
    ]

    static let rustKeywords: Set<String> = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
        "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
        "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static",
        "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"
    ]

    static let rustTypes: Set<String> = [
        "String", "Vec", "Option", "Result", "Box", "Arc", "Rc", "HashMap", "HashSet",
        "usize", "isize", "u8", "u16", "u32", "u64", "i32", "i64", "f32", "f64", "bool", "str"
    ]

    static let goKeywords: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else",
        "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
        "package", "range", "return", "select", "struct", "switch", "type", "var",
        "nil", "true", "false"
    ]

    static let goTypes: Set<String> = [
        "string", "int", "int64", "uint", "uint64", "float64", "bool", "byte", "rune",
        "error", "any", "Context", "Reader", "Writer"
    ]

    static let sqlKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "TABLE", "INDEX", "DROP", "ALTER", "JOIN", "LEFT", "RIGHT", "INNER",
        "OUTER", "ON", "AS", "AND", "OR", "NOT", "NULL", "GROUP", "BY", "ORDER", "LIMIT",
        "OFFSET", "HAVING", "DISTINCT", "COUNT", "SUM", "AVG", "MIN", "MAX", "CASE", "WHEN",
        "THEN", "ELSE", "END", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE"
    ]
}
