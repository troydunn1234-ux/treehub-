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
                VStack(alignment: .leading, spacing: 18) {
                    if let preview { importCard(preview) }
                    shareSection
                    importSection
                    friendsSection
                    Text("Shared trees carry only a name, a species and a spot rounded to about 1 km. No photos, dates or anything else, and nothing goes through a server: the code is the whole thing.")
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                }
                .padding(Theme.pad)
                .padding(.bottom, 40)
            }
            .forestScreen()
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
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Share my trees", symbol: "square.and.arrow.up")
                TextField("Your name for friends", text: $myName)
                    .textInputAutocapitalization(.words)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                if pinned.isEmpty {
                    Text("Pin a tree on the map when you log a hug, then you can share it here.")
                        .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                } else {
                    Text("Pick the trees friends can see:").font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.textDim)
                    ForEach(pinned) { t in
                        Toggle(isOn: Binding(get: { shared.contains(t.id) },
                                             set: { on in FriendShare.setShared(t.id, on); shared = FriendShare.sharedTreeIDs })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                                Text(t.species.isEmpty ? "Mystery species" : t.species)
                                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            }
                        }
                        .tint(Theme.glow)
                    }
                }
                if let link, let code {
                    HStack(alignment: .center, spacing: 14) {
                        if let qr = FriendShare.qrImage(for: link.absoluteString) {
                            Image(uiImage: qr).interpolation(.none).resizable()
                                .frame(width: 128, height: 128)
                                .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityLabel("QR code with your shared trees")
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(pack.t.count) tree\(pack.t.count == 1 ? "" : "s") in this code")
                                .font(Theme.rounded(13, .bold)).foregroundStyle(.white)
                            ShareLink(item: link, subject: Text("My Rootbound trees"),
                                      message: Text("Open this in Rootbound to see my trees on your map. Code: \(code)")) {
                                Label("Send link", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.leaf)
                            Button { UIPasteboard.general.string = code; message = "Code copied." } label: {
                                Label("Copy code", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    // MARK: Import theirs

    private var importSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Add a friend's trees", symbol: "person.2.fill")
                Text("Scan their QR code with the Camera, open their link, or paste their code here.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                HStack {
                    TextField("RB1-…", text: $pasted)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    Button("Paste") { pasted = UIPasteboard.general.string ?? "" }.buttonStyle(.bordered)
                }
                Button {
                    if let p = FriendShare.decode(pasted) { preview = p; message = "" } else { message = "That doesn't look like a Rootbound code." }
                } label: { Text("Add").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
                if !message.isEmpty {
                    Text(message).font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.gold)
                }
            }
        }
    }

    private func importCard(_ p: SharePack) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "\(p.from.isEmpty ? "A friend" : p.from) shared \(p.t.count) tree\(p.t.count == 1 ? "" : "s")", symbol: "gift.fill")
                ForEach(Array(p.t.prefix(6).enumerated()), id: \.offset) { _, t in
                    Text("• \(t.n)\(t.s.isEmpty ? "" : " · \(t.s)")").font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                }
                if p.t.count > 6 { Text("and \(p.t.count - 6) more").font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim) }
                HStack {
                    Button("Add to my map") {
                        FriendShare.importPack(p)
                        friends = FriendShare.friends
                        preview = nil; pasted = ""
                        message = "Added. Their trees show on your Grove map in blue."
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.sky)
                    Button("Not now") { preview = nil }.buttonStyle(.bordered)
                }
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !friends.isEmpty {
                SectionHeader(title: "Friends on your map", symbol: "map.fill")
                ForEach(friends) { f in
                    HStack {
                        Circle().fill(Theme.sky).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                            Text("\(f.trees.count) tree\(f.trees.count == 1 ? "" : "s") · added \(Format.day(f.importedAt))")
                                .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        Button(role: .destructive) { FriendShare.remove(f.id); friends = FriendShare.friends } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove \(f.name)")
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
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
