import SwiftUI

/// "Scenes" row on the home screen: one-tap macros, plus a tile to add or edit them.
struct ScenesRow: View {
    @Environment(SceneStore.self) private var scenes
    @Environment(TVStore.self) private var store
    @State private var editing = false
    @State private var editingScene: RemoteScene?

    var body: some View {
        VStack(alignment: .leading, spacing: Look.S.m) {
            SectionHeader(title: "Scenes") {
                Button { editing = true } label: {
                    Text("Edit").font(Look.font(13, .heavy)).foregroundStyle(Look.cyan)
                        .padding(.horizontal, Look.S.m).frame(minHeight: 32)
                        .background(Look.cyan.opacity(0.12), in: Capsule())
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel("Edit scenes")
            }
            ScrollView(.horizontal) {
                HStack(spacing: Look.S.s) {
                    ForEach(scenes.scenes) { scene in
                        SceneChip(scene: scene, running: scenes.running == scene.id) {
                            Task { await scenes.run(scene) }
                        }
                        .contextMenu {
                            Button { editingScene = scene } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { scenes.remove(scene) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    Button {
                        if scenes.canAdd() { editingScene = RemoteScene(name: "", emoji: "✨", steps: []) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 13, weight: .heavy))
                            Text("New").font(Look.font(14, .heavy))
                        }
                        .foregroundStyle(Look.dim)
                        .padding(.horizontal, Look.S.l).frame(height: 48)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [6, 7])))
                    }
                    .buttonStyle(SquishStyle())
                    .accessibilityLabel("New scene")
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $editing) { ScenesView().environment(scenes).environment(store) }
        .sheet(item: $editingScene) { s in SceneEditor(scene: s).environment(scenes).environment(store) }
    }
}

/// One scene as a glowing pill.
struct SceneChip: View {
    let scene: RemoteScene
    var running = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Look.S.s) {
                if running {
                    ProgressView().tint(.white).frame(width: 22, height: 22)
                } else {
                    Text(scene.emoji).font(.system(size: 20))
                }
                Text(scene.name).font(Look.font(15, .heavy)).foregroundStyle(.white).lineLimit(1)
            }
            .padding(.horizontal, Look.S.l).frame(height: 48)
            .glassCapsule(tint: Look.violet, glow: running ? Look.magenta : nil)
        }
        .buttonStyle(SquishStyle(scale: 0.94))
        .disabled(running)
        .accessibilityLabel("Run scene \(scene.name)")
    }
}

/// All scenes: reorder, edit, delete, add.
struct ScenesView: View {
    @Environment(SceneStore.self) private var scenes
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editingScene: RemoteScene?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(scenes.scenes) { scene in
                        Button { editingScene = scene } label: {
                            HStack(spacing: Look.S.m) {
                                Text(scene.emoji).font(.system(size: 26)).frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scene.name).font(Look.font(17, .heavy)).foregroundStyle(.white)
                                    Text(scene.steps.map(\.title).joined(separator: " → "))
                                        .font(Look.font(12, .semibold)).foregroundStyle(Look.dim).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Look.faint)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                    .onDelete { idx in for i in idx.sorted(by: >) where i < scenes.scenes.count { scenes.remove(scenes.scenes[i]) } }
                    .onMove { from, to in scenes.move(from: from, to: to) }
                } header: {
                    Text("Tap a scene to edit it. Say “Run Movie night in Couch Remote” to Siri to run one.")
                        .font(Look.font(12, .medium)).foregroundStyle(Look.dim).textCase(nil)
                }
                Section {
                    Button {
                        if scenes.canAdd() { editingScene = RemoteScene(name: "", emoji: "✨", steps: []) }
                    } label: {
                        Label(scenes.scenes.count >= SceneStore.freeLimit && !Unlock.shared.isPro ? "New scene (Pro)" : "New scene",
                              systemImage: "plus.circle.fill")
                            .font(Look.font(16, .heavy)).foregroundStyle(Look.cyan)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editingScene) { s in SceneEditor(scene: s).environment(scenes).environment(store) }
    }
}

/// Edit one scene: name, emoji and its ordered steps.
struct SceneEditor: View {
    @Environment(SceneStore.self) private var scenes
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var scene: RemoteScene
    @State private var addingStep = false
    @State private var appName = ""

    private var isNew: Bool { !scenes.scenes.contains { $0.id == scene.id } }
    private var canSave: Bool { !scene.name.trimmingCharacters(in: .whitespaces).isEmpty && !scene.steps.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Look.S.m) {
                        TextField("🍿", text: $scene.emoji)
                            .font(.system(size: 28)).multilineTextAlignment(.center)
                            .frame(width: 56, height: 48)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onChange(of: scene.emoji) { _, v in if v.count > 1 { scene.emoji = String(v.suffix(1)) } }
                            .accessibilityLabel("Emoji")
                        TextField("Scene name", text: $scene.name).font(Look.font(18, .heavy))
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                Section {
                    ForEach(Array(scene.steps.enumerated()), id: \.offset) { i, step in
                        HStack(spacing: Look.S.m) {
                            Image(systemName: step.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Look.cyan).frame(width: 26)
                            Text(step.title).font(Look.font(16, .bold)).foregroundStyle(.white)
                            Spacer()
                            Text("\(i + 1)").font(Look.font(12, .heavy)).foregroundStyle(Look.faint)
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                    .onDelete { scene.steps.remove(atOffsets: $0) }
                    .onMove { scene.steps.move(fromOffsets: $0, toOffset: $1) }
                    Menu {
                        Button { scene.steps.append(.tvPower(on: true)) } label: { Label("TV on", systemImage: "power.circle.fill") }
                        Button { scene.steps.append(.tvPower(on: false)) } label: { Label("TV off", systemImage: "power.circle") }
                        Menu {
                            ForEach(store.favoriteApps) { app in Button(app.name) { scene.steps.append(.launchApp(name: app.name)) } }
                            Divider()
                            Button("Other app…") { addingStep = true }
                        } label: { Label("Open app", systemImage: "play.rectangle.fill") }
                        Menu {
                            ForEach([3, 5, 10], id: \.self) { n in
                                Button("Volume up ×\(n)") { scene.steps.append(.volume(presses: n)) }
                            }
                            ForEach([3, 5, 10], id: \.self) { n in
                                Button("Volume down ×\(n)") { scene.steps.append(.volume(presses: -n)) }
                            }
                        } label: { Label("Volume", systemImage: "speaker.wave.2.fill") }
                        Button { scene.steps.append(.pcWake) } label: { Label("Wake PC", systemImage: "desktopcomputer") }
                        Button { scene.steps.append(.pcSleep) } label: { Label("Sleep PC", systemImage: "moon.zzz.fill") }
                        if store.tvs.count > 1 {
                            Menu {
                                ForEach(store.tvs) { t in Button(t.name) { scene.steps.append(.switchTV(id: t.id, name: t.name)) } }
                            } label: { Label("Switch TV", systemImage: "tv.and.mediabox") }
                        }
                    } label: {
                        Label("Add step", systemImage: "plus.circle.fill").font(Look.font(16, .heavy)).foregroundStyle(Look.cyan)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                } header: {
                    Text("Steps run in order, with a short pause between them.")
                        .font(Look.font(12, .medium)).foregroundStyle(Look.dim).textCase(nil)
                }
                if !isNew {
                    Section {
                        Button(role: .destructive) { scenes.remove(scene); dismiss() } label: {
                            Label("Delete scene", systemImage: "trash").font(Look.font(16, .heavy))
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle(isNew ? "New scene" : "Edit scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        scene.name = scene.name.trimmingCharacters(in: .whitespaces)
                        if scene.emoji.isEmpty { scene.emoji = "✨" }
                        if isNew { if scenes.add(scene) { dismiss() } } else { scenes.update(scene); dismiss() }
                    }
                    .disabled(!canSave)
                }
            }
            .alert("Open which app?", isPresented: $addingStep) {
                TextField("App name", text: $appName)
                Button("Add") {
                    let n = appName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { scene.steps.append(.launchApp(name: n)) }
                    appName = ""
                }
                Button("Cancel", role: .cancel) { appName = "" }
            } message: { Text("Type the app's name as it appears on your TV, e.g. Netflix.") }
        }
        .preferredColorScheme(.dark)
    }
}
