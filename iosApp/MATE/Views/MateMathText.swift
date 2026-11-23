import SwiftUI
import WebKit

/// KaTeX is bundled by scripts/install_katex.sh; plain-text fallback remains readable.
struct MateMathText: View {
    let text: String
    @State private var height: CGFloat = 70

    var body: some View {
        if Bundle.main.url(forResource: "katex.min", withExtension: "js", subdirectory: "katex") != nil,
           text.contains("\\(") || text.contains("\\[") || text.contains("$$") {
            MateMathWeb(text: text, height: $height)
                .frame(height: min(840, max(50, height)))
        } else {
            Text(text).font(.body).textSelection(.enabled)
        }
    }
}

private struct MateMathWeb: UIViewRepresentable {
    let text: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let content = WKUserContentController()
        content.add(context.coordinator, name: "height")
        config.userContentController = content
        let view = WKWebView(frame: .zero, configuration: config)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.scrollView.isScrollEnabled = true
        view.scrollView.bounces = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.previous != text else { return }
        context.coordinator.previous = text
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <link rel="stylesheet" href="katex/katex.min.css">
        <style>html,body{margin:0;background:transparent;color:#202436;font:16px -apple-system,BlinkMacSystemFont,sans-serif} body{overflow-wrap:anywhere} pre{white-space:pre-wrap;line-height:1.55} .katex-display{overflow-x:auto;overflow-y:hidden}</style>
        </head><body><pre id="answer">\(escaped)</pre>
        <script src="katex/katex.min.js"></script><script src="katex/auto-render.min.js"></script>
        <script>
        if(typeof renderMathInElement === 'function') {
          renderMathInElement(document.getElementById('answer'), {
            delimiters:[{left:'\\\\(',right:'\\\\)',display:false},{left:'\\\\[',right:'\\\\]',display:true},{left:'$$',right:'$$',display:true}],throwOnError:false
          });
        }
        function report(){window.webkit.messageHandlers.height.postMessage(Math.min(840,document.documentElement.scrollHeight+12));}
        setTimeout(report,180); setTimeout(report,500);
        </script></body></html>
        """
        view.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }
    final class Coordinator: NSObject, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var previous: String?
        init(height: Binding<CGFloat>) { _height = height }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let h = message.body as? Double else { return }
            DispatchQueue.main.async { self.height = CGFloat(h) }
        }
    }
}
