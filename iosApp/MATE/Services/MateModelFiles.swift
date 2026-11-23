import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MateModelFiles: ObservableObject {
    @Published var languagePath: URL?
    @Published var visionPath: URL?
    @Published var busy = false
    @Published var message = ""

    private let folder: URL
    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MATE/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refresh()
    }

    func refresh() {
        let modelName = UserDefaults.standard.string(forKey: "mate.languageGGUF")
        let visionName = UserDefaults.standard.string(forKey: "mate.visionGGUF")
        languagePath = modelName.flatMap { name in
            let path = folder.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: path.path) ? path : nil
        }
        visionPath = visionName.flatMap { name in
            let path = folder.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: path.path) ? path : nil
        }
    }

    func install(from pickedURL: URL, forVision: Bool) {
        guard !busy else { return }
        busy = true
        message = "파일을 가져오는 중입니다."
        // Preserve original filename and bytes (both Qwen 4B quantization variants supported).
        let target = folder.appendingPathComponent(pickedURL.lastPathComponent)
        // Copy on a utility queue; memory is not loaded into a single Data buffer.
        DispatchQueue.global(qos: .utility).async {
            let scoped = pickedURL.startAccessingSecurityScopedResource()
            defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }
            do {
                guard pickedURL.pathExtension.lowercased() == "gguf" else {
                    throw MateFileError.notGGUF
                }
                let tmp = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".partial")
                try FileManager.default.copyItem(at: pickedURL, to: tmp)
                if FileManager.default.fileExists(atPath: target.path) {
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
                } else {
                    try FileManager.default.moveItem(at: tmp, to: target)
                }
                DispatchQueue.main.async { [weak self] in
                    UserDefaults.standard.set(target.lastPathComponent, forKey: forVision ? "mate.visionGGUF" : "mate.languageGGUF")
                    self?.busy = false
                    self?.refresh()
                    self?.message = "파일을 가져왔습니다."
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.busy = false
                    self?.message = "파일 가져오기 실패: \(error.localizedDescription)"
                }
            }
        }
    }
}

enum MateFileError: LocalizedError {
    case notGGUF
    var errorDescription: String? { "GGUF 파일을 선택해 주세요." }
}
