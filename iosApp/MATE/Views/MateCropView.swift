import SwiftUI
import UIKit

/// The on-screen rectangle and the output CGImage crop are derived from the same
/// upright, pixel-sized image. This avoids camera EXIF orientation and aspect-fit offsets.
struct MateCropView: View {
    let onCancel: () -> Void
    let onUse: (UIImage) -> Void

    private let uprightImage: UIImage

    // All four values are fractions of the upright image (0...1).
    @State private var crop = CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84)
    @State private var moveStart: CGRect?
    @State private var resizeStart: CGRect?
    @State private var activeHandle: MateCropHandle?
    @State private var previewImage: UIImage?
    @State private var showPreview = false
    @State private var cropError: String?

    init(image: UIImage, onCancel: @escaping () -> Void, onUse: @escaping (UIImage) -> Void) {
        self.uprightImage = image.mateUprightPixelImage()
        self.onCancel = onCancel
        self.onUse = onUse
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("문제가 있는 부분만 선택해 주세요")
                    .font(.headline)

                GeometryReader { geometry in
                    let layout = MateCropLayout(imageSize: uprightImage.size, containerSize: geometry.size)
                    let selected = layout.displayRect(for: crop)

                    ZStack(alignment: .topLeading) {
                        Color(uiColor: .secondarySystemGroupedBackground)

                        Image(uiImage: uprightImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: layout.imageRect.width, height: layout.imageRect.height)
                            .position(x: layout.imageRect.midX, y: layout.imageRect.midY)
                            .accessibilityHidden(true)

                        // Dim only the image outside the selected rectangle.
                        Path { path in
                            path.addRect(layout.imageRect)
                            path.addRect(selected)
                        }
                        .fill(Color.black.opacity(0.46), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)

                        Rectangle()
                            .fill(MateStyle.indigo.opacity(0.07))
                            .overlay {
                                Rectangle().strokeBorder(Color.white, lineWidth: 2)
                            }
                            .frame(width: selected.width, height: selected.height)
                            .contentShape(Rectangle())
                            .position(x: selected.midX, y: selected.midY)
                            .gesture(moveGesture(layout: layout))
                            .accessibilityLabel("선택 영역 이동")

                        // Rule-of-thirds grid: purely decorative and never intercepts touches.
                        Path { path in
                            for i in 1...2 {
                                let fraction = CGFloat(i) / 3.0
                                let x = selected.minX + selected.width * fraction
                                let y = selected.minY + selected.height * fraction
                                path.move(to: CGPoint(x: x, y: selected.minY))
                                path.addLine(to: CGPoint(x: x, y: selected.maxY))
                                path.move(to: CGPoint(x: selected.minX, y: y))
                                path.addLine(to: CGPoint(x: selected.maxX, y: y))
                            }
                        }
                        .stroke(Color.white.opacity(0.65), lineWidth: 0.8)
                        .allowsHitTesting(false)

                        ForEach(MateCropHandle.allCases, id: \.self) { handle in
                            Circle()
                                .fill(Color.white)
                                .frame(width: 17, height: 17)
                                .overlay { Circle().stroke(MateStyle.indigo, lineWidth: 2.5) }
                                .frame(width: 44, height: 44) // Large, touch-friendly target
                                .contentShape(Rectangle())
                                .position(handle.point(in: selected))
                                .gesture(resizeGesture(handle: handle, layout: layout))
                                .accessibilityLabel(handle.accessibilityText)
                        }
                    }
                    // Crucial: positions above are relative to GeometryReader, NOT an
                    // intrinsic-sized ZStack centered elsewhere in the available space.
                    .frame(width: geometry.size.width, height: geometry.size.height,
                           alignment: .topLeading)
                    .clipped()
                }

                Text("박스 안쪽을 드래그해 이동하고, 모서리나 변의 동그라미를 드래그해 크기를 조절하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("전체 선택") {
                        crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                    }
                    .buttonStyle(.bordered)

                    Button("선택 영역 미리보기") { previewSelectedRegion() }
                        .buttonStyle(.bordered)
                }

                Button(action: useSelectedRegion) {
                    Text("이 영역으로 질문하기")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(MateStyle.indigo)
            }
            .padding(16)
            .navigationTitle("문제 자르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
            }
            .sheet(isPresented: $showPreview) {
                NavigationStack {
                    VStack(spacing: 14) {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        Text("실제로 질문에 전달될 사진입니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .navigationTitle("잘린 이미지 확인")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("돌아가기") { showPreview = false }
                        }
                    }
                }
            }
            .alert("사진을 자르지 못했습니다", isPresented: Binding(
                get: { cropError != nil },
                set: { if !$0 { cropError = nil } }
            )) {
                Button("확인") { cropError = nil }
            } message: {
                Text(cropError ?? "")
            }
        }
    }

    private func moveGesture(layout: MateCropLayout) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if moveStart == nil { moveStart = crop }
                guard let start = moveStart else { return }
                let dx = value.translation.width / max(layout.imageRect.width, 1)
                let dy = value.translation.height / max(layout.imageRect.height, 1)
                let x = min(max(0, start.minX + dx), 1 - start.width)
                let y = min(max(0, start.minY + dy), 1 - start.height)
                crop = CGRect(x: x, y: y, width: start.width, height: start.height)
            }
            .onEnded { _ in moveStart = nil }
    }

    private func resizeGesture(handle: MateCropHandle, layout: MateCropLayout) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeHandle != handle {
                    activeHandle = handle
                    resizeStart = crop
                }
                guard let start = resizeStart else { return }
                let dx = value.translation.width / max(layout.imageRect.width, 1)
                let dy = value.translation.height / max(layout.imageRect.height, 1)
                crop = handle.resized(start, dx: dx, dy: dy)
            }
            .onEnded { _ in
                activeHandle = nil
                resizeStart = nil
            }
    }

    private func previewSelectedRegion() {
        guard let result = makeCroppedImage() else { return }
        previewImage = result
        showPreview = true
    }

    private func useSelectedRegion() {
        guard let result = makeCroppedImage() else { return }
        onUse(result)
    }

    /// Crop in CGImage pixels, never in UIKit points. The visual selection uses
    /// exactly the same normalized crop on the same uprightImage.
    private func makeCroppedImage() -> UIImage? {
        guard let source = uprightImage.cgImage else {
            cropError = "이미지 픽셀 데이터가 없어 자르기를 수행할 수 없습니다."
            return nil
        }
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else {
            cropError = "이미지의 크기가 올바르지 않습니다."
            return nil
        }
        let w = CGFloat(width)
        let h = CGFloat(height)
        let left = max(0, min(width - 1, Int(floor(crop.minX * w))))
        let top = max(0, min(height - 1, Int(floor(crop.minY * h))))
        let right = max(left + 1, min(width, Int(ceil(crop.maxX * w))))
        let bottom = max(top + 1, min(height, Int(ceil(crop.maxY * h))))
        let pixelRect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        guard let result = source.cropping(to: pixelRect) else {
            cropError = "선택한 영역을 잘라낼 수 없습니다. 다시 선택해 주세요."
            return nil
        }
        return UIImage(cgImage: result, scale: 1, orientation: .up)
    }
}

private struct MateCropLayout {
    let imageRect: CGRect

    init(imageSize: CGSize, containerSize: CGSize) {
        let scale = min(containerSize.width / max(imageSize.width, 1),
                        containerSize.height / max(imageSize.height, 1))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        imageRect = CGRect(x: (containerSize.width - size.width) / 2,
                           y: (containerSize.height - size.height) / 2,
                           width: size.width, height: size.height)
    }

    func displayRect(for normalized: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + normalized.minX * imageRect.width,
               y: imageRect.minY + normalized.minY * imageRect.height,
               width: normalized.width * imageRect.width,
               height: normalized.height * imageRect.height)
    }
}

private enum MateCropHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    var accessibilityText: String {
        switch self {
        case .topLeft: return "왼쪽 위 크기 조절"
        case .top: return "위쪽 크기 조절"
        case .topRight: return "오른쪽 위 크기 조절"
        case .right: return "오른쪽 크기 조절"
        case .bottomRight: return "오른쪽 아래 크기 조절"
        case .bottom: return "아래쪽 크기 조절"
        case .bottomLeft: return "왼쪽 아래 크기 조절"
        case .left: return "왼쪽 크기 조절"
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        let x: CGFloat
        if movesLeft { x = rect.minX }
        else if movesRight { x = rect.maxX }
        else { x = rect.midX }

        let y: CGFloat
        if movesTop { y = rect.minY }
        else if movesBottom { y = rect.maxY }
        else { y = rect.midY }
        return CGPoint(x: x, y: y)
    }

    func resized(_ start: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        let minimumSpan: CGFloat = 0.04
        var left = start.minX
        var right = start.maxX
        var top = start.minY
        var bottom = start.maxY

        if movesLeft { left = min(max(0, start.minX + dx), start.maxX - minimumSpan) }
        if movesRight { right = max(min(1, start.maxX + dx), start.minX + minimumSpan) }
        if movesTop { top = min(max(0, start.minY + dy), start.maxY - minimumSpan) }
        if movesBottom { bottom = max(min(1, start.maxY + dy), start.minY + minimumSpan) }

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

private extension UIImage {
    /// Render EXIF-oriented camera photos into upright pixels once.
    /// Keeping scale = 1 makes UIImage.size equal to CGImage pixel dimensions.
    func mateUprightPixelImage() -> UIImage {
        guard let originalPixels = cgImage else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                draw(in: CGRect(origin: .zero, size: size))
            }
        }

        if imageOrientation == .up {
            return UIImage(cgImage: originalPixels, scale: 1, orientation: .up)
        }

        let swapAxes: Bool
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored: swapAxes = true
        default: swapAxes = false
        }
        let target = CGSize(width: CGFloat(swapAxes ? originalPixels.height : originalPixels.width),
                            height: CGFloat(swapAxes ? originalPixels.width : originalPixels.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
