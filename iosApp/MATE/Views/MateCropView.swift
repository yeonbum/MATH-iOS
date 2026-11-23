import SwiftUI
import UIKit

/// Normalized selection of a rectangular region. Works with portrait/landscape images.
struct MateCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onUse: (UIImage) -> Void
    @State private var crop = CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84)
    @State private var lastCrop: CGRect?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("풀이할 문제를 선택해 주세요")
                    .font(.headline)
                GeometryReader { space in
                    let size = image.size
                    let fit = min(space.size.width / max(size.width, 1), space.size.height / max(size.height, 1))
                    let drawSize = CGSize(width: size.width * fit, height: size.height * fit)
                    let origin = CGPoint(x: (space.size.width - drawSize.width)/2, y: (space.size.height - drawSize.height)/2)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: drawSize.width, height: drawSize.height)
                            .position(x: origin.x + drawSize.width/2, y: origin.y + drawSize.height/2)
                        Rectangle()
                            .fill(.clear)
                            .border(MateStyle.indigo, width: 3)
                            .background(MateStyle.indigo.opacity(0.10))
                            .frame(width: crop.width * drawSize.width, height: crop.height * drawSize.height)
                            .position(x: origin.x + (crop.minX+crop.width/2)*drawSize.width,
                                      y: origin.y + (crop.minY+crop.height/2)*drawSize.height)
                            .gesture(DragGesture()
                                .onChanged { value in
                                    if lastCrop == nil { lastCrop = crop }
                                    guard let initial = lastCrop else { return }
                                    let dx = value.translation.width / max(drawSize.width,1)
                                    let dy = value.translation.height / max(drawSize.height,1)
                                    crop.origin.x = min(max(0, initial.minX + dx), 1-initial.width)
                                    crop.origin.y = min(max(0, initial.minY + dy), 1-initial.height)
                                }
                                .onEnded { _ in lastCrop = nil }
                            )
                    }
                }
                .padding(10)
                Text("테두리 안쪽을 드래그해서 문제 위치를 옮길 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("영역 좁히기") { resize(-0.10) }.buttonStyle(.bordered)
                    Button("영역 넓히기") { resize(0.10) }.buttonStyle(.bordered)
                    Button("전체") { crop = CGRect(x:0,y:0,width:1,height:1) }.buttonStyle(.bordered)
                }
                Button {
                    guard let normalized = image.normalizedImage(),
                          let clipped = normalized.cgImage?.cropping(to: CGRect(
                              x: crop.minX * normalized.size.width,
                              y: crop.minY * normalized.size.height,
                              width: crop.width * normalized.size.width,
                              height: crop.height * normalized.size.height
                          )) else { onUse(image); return }
                    onUse(UIImage(cgImage: clipped))
                } label: {
                    Text("이 문제로 질문하기").bold()
                        .frame(maxWidth: .infinity).frame(height: 46)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .navigationTitle("문제 자르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소", action: onCancel) } }
        }
    }
    private func resize(_ change: CGFloat) {
        let cx = crop.midX, cy = crop.midY
        let w = min(1, max(0.2, crop.width + change)), h = min(1, max(0.2, crop.height + change))
        crop = CGRect(x: min(max(0, cx - w/2), 1-w), y: min(max(0, cy - h/2), 1-h), width: w, height: h)
    }
}

extension UIImage {
    func normalizedImage() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
