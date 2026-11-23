import SwiftUI
import PhotosUI
import UIKit

struct MateRootView: View {
    @EnvironmentObject private var store: MateStore
    @EnvironmentObject private var engine: MateInferenceEngine
    @StateObject private var files = MateModelFiles()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var activeSession: MateSession?
    @State private var showCrop = false
    @State private var selectionError: String?

    var body: some View {
        TabView {
            NavigationStack {
                home
                    .navigationTitle("MATE")
                    .toolbarBackground(MateStyle.canvas, for: .navigationBar)
            }
            .tabItem { Label("홈", systemImage: "house.fill") }

            NavigationStack {
                MateLibraryView(favoritesOnly: false, onOpen: openSession)
                    .navigationTitle("기록")
            }
            .tabItem { Label("기록", systemImage: "clock.arrow.circlepath") }

            NavigationStack {
                MateLibraryView(favoritesOnly: true, onOpen: openSession)
                    .navigationTitle("즐겨찾기")
            }
            .tabItem { Label("즐겨찾기", systemImage: "heart.fill") }

            NavigationStack {
                MateSettingsView(files: files)
                    .navigationTitle("설정")
            }
            .tabItem { Label("설정", systemImage: "gearshape.fill") }
        }
        .sheet(isPresented: $showCamera, onDismiss: {
            if let capturedImage { beginCrop(capturedImage); self.capturedImage = nil }
        }) {
            MateCameraPicker(image: $capturedImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showCrop) {
            if let pendingImage {
                MateCropView(image: pendingImage, onCancel: { showCrop = false }, onUse: { cropped in
                    showCrop = false
                    do {
                        activeSession = try store.create(image: cropped)
                    } catch { selectionError = error.localizedDescription }
                })
            }
        }
        .sheet(item: $activeSession) { session in
            NavigationStack {
                MateChatView(sessionID: session.id, files: files,
                             dismiss: { activeSession = nil },
                             openNewFromImage: { image in
                                activeSession = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { beginCrop(image) }
                             })
            }
        }
        .alert("이미지를 열 수 없습니다", isPresented: Binding(
            get: { selectionError != nil },
            set: { if !$0 { selectionError = nil } }
        )) { Button("확인") { selectionError = nil } } message: { Text(selectionError ?? "") }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                do {
                    guard let data = try await newValue.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { throw MatePickerError.badImage }
                    beginCrop(image)
                } catch { selectionError = error.localizedDescription }
                selectedPhoto = nil
            }
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 35, weight: .semibold))
                        .foregroundStyle(MateStyle.indigo)
                    Text("어려운 문제도,\n이해될 때까지.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("사진으로 질문하고, 대화로 이해하세요.")
                        .foregroundStyle(.secondary)
                    Text("MATE가 함께 풀어드릴게요.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(MateStyle.card, in: RoundedRectangle(cornerRadius: 26))

                Text("새 질문 시작하기")
                    .font(.title3.bold())

                Button { showCamera = true } label: {
                    Label("사진 찍기", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity).frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(MateStyle.indigo)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("앨범에서 가져오기", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.bordered)

                HStack {
                    Text("최근 풀이").font(.title3.bold())
                    Spacer()
                    Text("\(store.sessions.count)개")
                        .foregroundStyle(.secondary)
                }
                if store.sessions.isEmpty {
                    ContentUnavailableView("아직 풀이 기록이 없어요", systemImage: "book.closed", description: Text("사진을 선택하면 첫 풀이를 시작할 수 있어요."))
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(store.sessions.prefix(3)) { session in
                        Button { openSession(session) } label: {
                            MateSessionRow(session: session, image: store.image(for: session))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
        }
        .background(MateStyle.canvas)
    }

    private func beginCrop(_ image: UIImage) {
        pendingImage = image
        showCrop = true
    }
    private func openSession(_ session: MateSession) { activeSession = session }
}

enum MatePickerError: LocalizedError {
    case badImage
    var errorDescription: String? { "이미지 파일을 읽을 수 없습니다." }
}

struct MateCameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: MateCameraPicker
        init(_ parent: MateCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
