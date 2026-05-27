import Cocoa
import WebKit
import JavaScriptCore

// MARK: - App entry point

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    var windowControllers: [MarkdownWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        // If launched with no files, show the welcome window
        if NSApp.windows.isEmpty {
            showWelcomeWindow()
        }
    }

    // Called by macOS when files are opened via double-click, Open With, or drag-onto-dock
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for path in filenames {
            openMarkdownFile(URL(fileURLWithPath: path))
        }
        NSApp.reply(toOpenOrPrint: .success)
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        runOpenPanel()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Actions

    @objc func openDocument(_ sender: Any?) { runOpenPanel() }

    // MARK: - Helpers

    func openMarkdownFile(_ url: URL) {
        let wc = MarkdownWindowController(url: url)
        windowControllers.append(wc)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func runOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []     // rely on extension filter below
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Open Markdown files"
        panel.prompt = "Open"
        // Filter to known markdown extensions
        panel.allowedFileTypes = ["md", "markdown", "mdown", "mkd", "mkdn", "yaml", "yml"]
        if panel.runModal() == .OK {
            for url in panel.urls { openMarkdownFile(url) }
        }
    }

    func showWelcomeWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "MarkdownQL"
        win.center()
        win.isReleasedWhenClosed = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "MarkdownQL")
        heading.font = .boldSystemFont(ofSize: 15)
        heading.alignment = .center

        let body = NSTextField(labelWithString:
            "Double-click any .md file, or use File → Open.\nQuickLook extension is also installed.")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.maximumNumberOfLines = 3

        let openBtn = NSButton(title: "Open File…", target: self, action: #selector(openDocument(_:)))
        openBtn.bezelStyle = .rounded
        openBtn.keyEquivalent = "\r"

        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(body)
        stack.addArrangedSubview(openBtn)

        win.contentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: win.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: win.contentView!.bottomAnchor),
        ])
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu

    func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit MarkdownQL", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        NSApp.mainMenu = mainMenu
    }
}

// MARK: - Markdown Window

class MarkdownWindowController: NSWindowController, NSWindowDelegate {
    let fileURL: URL
    private var webView: WKWebView!

    init(url: URL) {
        self.fileURL = url
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = url.lastPathComponent
        win.titlebarAppearsTransparent = false
        win.center()
        win.isReleasedWhenClosed = true
        super.init(window: win)
        win.delegate = self
        setupWebView()
        loadFile()
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.windowControllers.removeAll { $0 === self }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // Allow local file reads so we could also serve assets if needed
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        window!.contentView!.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor),
            webView.topAnchor.constraint(equalTo: window!.contentView!.topAnchor),
            webView.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor),
        ])
    }

    private func loadFile() {
        let html = HTMLRenderer.shared.render(fileURL: fileURL)
        // Use baseURL of file's directory so relative links in the markdown resolve
        webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
    }
}

// MARK: - HTML Renderer (shared between app and extension)

class HTMLRenderer {
    static let shared = HTMLRenderer()

    private let jsContext: JSContext?
    private let css: String
    private let hljsScript: String

    private init() {
        let bundle = Bundle.main
        css = HTMLRenderer.loadResource(bundle: bundle, name: "preview", ext: "css")
        hljsScript = HTMLRenderer.loadResource(bundle: bundle, name: "highlight.min", ext: "js")

        guard let ctx = JSContext(),
              let js = HTMLRenderer.loadResourceOpt(bundle: bundle, name: "marked.min", ext: "js") else {
            jsContext = nil
            return
        }
        ctx.evaluateScript(js)
        jsContext = ctx
    }

    func render(fileURL url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let markdown: String
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            markdown = s
        } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
            markdown = s
        } else {
            markdown = "*Could not read file.*"
        }

        let title = htmlEscape(url.deletingPathExtension().lastPathComponent)

        if ["yaml", "yml"].contains(ext) {
            return buildCodePage(title: title, code: markdown, language: "yaml")
        }

        let body = renderBody(markdown)
        return buildPage(title: title, body: body)
    }

    private func renderBody(_ markdown: String) -> String {
        guard let ctx = jsContext else {
            return "<pre>\(htmlEscape(markdown))</pre>"
        }
        ctx.setObject(markdown, forKeyedSubscript: "__md" as NSString)
        let result = ctx.evaluateScript(
            "(function(){ marked.use({gfm:true,breaks:false}); return marked.parse(__md); })()"
        )
        let html = result?.toString() ?? ""
        guard !html.isEmpty, html != "undefined" else {
            return "<pre>\(htmlEscape(markdown))</pre>"
        }
        return html
    }

    private func buildPage(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    private func buildCodePage(title: String, code: String, language: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        <pre><code class="language-\(language)">\(htmlEscape(code))</code></pre>
        </article>
        <script>\(hljsScript)</script>
        <script>hljs.highlightAll();</script>
        </body>
        </html>
        """
    }

    private static func loadResource(bundle: Bundle, name: String, ext: String) -> String {
        loadResourceOpt(bundle: bundle, name: name, ext: ext) ?? ""
    }
    private static func loadResourceOpt(bundle: Bundle, name: String, ext: String) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
}
