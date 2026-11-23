import Foundation

/// One slash command Claude Code can run in a session.
///
/// Claude Code reports this catalog in the `initialize` control response. It
/// covers built-in commands as well as user, project, plugin, and mod commands,
/// which is why Gantry asks the CLI instead of scanning command folders: mods
/// can register commands at runtime from their hooks module.
public struct ClaudeSlashCommand: Hashable, Sendable, Identifiable {
    public var name: String
    public var description: String?
    public var argumentHint: String?
    public var isBuiltin: Bool
    public var plugin: String?
    public var aliases: [String]

    public var id: String { name }
    public var invocation: String { "/\(name)" }

    /// The extension or mod that contributed this command. Some plugin
    /// commands are reported only as `plugin:command`, so the namespace is the
    /// fallback label for the picker.
    public var sourceLabel: String? {
        if let plugin { return plugin }
        guard let colon = name.firstIndex(of: ":"), colon != name.startIndex else {
            return nil
        }
        return String(name[..<colon])
    }

    public init(
        name: String,
        description: String? = nil,
        argumentHint: String? = nil,
        isBuiltin: Bool = false,
        plugin: String? = nil,
        aliases: [String] = []
    ) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
        self.isBuiltin = isBuiltin
        self.plugin = plugin
        self.aliases = aliases
    }

    /// True when the command should be offered for a partially typed name.
    /// Aliases (for example `cost` for `usage`) match like names.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        if name.lowercased().hasPrefix(query) { return true }
        return aliases.contains { $0.lowercased().hasPrefix(query) }
    }

    /// Parses the `commands` array of the `initialize` control response.
    /// Malformed entries are skipped so one unexpected field cannot empty the
    /// whole picker.
    public static func decode(fromInitializePayload payload: JSONValue) -> [ClaudeSlashCommand] {
        guard let entries = payload.objectValue?["commands"]?.arrayValue else {
            return []
        }
        var seen = Set<String>()
        var commands: [ClaudeSlashCommand] = []
        for entry in entries {
            guard let object = entry.objectValue,
                  let name = cleaned(object["name"]?.stringValue),
                  seen.insert(name).inserted else {
                continue
            }
            var seenAliases = Set<String>()
            let aliases = (object["aliases"]?.arrayValue ?? [])
                .compactMap { cleaned($0.stringValue) }
                .filter { $0 != name && seenAliases.insert($0).inserted }
            commands.append(ClaudeSlashCommand(
                name: name,
                description: cleaned(object["description"]?.stringValue),
                argumentHint: cleaned(object["argumentHint"]?.stringValue),
                isBuiltin: object["builtin"]?.boolValue ?? false,
                plugin: cleaned(object["plugin"]?.stringValue),
                aliases: aliases
            ))
        }
        return commands
    }

    /// Appends commands that the session's `init` event listed by name but the
    /// control response did not describe (older CLI versions). Existing entries
    /// keep their descriptions and order.
    public static func merging(
        names: [String],
        into catalog: [ClaudeSlashCommand]
    ) -> [ClaudeSlashCommand] {
        var result = catalog
        var known = Set(catalog.map(\.name))
        for rawName in names {
            guard let name = cleaned(rawName), known.insert(name).inserted else {
                continue
            }
            result.append(ClaudeSlashCommand(name: name))
        }
        return result
    }

    /// Collapses runs of whitespace so a multi-line description fits in one row.
    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
