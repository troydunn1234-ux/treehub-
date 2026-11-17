import SwiftUI
import SwiftData
import UIKit

/// Share your trees with friends (opt in per tree), and import theirs. No accounts, no server.
struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @AppStorage(FriendShare.nameKey) private var myName = ""
    @State private var shared = FriendShare.sharedTreeIDs
    @State private var friends = FriendShare.friends
    @State private var pasted = ""
    @State private var message = ""
    @State private var preview: SharePack?
    @State private var copied = 0
    /// A code that arrived through a rootbound://friends link.
    var incoming: String? = nil

    private var trees: [TreeSummary] { TreeSummary.build(from: hugs) }
    private var pinned: [TreeSummary] { trees.filter { $0.coordinate != nil } }
    private var pack: SharePack { FriendShare.pack(from: myName.isEmpty ? "A friend" : myName, trees: trees) }
    private var code: String? { pack.t.isEmpty ? nil : FriendShare.code(for: pack) }
    private var link: URL? { code.flatMap(FriendShare.link(for:)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RB.l) {
                    if let preview { importCard(preview) }
                    shareSection
                    importSection
                    friendsSection
                    Label("Shared trees carry only a name, a species and a spot rounded to about 1 km. No photos, dates or anything else, and nothing goes through a server: the code is the whole thing.",
                          systemImage: "lock.shield.fill")
                        .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(RB.screen)
                .padding(.bottom, RB.xxl)
            }
            .forestScreen()
            .sensoryFeedback(.success, trigger: copied)
            .navigationTitle("Friends map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                if let incoming, let p = FriendShare.decode(incoming) { preview = p }
            }
        }
    }

    // MARK: Share mine

    private var shareSection: some View {
        RBCard {
            VStack(alignment: .leading, spacing: 12) {
                RBSectionTitle(title: "Share my trees", symbol: "square.and.arrow.up")
                TextField("Your name for friends", text: $myName)
                    .textInputAutocapitalization(.words)
                    .font(RB.text(.body))
                    .padding(.horizontal, RB.m)
                    .frame(minHeight: 48)
                    .rbInner()
                if pinned.isEmpty {
                    Text("Pin a tree on the map when you log a hug, then you can share it here.")
                        .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                } else {
                    Text("Pick the trees friends can see:").font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.textDim)
                    ForEach(pinned) { t in
                        Toggle(isOn: Binding(get: { shared.contains(t.id) },
                                             set: { on in FriendShare.setShared(t.id, on); shared = FriendShare.sharedTreeIDs })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                                Text(t.species.isEmpty ? "Mystery species" : t.species)
                                    .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                            }
                        }
                        .tint(Theme.glow)
                    }
                }
                if let link, let code {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: RB.m) { qrCode(link); shareButtons(link, code: code) }
                        VStack(alignment: .leading, spacing: RB.m) { qrCode(link); shareButtons(link, code: code) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func qrCode(_ link: URL) -> some View {
        if let qr = FriendShare.qrImage(for: link.absoluteString) {
            Image(uiImage: qr).interpolation(.none).resizable()
                .frame(width: 128, height: 128)
                .padding(6).background(.white, in: RoundedRectangle(cornerRadius: RB.inner, style: .continuous))
                .accessibilityLabel("QR code with your shared trees")
        }
    }

    private func shareButtons(_ link: URL, code: String) -> some View {
        VStack(alignment: .leading, spacing: RB.s) {
            Text("\(pack.t.count) tree\(pack.t.count == 1 ? "" : "s") in this code")
                .font(RB.text(.footnote, .bold)).foregroundStyle(.white)
            ShareLink(item: link, subject: Text("My Rootbound trees"),
                      message: Text("Open this in Rootbound to see my trees on your map. Code: \(code)")) {
                Label("Send link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(RBPrimaryButtonStyle())
            Button { UIPasteboard.general.string = code; message = "Code copied."; copied += 1 } label: {
                Label("Copy code", systemImage: "doc.on.doc")
            }
            .buttonStyle(RBSecondaryButtonStyle(compact: true))
        }
    }

    // MARK: Import theirs

    private var importSection: some View {
        RBCard {
            VStack(alignment: .leading, spacing: RB.m) {
                RBSectionTitle(title: "Add a friend's trees", symbol: "person.2.fill")
                Text("Scan their QR code with the Camera, open their link, or paste their code here.")
                    .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: RB.s) {
                    TextField("RB1-…", text: $pasted)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(RB.text(.body))
                        .padding(.horizontal, RB.m)
                        .frame(minHeight: 48)
                        .rbInner()
                    Button("Paste") { pasted = UIPasteboard.general.string ?? "" }
                        .buttonStyle(RBSecondaryButtonStyle(compact: true))
                        .fixedSize()
                }
                Button {
                    if let p = FriendShare.decode(pasted) { preview = p; message = "" } else { message = "That doesn't look like a Rootbound code." }
                } label: { Text("Add").frame(maxWidth: .infinity) }
                .buttonStyle(RBPrimaryButtonStyle())
                .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
                if !message.isEmpty {
                    Text(message).font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.gold)
                }
            }
        }
    }

    private func importCard(_ p: SharePack) -> some View {
        RBCard {
            VStack(alignment: .leading, spacing: 10) {
                RBSectionTitle(title: "\(p.from.isEmpty ? "A friend" : p.from) shared \(p.t.count) tree\(p.t.count == 1 ? "" : "s")", symbol: "gift.fill")
                ForEach(Array(p.t.prefix(6).enumerated()), id: \.offset) { _, t in
                    Text("• \(t.n)\(t.s.isEmpty ? "" : " · \(t.s)")").font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                }
                if p.t.count > 6 { Text("and \(p.t.count - 6) more").font(RB.text(.caption)).foregroundStyle(Theme.textDim) }
                HStack(spacing: RB.s) {
                    Button("Add to my map") {
                        FriendShare.importPack(p)
                        friends = FriendShare.friends
                        preview = nil; pasted = ""
                        message = "Added. Their trees show on your Grove map in blue."
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    .buttonStyle(RBPrimaryButtonStyle(tint: Theme.sky))
                    Button("Not now") { preview = nil }
                        .buttonStyle(RBSecondaryButtonStyle())
                }
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !friends.isEmpty {
                RBSectionTitle(title: "Friends on your map", symbol: "map.fill")
                ForEach(friends) { f in
                    HStack(spacing: RB.m) {
                        Circle().fill(Theme.sky).frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                            Text("\(f.trees.count) tree\(f.trees.count == 1 ? "" : "s") · added \(Format.day(f.importedAt))")
                                .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                        }
                        Spacer(minLength: RB.s)
                        Button(role: .destructive) { FriendShare.remove(f.id); friends = FriendShare.friends } label: {
                            Image(systemName: "trash")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(f.name)")
                    }
                    .padding(.leading, RB.m)
                    .padding(.vertical, RB.xs)
                    .rbInner()
                }
            }
        }
    }
}

/// A friend's tree on the Grove map: blue, with a person badge, so it never looks like one of yours.
struct FriendTreePin: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(Theme.sky.opacity(0.9)).frame(width: 30, height: 30)
                .overlay(Image(systemName: "tree.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: Theme.sky.opacity(0.7), radius: 6)
            Image(systemName: "person.fill").font(.system(size: 8, weight: .black)).foregroundStyle(Theme.sky)
                .padding(3).background(.white, in: Circle()).offset(x: 4, y: 4)
        }
    }
}
