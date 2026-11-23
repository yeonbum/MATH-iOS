import Combine
import Foundation
import UIKit

@MainActor
final class MateStore: ObservableObject {
    @Published private(set) var sessions: [MateSession] = []
    @Published var statusMessage: String?
    private let directory: URL
    private let database: URL

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MATE", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directory = root
        database = root.appendingPathComponent("sessions.json")
        if let data = try? Data(contentsOf: database),
           let decoded = try? JSONDecoder().decode([MateSession].self, from: data) {
            sessions = decoded.sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    func create(image: UIImage) throws -> MateSession {
        let session = MateSession(imageName: UUID().uuidString + ".jpg")
        guard let data = image.jpegData(compressionQuality: 0.86) else {
            throw MateStoreError.imageEncoding
        }
        try data.write(to: directory.appendingPathComponent(session.imageName), options: .atomic)
        sessions.insert(session, at: 0)
        save()
        return session
    }

    func image(for session: MateSession) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(session.imageName).path)
    }

    func imageURL(for session: MateSession) -> URL {
        directory.appendingPathComponent(session.imageName)
    }

    func session(_ id: UUID) -> MateSession? { sessions.first(where: { $0.id == id }) }

    func addMessage(_ message: MateMessage, to id: UUID) {
        mutate(id) { $0.messages.append(message) }
    }

    func updateMessage(_ id: UUID, in sessionID: UUID, text: String, complete: Bool) {
        mutate(sessionID) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == id }) else { return }
            session.messages[index].text = text
            session.messages[index].complete = complete
        }
    }

    func setFavorite(_ id: UUID, _ value: Bool) { mutate(id) { $0.favorite = value } }
    func rename(_ id: UUID, _ value: String) { mutate(id) { $0.title = String(value.prefix(70)) } }

    func delete(_ id: UUID) {
        guard let target = session(id) else { return }
        try? FileManager.default.removeItem(at: imageURL(for: target))
        sessions.removeAll { $0.id == id }
        save()
    }

    private func mutate(_ id: UUID, _ body: (inout MateSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        body(&sessions[index])
        sessions[index].modifiedAt = Date()
        sessions.sort { $0.modifiedAt > $1.modifiedAt }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: database, options: .atomic)
        } catch {
            statusMessage = "기록을 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }
}

enum MateStoreError: LocalizedError {
    case imageEncoding
    var errorDescription: String? { "이미지를 저장할 수 없습니다." }
}
