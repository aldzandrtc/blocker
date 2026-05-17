import SwiftUI
import WebKit

struct LaTeXWebView: NSViewRepresentable {
    let text: String
    @Binding var dynamicHeight: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let handler = DynamicHeightHandler { height in
            DispatchQueue.main.async {
                self.dynamicHeight = height
            }
        }
        config.userContentController.add(handler, name: "heightReporter")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.isInspectable = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let html = """
        <!DOCTYPE html>
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>
        <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family:-apple-system,BlinkMacSystemFont,sans-serif;
            font-size:15px; color:#e0e0e0; background:transparent;
            padding:8px 12px; line-height:1.6;
        }
        .katex { font-size:1.1em; }
        </style></head><body>
        <div id="content">\(escaped)</div>
        <script>
        renderMathInElement(document.getElementById('content'), {
            delimiters: [
                {left:'$$',right:'$$',display:true},
                {left:'$',right:'$',display:false}
            ],
            throwOnError: false
        });
        setTimeout(() => {
            webkit.messageHandlers.heightReporter.postMessage(
                document.getElementById('content').scrollHeight + 20
            );
        }, 150);
        </script>
        </body></html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Void) {
        webView.stopLoading()
    }
}

private class DynamicHeightHandler: NSObject, WKScriptMessageHandler {
    let callback: (CGFloat) -> Void

    init(callback: @escaping (CGFloat) -> Void) {
        self.callback = callback
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let height = message.body as? CGFloat else { return }
        callback(height)
    }
}
