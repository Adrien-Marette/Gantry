import SwiftUI
import GantryCore

/// Full-text search across every project and conversation. Selecting a result
/// opens the session and, when the match is in a turn, scrolls to that turn.
struct SessionSearchSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var searchedQuery = ""
    @State private var hits: [SessionSearchHit] = []
    @State private var selectedIndex = 0
    @State private var isSearching = false
    @State private var keyboardScrollRevision = 0
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var clampedSelection: Int {
        guard !hits.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), hits.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            results
            Hairline()
            footer
        }
        .frame(width: 760, height: 600)
        .background(CanvasBackground())
        .task(id: query) {
            await runSearch()
        }
        .onAppear {
            searchFocused = true
        }
    }

    // MARK: - Search field

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)

                TextField("Search every project and conversation", text: $query)
                    .textFieldStyle(.plain)
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.ink)
                    .focused($searchFocused)
                    .onKeyPress(.downArrow) {
                        moveSelection(1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        moveSelection(-1)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        openSelected()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
                    .accessibilityLabel("Search every conversation")

                if isSearching {
                    ProgressView()
                        .controlSize(.mini)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(FieldBackground(radius: 10, focused: searchFocused))
            .animation(.easeOut(duration: 0.16), value: searchFocused)

            IconButton(systemName: "xmark", help: "Close", size: 12, frame: 28) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if trimmedQuery.isEmpty {
            emptySearchState
        } else if hits.isEmpty {
            if isSearching {
                VStack(spacing: 8) {
                    Spinner(size: 18)
                    Text("Searching…")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Palette.tertiaryInk)
                    Text("No matches")
                        .font(Typo.bodyMedium)
                        .foregroundStyle(Palette.ink)
                    Text("Nothing contains “\(trimmedQuery)”.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            resultRow(hit, isSelected: index == clampedSelection)
                                .id(hit.id)
                                .onHover { hovering in
                                    if hovering { selectedIndex = index }
                                }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
                .onChange(of: keyboardScrollRevision) { _, _ in
                    guard hits.indices.contains(clampedSelection) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(hits[clampedSelection].id, anchor: .center)
                    }
                }
                .onChange(of: hits) { _, newHits in
                    if let first = newHits.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }

    private func resultRow(_ hit: SessionSearchHit, isSelected: Bool) -> some View {
        let displayTitle = hit.sessionTitle.isEmpty ? "New session" : hit.sessionTitle
        return Button {
            open(hit)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isSelected ? Palette.accent : Color.clear)
                    .frame(width: 2, height: 34)

                Image(systemName: icon(for: hit.kind))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.tertiaryInk)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        highlighted(displayTitle)
                            .font(Typo.bodyMedium)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(label(for: hit.kind))
                            .font(Typo.micro)
                            .foregroundStyle(Palette.tertiaryInk)
                    }

                    if !hit.snippet.isEmpty {
                        highlighted(hit.snippet)
                            .font(Typo.caption)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(hit.projectName)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                    Text(Format.relativeTime(hit.createdAt))
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Palette.sidebarSelection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayTitle), \(label(for: hit.kind)), \(hit.projectName)")
    }

    private var emptySearchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Palette.tertiaryInk)
            Text("Search every conversation")
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.ink)
            Text("Find a prompt, an answer, a command, or a file path across every project and session.")
                .font(Typo.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(resultSummary)
                .font(Typo.caption)
                .foregroundStyle(Palette.tertiaryInk)
            Spacer()
            HStack(spacing: 4) {
                KeyHint(text: "↑↓")
                Text("select")
            }
            HStack(spacing: 4) {
                KeyHint(text: "↵")
                Text("open")
            }
            HStack(spacing: 4) {
                KeyHint(text: "esc")
                Text("close")
            }
        }
        .font(Typo.micro)
        .foregroundStyle(Palette.tertiaryInk)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var resultSummary: String {
        if trimmedQuery.isEmpty { return "Search all projects and sessions" }
        if isSearching { return "Searching…" }
        if hits.isEmpty { return "No matches" }
        return hits.count == 1 ? "1 result" : "\(hits.count) results"
    }

    // MARK: - Actions

    private func runSearch() async {
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else {
            hits = []
            searchedQuery = ""
            selectedIndex = 0
            isSearching = false
            return
        }

        isSearching = true
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }

        let projects = app.projects
        let results = await Task.detached(priority: .userInitiated) {
            SessionSearch.search(query: trimmed, projects: projects)
        }.value
        guard !Task.isCancelled else { return }

        hits = results
        searchedQuery = trimmed
        selectedIndex = 0
        isSearching = false
    }

    private func moveSelection(_ delta: Int) {
        guard !hits.isEmpty else { return }
        let next = clampedSelection + delta
        selectedIndex = (next + hits.count) % hits.count
        keyboardScrollRevision &+= 1
    }

    private func openSelected() {
        guard !isSearching,
              searchedQuery == trimmedQuery,
              hits.indices.contains(clampedSelection) else {
            return
        }
        open(hits[clampedSelection])
    }

    private func open(_ hit: SessionSearchHit) {
        app.pendingTurnScroll = hit.turnID.map {
            PendingTurnScroll(sessionID: hit.sessionID, turnID: $0)
        }
        app.commandPalettePresented = false
        app.select(sessionID: hit.sessionID)
        dismiss()
    }

    private func highlighted(_ text: String) -> Text {
        guard !searchedQuery.isEmpty,
              let range = text.range(
                  of: searchedQuery,
                  options: [.caseInsensitive, .diacriticInsensitive]
              ) else {
            return Text(text)
        }

        var highlighted = AttributedString(String(text[..<range.lowerBound]))
        var match = AttributedString(String(text[range]))
        match.foregroundColor = Palette.accent
        highlighted.append(match)
        highlighted.append(AttributedString(String(text[range.upperBound...])))
        return Text(highlighted)
    }

    private func label(for kind: SessionSearchHit.Kind) -> String {
        switch kind {
        case .title: return "Title"
        case .user: return "You"
        case .assistant: return "Claude"
        case .tool: return "Tool"
        }
    }

    private func icon(for kind: SessionSearchHit.Kind) -> String {
        switch kind {
        case .title: return "textformat"
        case .user: return "person.crop.circle"
        case .assistant: return "sparkles"
        case .tool: return "wrench.and.screwdriver"
        }
    }
}
