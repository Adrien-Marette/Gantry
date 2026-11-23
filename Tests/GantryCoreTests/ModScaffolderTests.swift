import Foundation
import Testing
@testable import GantryCore

private func scaffoldRoot() -> URL {
    GantryTestTempRoot.url
        .appendingPathComponent("Gantry-mod-scaffold-\(UUID().uuidString)", isDirectory: true)
}

private func manifest(at modURL: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: modURL.appendingPathComponent(".claude-plugin/plugin.json"))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func scaffoldsEveryTemplate() throws {
    for template in ModTemplate.allCases {
        let root = scaffoldRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let request = ModScaffoldRequest(
            name: "test-mod",
            description: "A test mod",
            author: "Tester",
            template: template,
            destinationDirectory: root,
            includeTest: true
        )
        let result = try ModScaffolder.scaffold(request)

        let modURL = result.directoryURL
        #expect(FileManager.default.fileExists(atPath: modURL.appendingPathComponent(".claude-plugin/plugin.json").path))
        #expect(FileManager.default.fileExists(atPath: modURL.appendingPathComponent("hooks/hooks.json").path))
        #expect(FileManager.default.fileExists(atPath: modURL.appendingPathComponent("hooks/register.tsx").path))
        #expect(FileManager.default.fileExists(atPath: modURL.appendingPathComponent("README.md").path))

        let json = try manifest(at: modURL)
        #expect(json["name"] as? String == "test-mod")
        #expect(json["version"] as? String == "0.1.0")
        #expect(json["description"] as? String == "A test mod")
        #expect(json["author"] as? String == "Tester")

        if template.usesStateContract {
            #expect(FileManager.default.fileExists(atPath: modURL.appendingPathComponent("types/index.d.ts").path))
            #expect(json["types"] as? String == "./types/index.d.ts")
        } else {
            #expect(json["types"] == nil)
        }

        #expect(result.hasTest == template.supportsTest)
        #expect(FileManager.default.fileExists(
            atPath: modURL.appendingPathComponent("hooks/register.test.tsx").path
        ) == template.supportsTest)

        let hooksData = try Data(contentsOf: modURL.appendingPathComponent("hooks/hooks.json"))
        let hooks = try #require(try JSONSerialization.jsonObject(with: hooksData) as? [String: Any])
        let modules = try #require(hooks["modules"] as? [String])
        #expect(modules == ["./register.tsx"])
    }
}

@Test func rejectsInvalidNames() throws {
    let invalid = [
        "",
        "Bad Name",
        "bad_name",
        "../escape",
        "a/b",
        "trailing-",
        "-leading",
        String(repeating: "a", count: 65)
    ]

    for name in invalid {
        do {
            try ModScaffolder.validateName(name)
            Issue.record("Expected invalid name: \(name)")
        } catch let error as ModScaffolderError {
            guard case .invalidName = error else {
                Issue.record("Unexpected error for \(name): \(error)")
                continue
            }
        } catch {
            Issue.record("Unexpected error for \(name): \(error)")
        }
    }

    try ModScaffolder.validateName("turn-counter")
    try ModScaffolder.validateName("x")
    try ModScaffolder.validateName("a1-b2-c3")
}

@Test func rejectsExistingDestination() throws {
    let root = scaffoldRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let existing = root.appendingPathComponent("taken", isDirectory: true)
    try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

    let request = ModScaffoldRequest(
        name: "taken",
        description: "",
        template: .blank,
        destinationDirectory: root
    )

    do {
        _ = try ModScaffolder.scaffold(request)
        Issue.record("Expected destinationExists")
    } catch let error as ModScaffolderError {
        guard case .destinationExists = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }
}

@Test func descriptionIsJSONEscaped() throws {
    let root = scaffoldRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let description = "Quotes \"here\" and a\nnewline"
    let result = try ModScaffolder.scaffold(
        ModScaffoldRequest(
            name: "escaped",
            description: description,
            template: .blank,
            destinationDirectory: root
        )
    )

    let json = try manifest(at: result.directoryURL)
    #expect(json["description"] as? String == description)
}

@Test func testFileIsOnlyGeneratedForPane() throws {
    let root = scaffoldRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    for template in ModTemplate.allCases {
        let result = try ModScaffolder.scaffold(
            ModScaffoldRequest(
                name: "test-\(template.rawValue.lowercased())",
                description: "",
                template: template,
                destinationDirectory: root,
                includeTest: true
            )
        )
        #expect(result.hasTest == (template == .pane))
    }
}

@Test func emptyDescriptionFallsBackToDefault() throws {
    let root = scaffoldRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let result = try ModScaffolder.scaffold(
        ModScaffoldRequest(
            name: "default-description",
            description: "   ",
            template: .blank,
            destinationDirectory: root
        )
    )
    let json = try manifest(at: result.directoryURL)
    #expect(json["description"] as? String == "A Claude Code mod created with Gantry.")
}

@Test func modScaffoldCLIValidation() async throws {
    guard ProcessInfo.processInfo.environment["Gantry_RUN_CLI_INTEGRATION"] == "1" else {
        return
    }
    guard let claudeURL = ClaudeLocator.locate() else {
        return
    }

    let runner = ProcessClaudePluginRunner(executableURL: claudeURL)
    for template in ModTemplate.allCases {
        let root = scaffoldRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try ModScaffolder.scaffold(
            ModScaffoldRequest(
                name: "validate-\(template.rawValue.lowercased())",
                description: "Validation fixture",
                template: template,
                destinationDirectory: root,
                includeTest: false
            )
        )

        let validation = try await runner.run(
            arguments: ["plugin", "validate", result.directoryURL.path, "--json"],
            timeout: 60
        )
        #expect(
            validation.exitCode == 0,
            "Template \(template.rawValue) failed validation: \(validation.stdout)\n\(validation.stderr)"
        )
    }
}
