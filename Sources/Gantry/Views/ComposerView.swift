import SwiftUI
import GantryCore

struct ComposerView: View {
    @Environment(AppModel.self) private var app
    var session: ChatSession
    var project: Project
    var activity: SessionActivity?
    var providerReady = true

    @FocusState private var focused: Bool
    @State private var isHoveringSend = false

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
        VStack(alignment: .leading, spacing: 9) {
            TextField(placeholder, text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
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
                .onSubmit { submit() }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                permissionMenu
                modelMenu

                Spacer(minLength: 8)

                if isRunning {
                    HStack(spacing: 7) {
                        ActivityDots(color: Palette.accent, size: 2.8)
                        Text(activity?.isStopping == true ? "Stopping…" : (activity?.statusText ?? "Working"))
                            .font(Typo.micro)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                    .padding(.trailing, 2)
                } else {
                    HStack(spacing: 4) {
                        Text("↵")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                        Text("send")
                            .font(.system(size: 9.5))
                        Text("·")
                            .font(.system(size: 9))
                        Text("⇧↵")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                        Text("new line")
                            .font(.system(size: 9.5))
                    }
                    .foregroundStyle(Palette.faintInk)
                    .padding(.trailing, 3)
                }

                primaryButton
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 1)
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .glassEffect(
            .regular
                .tint(Palette.accent.opacity(focused ? 0.075 : 0.035))
                .interactive(),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    focused ? Palette.accent.opacity(0.42) : Palette.lineStrong,
                    lineWidth: focused ? 1.0 : 0.9
                )
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.30), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
        .shadow(color: Palette.shadow.opacity(0.42), radius: 22, y: 9)
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
            return "Claude is working…"
        }
        if session.turns.isEmpty {
            return "Ask Claude to build, fix, or explain…"
        }
        return "Message Claude…"
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
            ControlPillLabel(
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
            ControlPillLabel(
                systemName: "sparkles",
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
        Button {
            if isRunning {
                app.stop(sessionID: session.id)
            } else {
                submit()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isRunning ? Palette.ink.opacity(0.82) : Palette.accent)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
                    )
                    .shadow(
                        color: (isRunning ? Color.black : Palette.accent).opacity(0.22),
                        radius: 7,
                        y: 2
                    )

                Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                    .font(.system(size: isRunning ? 10 : 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 30, height: 30)
            .scaleEffect(isHoveringSend ? 1.045 : 1)
            .opacity(canSend || isRunning ? 1 : 0.34)
        }
        .buttonStyle(.plain)
        .disabled(!canSend && !isRunning)
        .onHover { isHoveringSend = $0 }
        .animation(.easeOut(duration: 0.14), value: isHoveringSend)
        .help(isRunning ? "Stop (⌘.)" : "Send")
        .accessibilityLabel(isRunning ? "Stop Claude" : "Send message")
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
