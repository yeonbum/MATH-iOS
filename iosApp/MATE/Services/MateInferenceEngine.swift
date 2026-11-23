import Combine
import Foundation

// A serial queue is essential: model context, multi-turn KV-cache and mtmd share native state.
final class MateInferenceEngine: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    @Published private(set) var stage = ""
    @Published private(set) var errorMessage: String?

    private let queue = DispatchQueue(label: "dev.mateapp.inference", qos: .userInitiated)
    private var tokenSink: ((String) -> Void)?
    private var activeSession: UUID?
    private var loadedPair: (String, String)?

    func load(modelURL: URL, visionURL: URL, completion: @escaping (Bool) -> Void) {
        guard !busy else { completion(false); return }
        busy = true
        stage = "모델을 준비하고 있어요"
        errorMessage = nil
        let model = modelURL.path
        let vision = visionURL.path
        queue.async { [weak self] in
            guard let self else { return }
            let result = model.withCString { m in
                vision.withCString { v in String(cString: mate_load(m, v, 2048, 4, 8)) }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.ready = result.hasPrefix("OK:")
                self.loadedPair = self.ready ? (model, vision) : nil
                if !self.ready { self.errorMessage = result }
                self.stage = ""
                completion(self.ready)
            }
        }
    }

    func generate(sessionID: UUID, imageURL: URL, prompt: String,
                  followUp: Bool, maxTokens: Int = 512,
                  onToken: @escaping (String) -> Void,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        guard !busy else { completion(.failure(MateNativeError.busy)); return }
        guard ready else { completion(.failure(MateNativeError.notReady)); return }
        if followUp && activeSession != sessionID {
            completion(.failure(MateNativeError.sessionChanged))
            return
        }
        busy = true
        stage = followUp ? "답변을 작성하고 있어요" : "문제를 분석하고 있어요"
        errorMessage = nil
        tokenSink = onToken
        let context = Unmanaged.passUnretained(self).toOpaque()
        queue.async { [weak self] in
            guard let self else { return }
            let status: String
            if followUp {
                status = prompt.withCString { String(cString: mate_followup($0, Int32(maxTokens), mateSwiftToken, context)) }
            } else {
                status = imageURL.path.withCString { file in
                    prompt.withCString { question in
                        String(cString: mate_generate_image(file, question, Int32(maxTokens), mateSwiftToken, context))
                    }
                }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.tokenSink = nil
                self.stage = ""
                if status.hasPrefix("OK:") {
                    self.activeSession = sessionID
                    completion(.success(()))
                } else {
                    self.activeSession = nil
                    self.errorMessage = status
                    completion(.failure(MateNativeError.failed(status)))
                }
            }
        }
    }

    func cancel() { mate_cancel() }

    fileprivate func receive(_ part: String) {
        DispatchQueue.main.async { [weak self] in self?.tokenSink?(part) }
    }
}

private let mateSwiftToken: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { text, context in
    guard let text, let context else { return }
    let engine = Unmanaged<MateInferenceEngine>.fromOpaque(context).takeUnretainedValue()
    engine.receive(String(cString: text))
}

enum MateNativeError: LocalizedError {
    case busy, notReady, sessionChanged, failed(String)
    var errorDescription: String? {
        switch self {
        case .busy: "이미 다른 답변을 작성하고 있어요."
        case .notReady: "먼저 설정에서 모델 파일을 가져오고 준비해 주세요."
        case .sessionChanged: "과거 대화를 이어가려면 먼저 이미지를 다시 분석해 주세요."
        case let .failed(error): error
        }
    }
}
