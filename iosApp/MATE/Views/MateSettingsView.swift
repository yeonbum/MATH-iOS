import SwiftUI
import UniformTypeIdentifiers

struct MateSettingsView: View {
    @ObservedObject var files: MateModelFiles
    @EnvironmentObject private var engine: MateInferenceEngine
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("answerStyle") private var answerStyle = "균형 있게"
    @State private var importVision = false
    @State private var importing = false

    var body: some View {
        Form {
            Section("답변") {
                Picker("설명 방식", selection: $answerStyle) {
                    ForEach(MateAnswerStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("화면 테마", selection: $appearance) {
                    Text("기기 설정").tag("system")
                    Text("밝게").tag("light")
                    Text("어둡게").tag("dark")
                }
            }
            Section("학습 준비") {
                HStack {
                    Label("언어 모델", systemImage: "cpu")
                    Spacer()
                    Image(systemName: files.languagePath == nil ? "circle.dashed" : "checkmark.circle.fill")
                        .foregroundStyle(files.languagePath == nil ? Color.secondary : Color.green)
                }
                Button("언어 모델 파일 가져오기") { importVision = false; importing = true }
                HStack {
                    Label("이미지 모델", systemImage: "photo")
                    Spacer()
                    Image(systemName: files.visionPath == nil ? "circle.dashed" : "checkmark.circle.fill")
                        .foregroundStyle(files.visionPath == nil ? Color.secondary : Color.green)
                }
                Button("이미지 모델 파일 가져오기") { importVision = true; importing = true }
                Button {
                    guard let model = files.languagePath, let vision = files.visionPath else { return }
                    engine.load(modelURL: model, visionURL: vision) { _ in }
                } label: {
                    HStack {
                        Text(engine.busy ? "준비하는 중..." : engine.ready ? "모델 준비 완료" : "풀이 기능 준비하기")
                        Spacer()
                        if engine.busy { ProgressView() }
                    }
                }
                .disabled(files.languagePath == nil || files.visionPath == nil || engine.busy)
                Text(files.message).font(.caption).foregroundStyle(.secondary)
                if let error = engine.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section("앱 정보") {
                LabeledContent("앱 이름", value: "MATE")
                LabeledContent("버전", value: "1.0")
                Text("문제를 촬영하고, 답변을 읽고, 궁금한 내용을 이어서 질문할 수 있어요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { files.install(from: url, forVision: importVision) }
            case .failure(let error): files.message = error.localizedDescription
            }
        }
    }
}
