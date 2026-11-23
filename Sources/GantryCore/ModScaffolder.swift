import Foundation

public enum ModTemplate: String, CaseIterable, Codable, Sendable {
    case statusLine
    case slashCommand
    case pane
    case toolGuard
    case blank

    public var title: String {
        switch self {
        case .statusLine: return "Status line"
        case .slashCommand: return "Slash command"
        case .pane: return "Pane"
        case .toolGuard: return "Tool guard"
        case .blank: return "Blank"
        }
    }

    public var summary: String {
        switch self {
        case .statusLine:
            return "A quiet status line that shows your mod is active."
        case .slashCommand:
            return "A command that sends a reusable prompt."
        case .pane:
            return "A panel beside the chat with its own state and a starter test."
        case .toolGuard:
            return "Block edits to .env files before they run."
        case .blank:
            return "Just the manifest and an empty hooks module."
        }
    }

    public var usesStateContract: Bool {
        self == .pane
    }

    public var supportsTest: Bool {
        self == .pane
    }
}

public struct ModScaffoldRequest: Sendable {
    public var name: String
    public var description: String
    public var author: String?
    public var template: ModTemplate
    public var destinationDirectory: URL
    public var includeTest: Bool

    public init(
        name: String,
        description: String,
        author: String? = nil,
        template: ModTemplate,
        destinationDirectory: URL,
        includeTest: Bool = false
    ) {
        self.name = name
        self.description = description
        self.author = author
        self.template = template
        self.destinationDirectory = destinationDirectory
        self.includeTest = includeTest
    }
}

public struct ModScaffoldResult: Sendable {
    public var directoryURL: URL
    public var files: [URL]
    public var hasTest: Bool

    public init(directoryURL: URL, files: [URL], hasTest: Bool) {
        self.directoryURL = directoryURL
        self.files = files
        self.hasTest = hasTest
    }
}

public enum ModScaffolderError: Error, LocalizedError, Sendable {
    case invalidName(String)
    case destinationExists(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let message):
            return message
        case .destinationExists(let path):
            return "“\(path)” already exists. Choose another name or folder."
        case .writeFailed(let message):
            return "Couldn't create the mod. \(message)"
        }
    }
}

public enum ModScaffolder {
    private struct Manifest: Encodable {
        var name: String
        var version: String
        var description: String
        var author: String?
        var types: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case version
            case description
            case author
            case types
        }
    }

    private struct HooksManifest: Encodable {
        var modules: [String]
    }

    public static func validateName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == name, !name.isEmpty else {
            throw ModScaffolderError.invalidName("Enter a name using lowercase letters, numbers, and hyphens.")
        }
        guard name.count <= 64 else {
            throw ModScaffolderError.invalidName("Keep the mod name to 64 characters or fewer.")
        }
        guard name.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else {
            throw ModScaffolderError.invalidName(
                "Use lowercase letters, numbers, and single hyphens — for example “turn-counter”."
            )
        }
    }

    public static func scaffold(_ request: ModScaffoldRequest) throws -> ModScaffoldResult {
        try validateName(request.name)

        let parent = request.destinationDirectory.standardizedFileURL
        let target = parent
            .appendingPathComponent(request.name, isDirectory: true)
            .standardizedFileURL
        let parentPath = parent.resolvingSymlinksInPath().standardizedFileURL.path
        let targetPath = target.resolvingSymlinksInPath().standardizedFileURL.path
        guard targetPath.hasPrefix(parentPath + "/") else {
            throw ModScaffolderError.invalidName("The mod name must stay inside the chosen folder.")
        }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw ModScaffolderError.destinationExists(target.path)
        }

        let description = request.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = request.author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let includeTest = request.includeTest && request.template.supportsTest

        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        } catch {
            throw ModScaffolderError.writeFailed(error.localizedDescription)
        }

        do {
            var files: [String: String] = [:]
            files[".claude-plugin/plugin.json"] = try manifestJSON(
                name: request.name,
                description: description,
                author: author,
                template: request.template
            )
            files["hooks/hooks.json"] = try hooksJSON()
            files["hooks/register.tsx"] = registerSource(
                name: request.name,
                template: request.template
            )
            files["README.md"] = readme(
                name: request.name,
                description: description,
                template: request.template
            )

            if request.template.usesStateContract {
                files["types/index.d.ts"] = stateContract(name: request.name)
            }
            if includeTest {
                files["hooks/register.test.tsx"] = testSource(name: request.name)
            }

            var written: [URL] = []
            for (relativePath, content) in files {
                let url = target.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                // The directory is new and removed if any write fails, so a
                // partial mod cannot be observed. Non-atomic writes also keep
                // the scaffolder usable in restricted test sandboxes.
                try Data(content.utf8).write(to: url)
                written.append(url)
            }

            return ModScaffoldResult(
                directoryURL: target,
                files: written.sorted { $0.path < $1.path },
                hasTest: includeTest
            )
        } catch let error as ModScaffolderError {
            try? FileManager.default.removeItem(at: target)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw ModScaffolderError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Files

    private static func manifestJSON(
        name: String,
        description: String,
        author: String?,
        template: ModTemplate
    ) throws -> String {
        let manifest = Manifest(
            name: name,
            version: "0.1.0",
            description: description.isEmpty ? "A Claude Code mod created with Gantry." : description,
            author: author,
            types: template.usesStateContract ? "./types/index.d.ts" : nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func hooksJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(HooksManifest(modules: ["./register.tsx"]))
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func registerSource(name: String, template: ModTemplate) -> String {
        switch template {
        case .statusLine:
            return """
            import type { Register } from 'claude-code'

            export const register: Register = on => {
              on('session.start', ($, e, next) => {
                $.ui.status(`${$.plugin.name} is active`)
                return next(e)
              })

              on('turn.complete', ($, e, next) => {
                $.ui.status(`${$.plugin.name} · ready`)
                return next(e)
              })
            }

            """
        case .slashCommand:
            return """
            import type { Register } from 'claude-code'

            const COMMAND = '\(name)'

            export const register: Register = on => {
              on('session.start', async ($, e, next) => {
                await $.command.register({
                  name: COMMAND,
                  description: 'Starter command created with Gantry',
                })
                return next(e)
              })

              on('command.run', { command: COMMAND }, async $ => ({
                text: `Start by describing what ${$.plugin.name} should do.`,
              }))
            }

            """
        case .pane:
            return """
            import { atom, read, update } from 'claude-code'
            import type { Register } from 'claude-code'

            const PANE = '\(name)-pane'
            const count = atom({ plugin: '\(name)', key: 'count' } as const, 0)

            export const register: Register = on => {
              on('session.start', async ($, e, next) => {
                await $.command.register({
                  name: '\(name)',
                  description: 'Open the \(name) pane',
                })
                void $.ui.open({ id: PANE, title: '\(name)' })
                return next(e)
              })

              on('command.run', { command: '\(name)' }, async $ => {
                await $.ui.open({ id: PANE, title: '\(name)' })
                return { text: 'Pane opened.' }
              })

              on('tool.call', async ($, e, next) => {
                const ran = await next(e)
                await update($, count, value => value + 1)
                return ran
              })

              on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
                const { Box, Text } = $.ui.resolve(e)
                const value = await read($, count)

                return (
                  <Box flexDirection="column">
                    <Text bold>{$.plugin.name}</Text>
                    <Text dimColor>
                      {value} tool call{value === 1 ? '' : 's'} in this session
                    </Text>
                  </Box>
                )
              })
            }

            """
        case .toolGuard:
            return """
            import type { Register } from 'claude-code'

            const PROTECTED = /(^|\\/)\\.env(\\.|$)/

            export const register: Register = on => {
              on('tool.call', { tool: 'Edit' }, ($, e, next) =>
                PROTECTED.test(e.file_path)
                  ? { deny: `${$.plugin.name}: ${e.file_path} is protected here.` }
                  : next(e),
              )
            }

            """
        case .blank:
            return """
            import type { Register } from 'claude-code'

            export const register: Register = on => {
              on('session.start', ($, e, next) => next(e))
            }

            """
        }
    }

    private static func stateContract(name: String) -> String {
        """
        export type ModState = { count: number }

        declare module 'claude-code' {
          interface PluginState {
            '\(name)': { count: Shaped<number> }
          }
        }

        """
    }

    private static func testSource(name: String) -> String {
        """
        import { expect, test } from 'claude-code/testing'

        const PANE = {
          plugin: '\(name)',
          component: 'Pane',
          requestId: '\(name)-pane',
          props: {
            title: '\(name)',
            isFocused: false,
            bodyColumns: 40,
            placement: 'dock',
            scroll: { offset: 0, bodyRows: 20 },
            view: {},
          },
        } as const

        test('the pane renders', async $ => {
          const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
          expect((await ui.find({ type: 'Text', text: /\(name)/ }))?.text).toBeDefined()
          await ui.unmount()
        })

        """
    }

    private static func readme(name: String, description: String, template: ModTemplate) -> String {
        let summary = description.isEmpty
            ? "A Claude Code mod created with Gantry."
            : description
        return """
        # \(name)

        \(summary)

        Template: **\(template.title)**.

        ## Files

        - `.claude-plugin/plugin.json` — the mod manifest.
        - `hooks/hooks.json` — points Claude Code at the hooks module.
        - `hooks/register.tsx` — the hooks module.

        ## Develop

        Run these from this folder:

        ```sh
        claude plugin validate .
        claude plugin test .          # when a test file exists
        claude --plugin-dir .         # start a session with this mod loaded
        ```

        Gantry can open this folder as a project and load the mod with
        `--plugin-dir` for that project's chats.

        """
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
