import SwiftUI

struct MateSessionRow: View {
    let session: MateSession
    let image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: "doc.text.image").resizable().scaledToFit().padding(12).foregroundStyle(.secondary) }
            }
            .frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).font(.subheadline.bold()).lineLimit(2)
                Text(session.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(session.messages.count)개의 메시지")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if session.favorite { Image(systemName: "heart.fill").foregroundStyle(.pink) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(MateStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MateLibraryView: View {
    @EnvironmentObject private var store: MateStore
    let favoritesOnly: Bool
    let onOpen: (MateSession) -> Void
    @State private var query = ""
    @State private var editing: MateSession?
    @State private var newTitle = ""

    private var filtered: [MateSession] {
        store.sessions.filter { s in
            (!favoritesOnly || s.favorite) && (query.isEmpty || s.title.localizedCaseInsensitiveContains(query) || s.messages.contains { $0.text.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if filtered.isEmpty {
                    ContentUnavailableView(favoritesOnly ? "즐겨찾기가 없어요" : "기록이 없어요", systemImage: favoritesOnly ? "heart" : "clock", description: Text("중요한 풀이를 저장해 두고 다시 확인할 수 있어요."))
                }
                ForEach(filtered) { session in
                    Button { onOpen(session) } label: {
                        MateSessionRow(session: session, image: store.image(for: session))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(session.favorite ? "즐겨찾기 해제" : "즐겨찾기 추가", systemImage: session.favorite ? "heart.slash" : "heart") {
                            store.setFavorite(session.id, !session.favorite)
                        }
                        Button("이름 변경", systemImage: "pencil") {
                            newTitle = session.title; editing = session
                        }
                        Button("삭제", systemImage: "trash", role: .destructive) { store.delete(session.id) }
                    }
                }
            }.padding(16)
        }
        .background(MateStyle.canvas)
        .searchable(text: $query, prompt: "제목 또는 풀이 검색")
        .alert("기록 이름 변경", isPresented: Binding(
            get: { editing != nil }, set: { if !$0 { editing = nil } }
        )) {
            TextField("제목", text: $newTitle)
            Button("저장") { if let editing { store.rename(editing.id, newTitle) }; editing = nil }
            Button("취소", role: .cancel) { editing = nil }
        } message: { Text("이름은 언제든 다시 변경할 수 있어요.") }
    }
}
