import SwiftUI
import UIKit

struct MateChatView: View {
    @EnvironmentObject private var store: MateStore
    @EnvironmentObject private var engine: MateInferenceEngine
    @ObservedObject var files: MateModelFiles
    let sessionID: UUID
    let dismiss: () -> Void
    let openNewFromImage: (UIImage) -> Void

    @AppStorage("answerStyle") private var answerStyle = "균형 있게"
    @State private var question = ""
    @State private var streaming = ""
    @State private var lastError: String?
    @State private var didStart = false
    @FocusState private var inputFocused: Bool

    private var session: MateSession? { store.session(sessionID) }
    private var canFollowUp: Bool {
        session?.messages.contains(where: { $0.role == .assistant && $0.complete }) ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let session, let image = store.image(for: session) {
                            HStack {
                                Image(uiImage: image)
                                    .resizable().scaledToFit()
                                    .frame(maxHeight: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                Spacer(minLength: 0)
                            }
                            Button("이 문제로 새 분석 시작") { openNewFromImage(image) }
                                .font(.caption)
                        }
                        ForEach(session?.messages ?? []) { message in
                            MateBubble(message: message)
                        }
                        if !streaming.isEmpty {
                            MateBubble(message: MateMessage(role: .assistant, text: streaming, complete: false))
                        }
                        if !canFollowUp && !engine.busy {
                            Button {
                                startImageTurn()
                            } label: {
                                Label("풀이 시작하기", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if engine.busy {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(engine.stage).font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Button("취소") { engine.cancel() }.font(.caption)
                            }.padding(14).background(MateStyle.card, in: RoundedRectangle(cornerRadius: 16))
                        }
                        if let lastError {
                            Label(lastError, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: streaming.count / 90) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { scrollProxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: session?.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { scrollProxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            if canFollowUp && !engine.busy {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(["왜 이렇게 풀었나요?", "다른 풀이도 알려주세요", "좀 더 쉽게 설명해 주세요"], id: \.self) { sample in
                            Button(sample) { question = sample; submit() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }.padding(.horizontal, 12)
                }.padding(.vertical, 6)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("궁금한 점을 이어서 물어보세요", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(MateStyle.canvas, in: RoundedRectangle(cornerRadius: 18))
                    .submitLabel(.send)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.busy ? .gray : MateStyle.indigo)
                }
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.busy)
                .accessibilityLabel("질문 보내기")
            }
            .padding(12)
            .background(.bar)
        }
        .navigationTitle(session?.title ?? "MATE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("닫기") { if engine.busy { engine.cancel() }; dismiss() } }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    store.setFavorite(sessionID, !(session?.favorite ?? false))
                } label: { Image(systemName: (session?.favorite ?? false) ? "heart.fill" : "heart") }
                if let session {
                    ShareLink(item: transcript(session)) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .background(MateStyle.canvas)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            guard session?.messages.isEmpty == true else { return }
            startImageTurn()
        }
    }

    private func transcript(_ session: MateSession) -> String {
        (["MATE · \(session.title)"] + session.messages.map { "\($0.role == .assistant ? "MATE" : "나"): \($0.text)" }).joined(separator: "\n\n")
    }

    private func submit() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !engine.busy else { return }
        lastError = nil
        question = ""
        inputFocused = false
        if !canFollowUp {
            lastError = "먼저 이미지 분석을 완료해야 합니다."
            return
        }
        store.addMessage(MateMessage(role: .user, text: trimmed), to: sessionID)
        request(prompt: trimmed, followUp: true)
    }

    private func startImageTurn() {
        guard session != nil, !engine.busy else { return }
        files.refresh()
        let style = MateAnswerStyle(rawValue: answerStyle) ?? .balanced
        let prompt = MatePrompt.first(style: style)
        lastError = nil
        if engine.ready {
            request(prompt: prompt, followUp: false)
        } else if let languageURL = files.languagePath,
                  let visionURL = files.visionPath {
            engine.load(modelURL: languageURL, visionURL: visionURL) { success in
                if success {
                    request(prompt: prompt, followUp: false)
                } else {
                    lastError = "모델 파일은 발견했지만 로딩 실패: "
                        + (engine.errorMessage ?? "원인 알 수 없음")
                }
            }
        } else {
            lastError = "내장 모델 자동 인식 실패. "
                + "언어: " + files.languageStatus + " / 이미지: " + files.visionStatus
        }
    }

    private func request(prompt: String, followUp: Bool) {
        guard let session else { return }
        guard files.languagePath != nil && files.visionPath != nil else {
            lastError = "설정에서 모델 파일 2개를 가져와 주세요."
            return
        }
        guard engine.ready else {
            lastError = "설정에서 '풀이 기능 준비하기'를 먼저 실행해 주세요."
            return
        }
        streaming = ""
        lastError = nil
        engine.generate(sessionID: sessionID, imageURL: store.imageURL(for: session), prompt: prompt,
                        followUp: followUp, maxTokens: 512, onToken: { part in
            streaming += part
        }, completion: { result in
            switch result {
            case .success:
                if !streaming.isEmpty {
                    store.addMessage(MateMessage(role: .assistant, text: streaming), to: sessionID)
                    if !followUp { store.rename(sessionID, suggestTitle(streaming)) }
                }
            case .failure(let err):
                if !streaming.isEmpty {
                    store.addMessage(MateMessage(role: .assistant, text: streaming, complete: false), to: sessionID)
                }
                lastError = err.localizedDescription
            }
            streaming = ""
        })
    }

    private func suggestTitle(_ answer: String) -> String {
        let first = answer.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "문제 풀이"
        return String(first.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces).prefix(32))
    }
}

private struct MateBubble: View {
    let message: MateMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 9) {
                Text(message.role == .assistant ? "MATE" : "나")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if message.role == .assistant {
                    MateMathText(text: message.text)
                } else {
                    Text(message.text).font(.body).textSelection(.enabled)
                }
                if !message.complete { Text("작성 중이거나 중단된 답변입니다.").font(.caption2).foregroundStyle(.secondary) }
                if message.role == .assistant {
                    HStack {
                        Button { UIPasteboard.general.string = message.text } label: { Label("복사", systemImage: "doc.on.doc") }
                        ShareLink(item: message.text) { Label("공유", systemImage: "square.and.arrow.up") }
                    }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(15)
            .background(message.role == .user ? MateStyle.indigo.opacity(0.12) : MateStyle.card,
                        in: RoundedRectangle(cornerRadius: 20))
            if message.role == .assistant { Spacer(minLength: 22) }
        }
    }
}
