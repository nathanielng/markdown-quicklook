import Cocoa
import WebKit
import JavaScriptCore

// MARK: - App entry point

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - Theme

enum Theme: Int, CaseIterable {
    case githubLight = 0
    case githubDark = 1
    case a11yLight = 2
    case a11yDark = 3
    case solarizedLight = 4
    case solarizedDark = 5
    case nord = 6

    var displayName: String {
        switch self {
        case .githubLight:    return "GitHub Light"
        case .githubDark:     return "GitHub Dark"
        case .a11yLight:      return "a11y Light (AA)"
        case .a11yDark:       return "a11y Dark (AAA)"
        case .solarizedLight: return "Solarized Light"
        case .solarizedDark:  return "Solarized Dark"
        case .nord:           return "Nord"
        }
    }

    var filename: String {
        switch self {
        case .githubLight:    return "github-light"
        case .githubDark:     return "github-dark"
        case .a11yLight:      return "a11y-light"
        case .a11yDark:       return "a11y-dark"
        case .solarizedLight: return "solarized-light"
        case .solarizedDark:  return "solarized-dark"
        case .nord:           return "nord"
        }
    }

    var isAccessible: Bool {
        switch self {
        case .a11yLight, .a11yDark: return true
        default: return false
        }
    }

    static var current: Theme {
        get { Theme(rawValue: UserDefaults.standard.integer(forKey: "theme")) ?? .githubLight }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "theme") }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

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

    @objc func printDocument(_ sender: Any?) {
        if let wc = NSApp.keyWindow?.windowController as? MarkdownWindowController { wc.printContent() }
    }

    @objc func saveAsHTML(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? MarkdownWindowController else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["html"]
        panel.nameFieldStringValue = wc.fileURL.deletingPathExtension().lastPathComponent + ".html"
        if panel.runModal() == .OK, let url = panel.url {
            let html = HTMLRenderer.shared.render(fileURL: wc.fileURL)
            try? html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

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
        fileMenu.addItem(NSMenuItem(title: "Save as HTML…", action: #selector(saveAsHTML(_:)), keyEquivalent: "S"))
        fileMenu.addItem(NSMenuItem(title: "Print…", action: #selector(printDocument(_:)), keyEquivalent: "p"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // View menu — theme picker
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
        // Accessible themes
        let accessLabel = NSMenuItem(title: "Accessible", action: nil, keyEquivalent: "")
        accessLabel.isEnabled = false
        themeMenu.addItem(accessLabel)
        for theme in Theme.allCases where theme.isAccessible {
            let item = NSMenuItem(title: "  \(theme.displayName)", action: #selector(changeTheme(_:)), keyEquivalent: "")
            item.tag = theme.rawValue
            themeMenu.addItem(item)
        }
        themeMenu.addItem(.separator())
        // Standard themes
        let stdLabel = NSMenuItem(title: "Standard", action: nil, keyEquivalent: "")
        stdLabel.isEnabled = false
        themeMenu.addItem(stdLabel)
        for theme in Theme.allCases where !theme.isAccessible {
            let item = NSMenuItem(title: "  \(theme.displayName)", action: #selector(changeTheme(_:)), keyEquivalent: "")
            item.tag = theme.rawValue
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        viewMenu.addItem(themeItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(NSMenuItem(title: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+"))
        viewMenu.addItem(NSMenuItem(title: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-"))
        viewMenu.addItem(NSMenuItem(title: "Actual Size", action: #selector(zoomReset(_:)), keyEquivalent: "0"))
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func changeTheme(_ sender: NSMenuItem) {
        guard let theme = Theme(rawValue: sender.tag) else { return }
        Theme.current = theme
        for wc in windowControllers { wc.reload() }
    }

    @objc func zoomIn(_ sender: Any?) {
        if let wc = NSApp.keyWindow?.windowController as? MarkdownWindowController { wc.zoom(by: 0.25) }
    }
    @objc func zoomOut(_ sender: Any?) {
        if let wc = NSApp.keyWindow?.windowController as? MarkdownWindowController { wc.zoom(by: -0.25) }
    }
    @objc func zoomReset(_ sender: Any?) {
        if let wc = NSApp.keyWindow?.windowController as? MarkdownWindowController { wc.setZoom(1.0) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(changeTheme(_:)) {
            menuItem.state = menuItem.tag == Theme.current.rawValue ? .on : .off
        }
        return true
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
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
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
        webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
    }

    func reload() {
        loadFile()
    }

    func zoom(by delta: CGFloat) {
        webView.magnification = max(0.25, min(5.0, webView.magnification + delta))
    }

    func setZoom(_ level: CGFloat) {
        webView.magnification = level
    }

    func printContent() {
        let info = NSPrintInfo.shared
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        let op = webView.printOperation(with: info)
        op.runModal(for: window!, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

// MARK: - HTML Renderer (shared between app and extension)

class HTMLRenderer {
    static let shared = HTMLRenderer()

    private let jsContext: JSContext?
    private let hljsScript: String

    private var css: String {
        let bundle = Bundle.main
        return HTMLRenderer.loadResourceOpt(bundle: bundle, name: Theme.current.filename, ext: "css")
            ?? HTMLRenderer.loadResource(bundle: bundle, name: "preview", ext: "css")
    }

    private init() {
        let bundle = Bundle.main
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
