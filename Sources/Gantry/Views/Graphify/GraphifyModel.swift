import AppKit
import Foundation
import Observation
import GantryCore

@MainActor
@Observable
final class GraphifyModel {
    var status: GraphifyStatus?
    var cliVersion: String?
    var isRefreshing = false
    var isInstalling = false
    var isBuilding = false
    var isQuerying = false
    var actionOutput: String?
    var actionError: String?
    var query = ""
    var queryResult: String?
    var queryError: String?

    private(set) var projectID: UUID?
    private(set) var projectURL: URL?
    private(set) var projectName = ""

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var statusLoadGeneration: UInt = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: - Derived state

    var hasCLI: Bool { status?.cliURL != nil }
    var hasMCP: Bool { status?.mcpURL != nil }
    var hasGraph: Bool { status?.graphExists == true }
    var hasHTML: Bool { status?.htmlURL != nil }
    var hasUV: Bool { status?.uvURL != nil }
    var isBusy: Bool { isInstalling || isBuilding || isQuerying }
    var canQuery: Bool { hasCLI && hasGraph && !isBusy }

    /// Reinstalling adds the MCP extra to an existing CLI install.
    var installNeedsForce: Bool { hasCLI && !hasMCP }
    var installCommand: String {
        GraphifyCommand.installMCPDisplay(force: installNeedsForce)
    }

    var cliSummary: String {
        if let cliVersion { return cliVersion }
        return hasCLI ? "Installed" : "Not installed"
    }

    var mcpSummary: String {
        hasMCP ? "Ready" : "Not installed"
    }

    var graphSummary: String {
        guard let status else { return "Reading graph status…" }
        guard status.graphExists else {
            return "No graph yet for this project."
        }
        var parts = ["graphify-out/graph.json"]
        if let bytes = status.graphByteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        if let modified = status.graphModifiedAt {
            parts.append("Updated \(Format.relativeTime(modified))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Loading

    func refresh(project: Project) async {
        if projectID != project.id {
            status = nil
            cliVersion = nil
            actionOutput = nil
            actionError = nil
            query = ""
            queryResult = nil
            queryError = nil
        }
        projectID = project.id
        projectURL = project.url
        projectName = project.name
        isRefreshing = true
        defer { isRefreshing = false }
        await loadStatus()
    }

    func reload() async {
        guard let projectURL else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await loadStatus(at: projectURL)
    }

    func clear() {
        projectID = nil
        projectURL = nil
        projectName = ""
        status = nil
        cliVersion = nil
        actionOutput = nil
        actionError = nil
        queryResult = nil
        queryError = nil
    }

    private func loadStatus() async {
        guard let projectURL else { return }
        await loadStatus(at: projectURL)
    }

    private func loadStatus(at url: URL) async {
        statusLoadGeneration &+= 1
        let generation = statusLoadGeneration
        let status = GraphifyStatus.read(projectURL: url)
        var version: String?
        if let cliURL = status.cliURL,
           let result = try? await GraphifyProcess.run(
               executable: cliURL,
               arguments: GraphifyCommand.version(),
               workingDirectory: url,
               timeout: 5
           ),
           result.exitCode == 0 {
            version = result.output
                .split(separator: "\n")
                .first
                .map(String.init)
        }
        // The project or the latest status request may have changed.
        guard projectURL == url, statusLoadGeneration == generation else { return }
        self.status = status
        cliVersion = version
    }

    // MARK: - Actions

    func install() async {
        guard let status, let uvURL = status.uvURL else {
            actionError = "uv was not found. Install uv, then try again."
            return
        }
        guard !isBusy else { return }

        let startedProject = projectURL
        isInstalling = true
        actionError = nil
        actionOutput = nil
        defer { isInstalling = false }

        do {
            let result = try await GraphifyProcess.run(
                executable: uvURL,
                arguments: GraphifyCommand.installMCP(force: installNeedsForce),
                workingDirectory: startedProject,
                timeout: 600
            )
            if !result.timedOut, result.exitCode == 0 {
                app.invalidateRuntimes()
            }
            guard projectURL == startedProject else { return }
            actionOutput = result.output
            if result.timedOut {
                actionError = "The install stopped after 10 minutes."
            } else if result.exitCode != 0 {
                actionError = "uv could not install Graphify (exit \(result.exitCode))."
            } else {
                await loadStatus()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    func buildGraph() async {
        guard let cliURL = status?.cliURL, let projectURL, let projectID, !isBusy else { return }

        let startedProject = projectURL
        isBuilding = true
        actionError = nil
        actionOutput = nil
        defer { isBuilding = false }

        do {
            let result = try await GraphifyProcess.run(
                executable: cliURL,
                arguments: GraphifyCommand.update(projectURL: startedProject),
                workingDirectory: startedProject,
                timeout: 900
            )
            if !result.timedOut, result.exitCode == 0 {
                app.invalidateRuntimes(projectID: projectID)
            }
            guard projectURL == startedProject else { return }
            actionOutput = result.output
            if result.timedOut {
                actionError = "Graphify stopped after 15 minutes."
            } else if result.exitCode != 0 {
                actionError = "Graphify could not build the graph (exit \(result.exitCode))."
            } else {
                await loadStatus()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    func runQuery() async {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty,
              let cliURL = status?.cliURL,
              let graphURL = status?.graphURL,
              status?.graphExists == true,
              !isBusy else {
            return
        }

        let startedProject = projectURL
        isQuerying = true
        queryError = nil
        queryResult = nil
        defer { isQuerying = false }

        do {
            let result = try await GraphifyProcess.run(
                executable: cliURL,
                arguments: GraphifyCommand.query(question, graphURL: graphURL),
                workingDirectory: startedProject,
                timeout: 120
            )
            guard projectURL == startedProject else { return }
            if result.timedOut {
                queryError = "The query stopped after two minutes."
            } else if result.exitCode != 0 {
                queryError = result.output.isEmpty
                    ? "Graphify could not run the query."
                    : result.output
            } else {
                queryResult = result.output
            }
        } catch {
            queryError = error.localizedDescription
        }
    }

    func openGraph() {
        guard let url = status?.htmlURL else { return }
        NSWorkspace.shared.open(url)
    }
}
