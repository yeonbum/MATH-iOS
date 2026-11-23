import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MateModelFiles: ObservableObject {
    @Published var languagePath: URL?
    @Published var visionPath: URL?
    @Published var busy = false
    @Published var message = ""
    @Published private(set) var languageStatus = "검사 전"
    @Published private(set) var visionStatus = "검사 전"
    @Published private(set) var bundleDiagnostic = ""

    private let folder: URL
    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MATE/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refresh()
    }

    // Always look at the real installed .app folder. This also works with models
    // inserted into Payload/MATE.app/Models BEFORE the IPA was signed.
    func refresh() {
        let fm = FileManager.default
        let importedLanguage = importedURL(for: "mate.languageGGUF")
        let importedVision = importedURL(for: "mate.visionGGUF")
        let bundledLanguage = bundledURL(named: "language.gguf")
        let bundledVision = bundledURL(named: "vision.gguf")

        languagePath = importedLanguage ?? bundledLanguage
        visionPath = importedVision ?? bundledVision

        languageStatus = status(path: languagePath, imported: importedLanguage != nil,
                                expected: "Models/language.gguf")
        visionStatus = status(path: visionPath, imported: importedVision != nil,
                              expected: "Models/vision.gguf")

        let modelsDirectory = Bundle.main.bundleURL.appendingPathComponent("Models", isDirectory: true)
        let names = (try? fm.contentsOfDirectory(atPath: modelsDirectory.path)) ?? []
        bundleDiagnostic = names.isEmpty
            ? "설치된 앱 내부의 Models 폴더가 비어 있거나 없습니다."
            : "앱 내부 Models 폴더: " + names.sorted().joined(separator: ", ")
    }

    private func importedURL(for key: String) -> URL? {
        guard let name = UserDefaults.standard.string(forKey: key) else { return nil }
        let candidate = folder.appendingPathComponent(name)
        return isValidFile(candidate) ? candidate : nil
    }

    private func bundledURL(named name: String) -> URL? {
        let stem = String(name.dropLast(5)) // remove '.gguf'
        let candidates: [URL?] = [
            // Explicit path is more robust for an IPA modified after xcodebuild.
            Bundle.main.bundleURL.appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.url(forResource: stem, withExtension: "gguf", subdirectory: "Models")
        ]
        return candidates.compactMap { $0 }.first(where: isValidFile)
    }

    private func isValidFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let count = attributes[.size] as? NSNumber else { return false }
        return count.int64Value > 0
    }

    private func status(path: URL?, imported: Bool, expected: String) -> String {
        guard let path else { return "찾지 못함 · 기대 위치: " + expected }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size]
                     as? NSNumber)?.int64Value ?? 0
        let size = String(format: "%.2f GB", Double(bytes) / 1_000_000_000.0)
        return (imported ? "사용자 파일" : "앱 내장") + " 인식됨 · " + size
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
