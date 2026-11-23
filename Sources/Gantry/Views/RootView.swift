import AppKit
import SwiftUI
import GantryCore

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AuroraBackground()

            if app.projects.isEmpty {
                WelcomeView()
            } else {
                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: 274)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    Hairline(axis: .vertical)

                    workspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if app.commandPalettePresented {
                CommandPaletteView()
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .frame(minWidth: 1040, minHeight: 700)
        .tint(Palette.accent)
        .preferredColorScheme(app.appearance.colorScheme)
        .background(WindowConfigurator())
        .overlay(alignment: .top) {
            if let message = app.loadError {
                LoadErrorBanner(message: message) {
                    app.loadError = nil
                }
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(30)
            }
        }
        .animation(.smooth(duration: 0.25), value: app.projects.isEmpty)
        .animation(.smooth(duration: 0.22), value: app.commandPalettePresented)
        .sheet(isPresented: renameSheetBinding) {
            if let sessionID = app.renamingSessionID,
               let session = app.session(withID: sessionID) {
                RenameSessionSheet(session: session) { newTitle in
                    app.renameSession(sessionID, to: newTitle)
                    app.renamingSessionID = nil
                } onCancel: {
                    app.renamingSessionID = nil
                }
            }
        }
        .task {
            app.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            app.shutdown()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            app.saveNow()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                app.saveNow()
            }
        }
    }

    @ViewBuilder
    private var workspace: some View {
        if let project = app.selectedProject,
           let sessionID = app.selectedSessionID,
           let session = app.session(withID: sessionID) {
            HStack(spacing: 0) {
                ChatWorkspaceView(session: session, project: project)
                    .id(sessionID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if app.inspectorVisible {
                    Hairline(axis: .vertical)
                    InspectorView(session: session, project: project)
                        .frame(width: 306)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.24), value: app.inspectorVisible)
        } else if let project = app.selectedProject {
            ProjectLandingView(project: project)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WelcomeView()
        }
    }




    private var renameSheetBinding: Binding<Bool> {
        Binding(
            get: { app.renamingSessionID != nil },
            set: { isPresented in
                if !isPresented { app.renamingSessionID = nil }
            }
        )
    }
}

private struct LoadErrorBanner: View {
    var message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Palette.warning)
            Text(message)
                .font(Typo.caption)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.surfaceRaised.opacity(0.94))
                .overlay(Capsule(style: .continuous).strokeBorder(Palette.line, lineWidth: 0.7))
                .shadow(color: Palette.shadow.opacity(0.5), radius: 16, y: 6)
        )
        .frame(maxWidth: 620)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    final class Coordinator {
        var didConfigure = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view: view, coordinator: context.coordinator, attempts: 0)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if !context.coordinator.didConfigure {
            configure(view: nsView, coordinator: context.coordinator, attempts: 0)
        }
    }

    private func configure(view: NSView, coordinator: Coordinator, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempts == 0 ? 0 : 0.05)) {
            guard !coordinator.didConfigure, let window = view.window else {
                if attempts < 20 {
                    configure(view: view, coordinator: coordinator, attempts: attempts + 1)
                }
                return
            }
            coordinator.didConfigure = true
            window.title = "Gantry"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: 1040, height: 700)
            window.tabbingMode = .disallowed
            window.sharingType = .readOnly
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
    }
}

struct RenameSessionSheet: View {
    var session: ChatSession
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(session: ChatSession, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: session.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rename Session")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                Text("Give this conversation a name that's easy to find.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }

            TextField("Session name", text: $title)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.surfaceSubtle)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Palette.lineStrong, lineWidth: 0.8)
                        )
                )
                .focused($focused)
                .onSubmit { save() }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
        .background(Palette.canvasGradient)
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}


