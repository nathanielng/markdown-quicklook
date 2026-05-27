import Cocoa
import WebKit
import QuickLookUI
import JavaScriptCore

// View-based QuickLook extension — mirrors the approach used by working
// third-party extensions (e.g. Mindle). Uses NSViewController + WKWebView
// + QLPreviewingController instead of QLPreviewProvider (data-based), because:
//   1. WKWebView executes JavaScript, so marked.js runs normally.
//   2. QLPreviewReply's WebKit context does NOT execute JS → blank preview.
//   3. This matches the pattern of every working third-party QL extension.

@objc(PreviewViewController)
class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var completionHandler: ((Error?) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        view = webView
    }

    // Called by QuickLook for file-based previews.
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let ext = url.pathExtension.lowercased()
        let supportedMarkdown = ["md","markdown","mdown","mkd","mkdn"]
        let supportedYAML = ["yaml","yml"]
        guard supportedMarkdown.contains(ext) || supportedYAML.contains(ext) else {
            handler(nil)
            return
        }

        self.completionHandler = handler
        let html: String
        if supportedYAML.contains(ext) {
            html = renderCode(url: url, language: "yaml")
        } else {
            html = render(url: url)
        }
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completionHandler?(nil)
        completionHandler = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completionHandler?(error)
        completionHandler = nil
    }
}

// MARK: - Rendering

private func renderCode(url: URL, language: String) -> String {
    let content: String
    if let s = try? String(contentsOf: url, encoding: .utf8) {
        content = s
    } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
        content = s
    } else {
        content = "Could not read file."
    }

    let bundle = Bundle(for: PreviewViewController.self)
    let css = resource(bundle: bundle, name: "preview", ext: "css")
    let hljsJS = resource(bundle: bundle, name: "highlight.min", ext: "js")
    let title = htmlEscape(url.lastPathComponent)
    let escaped = htmlEscape(content)

    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>\(title)</title>
    <style>\(css)</style>
    </head>
    <body>
    <article class="markdown-body">
    <pre><code class="language-\(language)">\(escaped)</code></pre>
    </article>
    <script>\(hljsJS)</script>
    <script>hljs.highlightAll();</script>
    </body>
    </html>
    """
}

private func render(url: URL) -> String {
    let markdown: String
    if let s = try? String(contentsOf: url, encoding: .utf8) {
        markdown = s
    } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
        markdown = s
    } else {
        markdown = "*Could not read file.*"
    }

    let bundle = Bundle(for: PreviewViewController.self)
    let css      = resource(bundle: bundle, name: "preview",    ext: "css")
    let markedJS = resource(bundle: bundle, name: "marked.min", ext: "js")

    // Escape markdown for embedding in a JS template literal
    let escaped = markdown
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`",  with: "\\`")
        .replacingOccurrences(of: "${", with: "\\${")
        .replacingOccurrences(of: "</script>", with: "<\\/script>", options: .caseInsensitive)
    let title = htmlEscape(url.deletingPathExtension().lastPathComponent)

    // JS runs inside WKWebView — no restrictions here.
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>\(title)</title>
    <style>\(css)</style>
    </head>
    <body>
    <article class="markdown-body">
    <div id="content"></div>
    </article>
    <script>\(markedJS)</script>
    <script>
    (function() {
      var md = `\(escaped)`;
      marked.use({ gfm: true, breaks: false });
      document.getElementById('content').innerHTML = marked.parse(md);
      document.querySelectorAll('li').forEach(function(li) {
        if (li.querySelector('input[type="checkbox"]'))
          li.classList.add('task-list-item');
      });
    })();
    </script>
    </body>
    </html>
    """
}

private func resource(bundle: Bundle, name: String, ext: String) -> String {
    guard let url = bundle.url(forResource: name, withExtension: ext),
          let s   = try? String(contentsOf: url, encoding: .utf8) else { return "" }
    return s
}

private func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
}
