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
        // The text lands in an HTML text node, so it needs HTML escaping — not
        // backslash escaping, which would corrupt every LaTeX command in it.
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        /* Matches Palette.ink / Face.body in Theme.swift. */
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family:-apple-system,BlinkMacSystemFont,sans-serif;
            font-size:15px; color:#1A1714; background:transparent;
            padding:6px 2px; line-height:1.75;
        }
        @media (prefers-color-scheme: dark) {
            body { color:#EDE8DF; }
        }
        .katex { font-size:1.08em; }
        .katex-display { margin:14px 0; }
        </style>
        \(KaTeXAssets.shared.styleTag)
        </head><body>
        <div id="content">\(escaped)</div>
        \(KaTeXAssets.shared.scriptTag)
        <script>
        if (typeof renderMathInElement !== 'undefined') {
            renderMathInElement(document.getElementById('content'), {
                delimiters: [
                    {left:'$$',right:'$$',display:true},
                    {left:'$',right:'$',display:false}
                ],
                throwOnError: false
            });
        }
        function reportHeight() {
            webkit.messageHandlers.heightReporter.postMessage(
                document.getElementById('content').scrollHeight + 20
            );
        }
        reportHeight();
        setTimeout(reportHeight, 150);
        </script>
        </body></html>
        """

        // baseURL is nil, so everything above must be self-contained — no network.
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Void) {
        webView.stopLoading()
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "heightReporter")
    }
}

/// KaTeX inlined from the bundled copy. Assembled once — the CSS carries base64
/// fonts, so building it per render would be wasteful.
private final class KaTeXAssets {
    static let shared = KaTeXAssets()

    let styleTag: String
    let scriptTag: String

    private init() {
        guard let dir = Self.locateKaTeX() else {
            print("LaTeXWebView: bundled KaTeX not found — math will render as plain text.")
            styleTag = ""
            scriptTag = ""
            return
        }

        if let css = try? String(contentsOf: dir.appendingPathComponent("katex.min.css"),
                                 encoding: .utf8) {
            styleTag = "<style>\(Self.inlineFonts(in: css, fontsDir: dir.appendingPathComponent("fonts")))</style>"
        } else {
            styleTag = ""
        }

        let katex = (try? String(contentsOf: dir.appendingPathComponent("katex.min.js"),
                                 encoding: .utf8)) ?? ""
        let autoRender = (try? String(contentsOf: dir.appendingPathComponent("auto-render.min.js"),
                                      encoding: .utf8)) ?? ""
        scriptTag = katex.isEmpty ? "" : "<script>\(katex)</script><script>\(autoRender)</script>"
    }

    private static func locateKaTeX() -> URL? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("ChromeExt/katex"))
        }
        // Running straight from `swift run`, where there is no .app bundle.
        candidates.append(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // Views/
                .deletingLastPathComponent()   // Blocker/
                .appendingPathComponent("ChromeExt/katex")
        )
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Rewrites `url(fonts/X)` to a data URI for each font actually shipped.
    /// References to fonts we don't ship are left alone; the browser skips them.
    private static func inlineFonts(in css: String, fontsDir: URL) -> String {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: fontsDir.path) else {
            return css
        }
        var result = css
        for name in names where name.hasSuffix(".woff2") {
            guard let data = try? Data(contentsOf: fontsDir.appendingPathComponent(name)) else { continue }
            result = result.replacingOccurrences(
                of: "url(fonts/\(name))",
                with: "url(data:font/woff2;base64,\(data.base64EncodedString()))"
            )
        }
        return result
    }
}

private class DynamicHeightHandler: NSObject, WKScriptMessageHandler {
    let callback: (CGFloat) -> Void

    init(callback: @escaping (CGFloat) -> Void) {
        self.callback = callback
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let height = (message.body as? NSNumber)?.doubleValue else { return }
        callback(CGFloat(height))
    }
}
