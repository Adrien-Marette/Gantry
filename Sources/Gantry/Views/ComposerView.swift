import SwiftUI
import GantryCore

struct ComposerView: View {
    @Environment(AppModel.self) private var app
    var session: ChatSession
    var project: Project
    var activity: SessionActivity?
    var providerReady = true
    var glassNamespace: Namespace.ID?

    @FocusState private var focused: Bool
    @Namespace private var ownGlassNamespace

    private var isRunning: Bool {
        activity?.isRunning == true
    }

    private var draft: Binding<String> {
        Binding(
            get: { app.drafts[session.id] ?? "" },
            set: { app.drafts[session.id] = $0 }
        )
    }

    private var trimmedDraft: String {
        draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedDraft.isEmpty && !isRunning && app.claudeAvailability.isReady && providerReady
    }

    var body: some View {
        composerSurface
    }

    private var composerSurface: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .lineLimit(1...9)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                        return .ignored
                    }
                    if isRunning { return .handled }
                    submit()
                    return .handled
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                permissionMenu
                modelMenu

                Spacer(minLength: 8)

                if isRunning {
                    HStack(spacing: 8) {
                        LiveIndicator(color: Palette.accent, size: 12)
                        Text(activity?.isStopping == true ? "Stopping" : (activity?.statusText ?? "Working"))
                            .font(Typo.micro)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                    .padding(.trailing, 4)
                } else {
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            KeyHint(text: "↵")
                            Text("send")
                        }
                        HStack(spacing: 4) {
                            KeyHint(text: "⇧↵")
                            Text("new line")
                        }
                    }
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.trailing, 4)
                }

                primaryButton
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .glassPanel(radius: 20, interactive: true)
        .glassEffectID("composer", in: glassNamespace ?? ownGlassNamespace)
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.16), value: focused)
        .onAppear {
            if session.turns.isEmpty {
                focused = true
            }
        }
    }

    private var placeholder: String {
        if !app.claudeAvailability.isReady {
            return "Claude Code isn't available"
        }
        if !providerReady {
            return "Add an API key to use this provider"
        }
        if isRunning {
            return "Claude is working"
        }
        if session.turns.isEmpty {
            return "Ask Claude to build, fix, or explain"
        }
        return "Message Claude"
    }

    private var permissionMenu: some View {
        Menu {
            Picker("Permission", selection: Binding(
                get: { session.permissionMode },
                set: { app.setPermissionMode($0, for: session.id) }
            )) {
                ForEach(PermissionMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol)
                        .tag(mode)
                }
            }
            Divider()
            Text(session.permissionMode.detail)
            Text(permissionHelp)
        } label: {
            ControlLabel(
                systemName: session.permissionMode.symbol,
                title: session.permissionMode.title,
                tint: Palette.accent
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isRunning)
        .opacity(isRunning ? 0.64 : 1)
        .help("Permission mode: \(session.permissionMode.detail)")
    }

    private var modelMenu: some View {
        Menu {
            Picker("Model", selection: Binding(
                get: { session.model },
                set: { app.setModel($0, for: session.id) }
            )) {
                ForEach(ModelChoice.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
            Divider()
            Text(session.model.detail)
            if let actual = session.actualModelName, session.model == .automatic {
                Text("Active: \(actual)")
            }
        } label: {
            ControlLabel(
                systemName: "cpu",
                title: session.displayModelName,
                tint: Palette.secondaryInk
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isRunning)
        .opacity(isRunning ? 0.64 : 1)
        .help("Model for this session")
    }

    private var permissionHelp: String {
        switch session.permissionMode {
        case .ask: return "Claude will ask here before running commands or changing files."
        case .autoEdits: return "File edits run automatically; commands still ask."
        case .plan: return "Claude explores and proposes a plan without changing files."
        case .auto: return "Claude Code's classifier approves low-risk actions."
        }
    }

    private var primaryButton: some View {
        Group {
            if isRunning {
                Button {
                    app.stop(sessionID: session.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .padding(7)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Stop (⌘.)")
                .accessibilityLabel("Stop Claude")
            } else {
                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .padding(7)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Palette.accent)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
                .help("Send")
                .accessibilityLabel("Send message")
            }
        }
    }

    private func submit() {
        guard !isRunning, providerReady else { return }

        guard canSend else {
            if !trimmedDraft.isEmpty, !app.claudeAvailability.isReady {
                activity?.banner = "Claude Code isn't available yet."
            }
            return
        }
        let prompt = draft.wrappedValue
        if app.send(prompt, in: session.id) {
            app.drafts[session.id] = ""
            focused = true
        }
    }
}
