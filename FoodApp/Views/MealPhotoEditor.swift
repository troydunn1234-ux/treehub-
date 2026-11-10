import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import AVFoundation

struct MealEntryPhotoDetail: View {
    @Bindable var entry: FoodEntry
    @Environment(\.dismiss) private var dismiss
    @State private var editingPhoto = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Group {
                    if let data = entry.photo, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        ContentUnavailableView("No meal photo", systemImage: "photo")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                VStack(spacing: 4) {
                    Text(entry.name).font(Ember.font(20, .heavy)).foregroundStyle(Ember.cream)
                    Text("\(Int(entry.cal * entry.servings)) cal · \(entry.servings.formatted()) serving(s)")
                        .font(Ember.font(13, .medium)).foregroundStyle(Ember.dim)
                }
                Button { editingPhoto = true } label: {
                    Label("Edit Photo", systemImage: "photo.badge.plus")
                        .font(Ember.font(16, .bold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Ember.fire, in: Capsule()).foregroundStyle(.white)
                }
                .buttonStyle(Squish())
            }
            .padding(20)
            .background(Ember.bg)
            .navigationTitle(Day.title(entry.day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $editingPhoto) {
                MealPhotoEditor(entry: entry).presentationDetents([.large])
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MealPhotoEditor: View {
    @Bindable var entry: FoodEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: UIImage?
    @State private var original: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Group {
                    if let draft {
                        Image(uiImage: draft).resizable().scaledToFit()
                            .accessibilityLabel("Preview of the edited meal photo")
                    } else {
                        ContentUnavailableView("Photo removed", systemImage: "photo")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Ember.card, in: RoundedRectangle(cornerRadius: 18))

                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity).padding(12).background(Ember.card, in: Capsule())
                    }
                    Button(action: beginCamera) {
                        Label("Camera", systemImage: "camera")
                            .frame(maxWidth: .infinity).padding(12).background(Ember.card, in: Capsule())
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                }
                HStack(spacing: 10) {
                    Button(action: rotate) { Label("Rotate", systemImage: "rotate.right") }
                        .frame(maxWidth: .infinity).padding(11).background(Ember.card, in: Capsule())
                        .disabled(draft == nil)
                    Button(action: cropSquare) { Label("Crop square", systemImage: "crop.rotate") }
                        .frame(maxWidth: .infinity).padding(11).background(Ember.card, in: Capsule())
                        .disabled(draft == nil)
                    Button(role: .destructive, action: { draft = nil }) { Label("Remove", systemImage: "trash") }
                        .frame(maxWidth: .infinity).padding(11).background(Ember.card, in: Capsule())
                }
                if let errorMessage {
                    Text(errorMessage).font(Ember.font(13, .medium)).foregroundStyle(.red)
                }
            }
            .padding(18)
            .background(Ember.bg)
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                original = entry.photo
                if let data = original { draft = UIImage(data: data) }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                            errorMessage = "That photo could not be opened. Your saved photo is unchanged."
                            return
                        }
                        draft = image
                        errorMessage = nil
                    } catch {
                        errorMessage = "That photo could not be loaded. Your saved photo is unchanged."
                    }
                }
            }
            .sheet(isPresented: $takingPhoto) {
                MealCameraPicker { image in
                    if let image { draft = image; errorMessage = nil }
                }
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rotate() {
        guard let draft else { return }
        let image = normalized(draft)
        let size = CGSize(width: image.size.height, height: image.size.width)
        let renderer = UIGraphicsImageRenderer(size: size)
        self.draft = renderer.image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
        }
    }

    private func beginCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: takingPhoto = true
        case .notDetermined:
            Task {
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                if allowed { takingPhoto = true }
                else { errorMessage = "Camera access is off. Allow it in Settings, or choose a photo from your library." }
            }
        default:
            errorMessage = "Camera access is off. Allow it in Settings, or choose a photo from your library."
        }
    }

    private func cropSquare() {
        guard let draft, let normalizedCG = normalized(draft).cgImage else { return }
        let side = min(normalizedCG.width, normalizedCG.height)
        let rect = CGRect(x: (normalizedCG.width - side) / 2, y: (normalizedCG.height - side) / 2,
                          width: side, height: side).integral
        if let cropped = normalizedCG.cropping(to: rect) { self.draft = UIImage(cgImage: cropped) }
    }

    private func normalized(_ image: UIImage) -> UIImage {
        UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    private func save() {
        let oldPhoto = entry.photo
        if let draft {
            guard let jpeg = normalized(draft).jpegData(compressionQuality: 0.84),
                  UIImage(data: jpeg) != nil else {
                errorMessage = "The edited photo could not be saved. Your original is unchanged."
                return
            }
            entry.photo = ImageTools.compressed(jpeg)
        } else {
            entry.photo = nil
        }
        do {
            try context.save()
            dismiss()
        } catch {
            entry.photo = oldPhoto ?? original
            try? context.save()
            errorMessage = "The photo could not be saved. Your original photo and meal details have been restored."
        }
    }
}

private struct MealCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: MealCameraPicker
        init(_ parent: MealCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onImage(info[.originalImage] as? UIImage)
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
