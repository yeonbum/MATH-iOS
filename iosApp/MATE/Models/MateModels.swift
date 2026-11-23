import Foundation

enum MateRole: String, Codable { case user, assistant }

struct MateMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var role: MateRole
    var text: String
    var date: Date = Date()
    var complete: Bool = true
}

struct MateSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = "새 질문"
    var imageName: String
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var favorite: Bool = false
    var messages: [MateMessage] = []
}

enum MateAnswerStyle: String, CaseIterable, Identifiable {
    case concise = "핵심 위주"
    case balanced = "균형 있게"
    case detailed = "자세하게"
    var id: String { rawValue }
    var instruction: String {
        switch self {
        case .concise: return "핵심 근거를 간결하고 명확하게 설명해 주세요."
        case .balanced: return "중요한 풀이 과정과 근거를 차근차근 충분히 설명해 주세요."
        case .detailed: return "계산 과정과 이유를 빠뜨리지 않고 친절하게 자세히 설명해 주세요."
        }
    }
}

enum MatePrompt {
    static func first(style: MateAnswerStyle) -> String {
        "이미지 속 문제나 질문에 한국어 존댓말로 자연스럽게 답해 주세요. " +
        "필요한 풀이와 근거를 이해하기 쉽게 설명해 주세요. " + style.instruction +
        " 수식은 \\(...\\) 또는 \\[...\\]로 표시하고 \\boxed는 사용하지 마세요."
    }
}
