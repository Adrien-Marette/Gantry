import Foundation
import Testing
@testable import GantryCore

private func payload(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

@Test func decodesCommandCatalogFromInitializePayload() throws {
    let value = try payload(
        """
        {
          "commands": [
            {
              "name": "commit",
              "description": "Create a Conventional Commit\\nwith a generated message",
              "argumentHint": "[scope]"
            },
            {
              "name": "usage",
              "description": "Show session usage",
              "argumentHint": "",
              "builtin": true,
              "aliases": ["cost", "stats", "cost"]
            },
            {
              "name": "cache-tax",
              "description": "Prompt cache state",
              "plugin": "cache-tax",
              "aliases": []
            },
            {"description": "Missing a name"},
            {"name": ""},
            {"name": "commit", "description": "Duplicate"}
          ]
        }
        """
    )

    let commands = ClaudeSlashCommand.decode(fromInitializePayload: value)
    #expect(commands.map(\.name) == ["commit", "usage", "cache-tax"])

    let commit = try #require(commands.first)
    #expect(commit.description == "Create a Conventional Commit with a generated message")
    #expect(commit.argumentHint == "[scope]")
    #expect(commit.isBuiltin == false)
    #expect(commit.plugin == nil)

    let usage = try #require(commands.dropFirst().first)
    #expect(usage.isBuiltin)
    #expect(usage.aliases == ["cost", "stats"])
    #expect(usage.argumentHint == nil)

    let plugin = try #require(commands.last)
    #expect(plugin.plugin == "cache-tax")
    #expect(plugin.invocation == "/cache-tax")
    #expect(plugin.sourceLabel == "cache-tax")

    let namespaced = ClaudeSlashCommand(name: "claude-md-management:revise")
    #expect(namespaced.sourceLabel == "claude-md-management")
    #expect(ClaudeSlashCommand(name: "compact", isBuiltin: true).sourceLabel == nil)
}

@Test func malformedInitializePayloadYieldsNoCommands() throws {
    #expect(ClaudeSlashCommand.decode(fromInitializePayload: .string("nope")).isEmpty)
    #expect(ClaudeSlashCommand.decode(fromInitializePayload: .object([:])).isEmpty)
    #expect(ClaudeSlashCommand.decode(fromInitializePayload: try payload(#"{"commands":{}}"#)).isEmpty)
}

@Test func mergingInitNamesKeepsDescribedCommands() {
    let described = ClaudeSlashCommand(
        name: "commit",
        description: "Create a commit",
        argumentHint: "[scope]"
    )
    let merged = ClaudeSlashCommand.merging(
        names: ["commit", "verify", "verify", " ", "commit"],
        into: [described]
    )

    #expect(merged.map(\.name) == ["commit", "verify"])
    #expect(merged.first?.description == "Create a commit")
    #expect(merged.last?.description == nil)
}

@Test func matchingUsesNamesAliasesAndPrefixes() {
    let command = ClaudeSlashCommand(
        name: "usage",
        aliases: ["cost", "stats"]
    )

    #expect(command.matches(""))
    #expect(command.matches("us"))
    #expect(command.matches("USAGE"))
    #expect(command.matches("co"))
    #expect(!command.matches("comm"))
    #expect(!command.matches("usage extra"))

    let builtin = ClaudeSlashCommand(name: "compact", isBuiltin: true)
    #expect(builtin.matches("co"))
    #expect(builtin.matches("comp"))
    #expect(!builtin.matches("xyz"))
}
