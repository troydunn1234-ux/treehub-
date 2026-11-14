import SwiftUI
import Combine
import UIKit
import SwiftData
import AppIntents

// Entry points for "Go together": the button on the Track screen, the start / join sheet,
// invite links (roamr://join?c=CODE and the https join page), and the Siri shortcut.

/// Floating "Go together" pill shown over the Track screen when nothing is recording.
@MainActor
struct GoTogetherButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Go together", systemImage: "person.2.fill")
                .font(Theme.rounded(14, .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Start or join a live group activity with friends")
    }
}

/// "Group drive live · 3" pill to get back to the group map.
@MainActor
struct GroupLivePill: View {
    @ObservedObject var group: GroupSession
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(Theme.glow).frame(width: 8, height: 8)
                Image(systemName: "person.2.fill").font(.system(size: 13, weight: .black))
                Text("Group \(group.kind.title.lowercased()) live · \(group.riders.count + 1)")
                    .font(Theme.rounded(13, .heavy))
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .black))
            }
            .foregroundStyle(Theme.forestDeep)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.leafGradient, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open group map")
    }
}

/// Pick an activity and start a group, or type a friend's code to join theirs.
@MainActor
struct GoTogetherSheet: View {
    @ObservedObject private var group = GroupSession.shared
    @Environment(RouteTracker.self) private var tracker
    @State private var kind: ActivityKind
    @State private var name: String
    @State private var codeText = ""
    @FocusState private var codeFocused: Bool
    var onClose: () -> Void

    init(initialKind: ActivityKind = .drive, onClose: @escaping () -> Void) {
        _kind = State(initialValue: initialKind)
        let session = GroupSession.shared
        _name = State(initialValue: session.needsName ? "" : session.myName)
        self.onClose = onClose
    }

    private var cleanedName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Me" : String(n.prefix(24))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap + 4) {
                HStack {
                    Text("Go together").font(Theme.title(30)).foregroundStyle(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.textDim)
                            .frame(width: 32, height: 32).background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                Text("See your friends live on one map, with everyone's speed. Each phone records its own trip.")
                    .font(Theme.rounded(13, .semibold))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your name").font(Theme.rounded(12, .heavy)).foregroundStyle(Theme.textDim)
                    TextField("Name your friends will see", text: $name)
                        .font(Theme.rounded(17, .bold))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let invite = group.pendingInvite {
                    inviteCard(invite)
                } else {
                    startSection
                    joinSection
                }

                if let err = group.lastError {
                    Label(err, systemImage: "exclamationmark.circle.fill")
                        .font(Theme.rounded(13, .bold))
                        .foregroundStyle(Theme.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.pad)
        }
        .scrollIndicators(.hidden)
        .background(Theme.forestDeep.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .disabled(group.working)
        .overlay {
            if group.working { ProgressView().tint(Theme.glow).scaleEffect(1.3) }
        }
        .onAppear { group.lastError = nil }
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Start a group", symbol: "dot.radiowaves.left.and.right")
            HStack(spacing: 6) {
                ForEach(ActivityKind.available) { k in
                    Button {
                        withAnimation(.snappy) { kind = k }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: k.symbol).font(.system(size: 20, weight: .semibold))
                            Text(k.title).font(Theme.rounded(12, .bold))
                        }
                        .foregroundStyle(kind == k ? Theme.forestDeep : Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if kind == k {
                                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.leafGradient)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: kind == k)
                }
            }
            .padding(6)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Button {
                group.myName = cleanedName
                Task { await group.create(kind: kind) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill").font(.system(size: 15, weight: .black))
                    Text("Start group \(kind.title.lowercased())")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(tracker.denied)

            if tracker.isActive && tracker.kind != kind {
                Text("You're already recording a \(tracker.kind.title.lowercased()); it keeps going and joins the group.")
                    .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Join with code", symbol: "number")
            HStack(spacing: 8) {
                TextField("K7QH2M", text: $codeText)
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($codeFocused)
                    .submitLabel(.join)
                    .onSubmit(join)
                    .onChange(of: codeText) { _, v in
                        let c = GroupSession.cleanCode(v)
                        if c != v { codeText = c }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button(action: join) {
                    Text("Join")
                        .font(Theme.rounded(16, .heavy))
                        .foregroundStyle(Theme.forestDeep)
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .background(Theme.goldGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!GroupSession.isValidCode(codeText))
                .opacity(GroupSession.isValidCode(codeText) ? 1 : 0.5)
            }
        }
    }

    private func join() {
        guard GroupSession.isValidCode(codeText) else { return }
        codeFocused = false
        group.myName = cleanedName
        let code = codeText
        Task { await group.prepareJoin(code: code) }
    }

    private func inviteCard(_ invite: GroupInvite) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: invite.kind.symbol)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(width: 44, height: 44)
                    .background(Theme.leafGradient, in: Circle())
                Text("Join \(invite.hostName)'s group \(invite.kind.title.lowercased())?")
                    .font(Theme.rounded(18, .heavy))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Code \(invite.code). Your location is shared with this group only while you're in it.")
                .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
            Button {
                group.myName = cleanedName
                group.accept(invite)
            } label: {
                Text("Join")
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Not now") { group.pendingInvite = nil }
                .font(Theme.rounded(14, .bold))
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Hooks "Go together" into the app root: entry button, sheets, live map, invite links and alerts.
@MainActor
struct GroupTogetherModifier: ViewModifier {
    @Binding var tab: String
    @ObservedObject private var group = GroupSession.shared
    @Environment(RouteTracker.self) private var tracker
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSheet = false
    @State private var showMap = false
    @State private var sheetKind: ActivityKind = .drive
    @State private var nameDraft = ""

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if tab == "track" && !group.isActive && !tracker.isActive {
                    GoTogetherButton {
                        sheetKind = .drive
                        showSheet = true
                    }
                    .padding(.top, 58).padding(.leading, 14)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if group.isActive && !showMap {
                    GroupLivePill(group: group) { showMap = true }
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: group.isActive)
            .sheet(isPresented: $showSheet, onDismiss: {
                if !group.isActive { group.pendingInvite = nil }
            }) {
                GoTogetherSheet(initialKind: sheetKind) { showSheet = false }
                    .environment(tracker)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showMap) {
                GroupMapView()
                    .environment(tracker)
                    .environment(\.modelContext, context)
            }
            // Links are handled at the app level (TrackHubApp) so they also work during first launch;
            // the invite waits in GroupSession until this screen can ask.
            .onChange(of: group.pendingInvite) { _, invite in
                if invite != nil, !showSheet {
                    tab = "track"
                    nameDraft = group.needsName ? "" : group.myName
                }
            }
            .onChange(of: group.state) { old, new in
                if old == .idle && new != .idle {
                    tab = "track"
                    showSheet = false
                    // Let the sheet finish closing before the map covers the screen.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showMap = group.isActive }
                } else if new == .idle {
                    showMap = false
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { consumeSiri() }
            }
            .onReceive(NotificationCenter.default.publisher(for: GroupPending.note)) { _ in consumeSiri() }
            .onAppear {
                group.attach(tracker: tracker)
                nameDraft = group.needsName ? "" : group.myName
                consumeSiri()
            }
            // Invite from a link (codes typed in the sheet are confirmed inside the sheet).
            .alert(
                group.pendingInvite.map { "Join \($0.hostName)'s group \($0.kind.title.lowercased())?" } ?? "Join group?",
                isPresented: Binding(
                    get: { group.pendingInvite != nil && !showSheet && !showMap },
                    set: { if !$0 { group.pendingInvite = nil } }
                ),
                presenting: group.pendingInvite
            ) { invite in
                if group.needsName {
                    TextField("Your name", text: $nameDraft)
                        .textInputAutocapitalization(.words)
                }
                Button("Join") {
                    let n = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if group.needsName || !n.isEmpty { group.myName = n.isEmpty ? "Me" : String(n.prefix(24)) }
                    group.accept(invite)
                }
                Button("Not now", role: .cancel) {}
            } message: { invite in
                Text("Code \(invite.code). Your location is shared with this group only while you're in it.")
            }
            .alert("Go together", isPresented: Binding(
                get: { group.lastError != nil && !showSheet && !showMap },
                set: { if !$0 { group.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(group.lastError ?? "")
            }
            .alert(group.endedNotice ?? "Trip ended", isPresented: Binding(
                get: { group.endedNotice != nil && !showMap },
                set: { if !$0 { group.endedNotice = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You've left the group. Your own \(tracker.isActive ? tracker.kind.title.lowercased() : "trip") is still recording until you stop it.")
            }
    }

    /// "Start a group drive" from Siri / Shortcuts.
    private func consumeSiri() {
        guard GroupPending.take() else { return }
        tab = "track"
        guard !group.isActive else { showMap = true; return }
        if group.needsName {
            sheetKind = .drive
            showSheet = true
        } else {
            Task { await group.create(kind: .drive) }
        }
    }
}

extension View {
    /// Adds "Go together" (group activities with friends) to the app root.
    @MainActor
    func groupTogether(tab: Binding<String>) -> some View {
        modifier(GroupTogetherModifier(tab: tab))
    }
}

// MARK: - Siri

struct StartGroupDriveIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Group Drive"
    static var description = IntentDescription("Opens Roamr and starts a live group drive you can share with friends.")
    static var openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        GroupPending.queue()
        return .result()
    }
}
