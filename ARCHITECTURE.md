# How This Project Works (Beginner Guide)

If you've never built a macOS app or QuickLook plugin before, this explains everything from scratch.

---

## What is QuickLook?

QuickLook is the macOS feature that shows a preview when you select a file in Finder and press **Space**. It works for PDFs, images, text files, etc. out of the box.

By default, macOS shows `.md` files as raw plain text. This project makes QuickLook render them as styled HTML instead — with headings, code blocks, tables, and dark mode.

## How macOS Lets You Extend QuickLook

Apple's modern approach (macOS 12+) requires you to build a **host app** that contains a **QuickLook Preview Extension** inside it. You can't just ship the extension alone — macOS requires it to live inside an app bundle.

```
MarkdownQL.app/                    ← The host app (container)
└── Contents/
    ├── MacOS/MarkdownQL           ← App binary
    ├── Info.plist                 ← App metadata
    ├── Resources/                 ← Shared assets
    └── PlugIns/
        └── MarkdownQLPreview.appex/   ← The actual QuickLook extension
            └── Contents/
                ├── MacOS/MarkdownQLPreview  ← Extension binary
                ├── Info.plist               ← Extension metadata
                └── Resources/               ← Extension assets
```

When you press Space on a `.md` file, macOS finds the extension, launches it in a sandbox, and asks it to render a preview.

---

## Project Structure

```
markdown-quicklook/
├── AppSources/
│   ├── app/              ← Host app source code
│   │   ├── AppMain.swift       Swift code for the container app
│   │   ├── Info.plist          Metadata (name, version, file types)
│   │   └── app.entitlements    Permissions the app requests
│   └── ext/              ← QuickLook extension source code
│       ├── PreviewProvider.swift   The actual preview rendering logic
│       ├── Info.plist              Declares what file types we handle
│       └── ext.entitlements        Permissions the extension needs
├── Resources/
│   ├── preview.css       ← GitHub-style CSS for the rendered HTML
│   └── marked.min.js     ← JavaScript library that converts Markdown → HTML
├── Makefile              ← Build script
├── test/
│   └── sample.md         ← Test file for previewing
└── README.md
```

### Why `app/` and `ext/`?

- **`app/`** — The host app. It's a simple Markdown viewer window. macOS requires a host app to exist, but it doesn't need to do much. Ours lets you open and view `.md` files directly.
- **`ext/`** — The QuickLook extension. This is the important part. When you press Space on a `.md` file in Finder, macOS runs this code to generate the preview.

### Why `AppSources/` and `Resources/`?

- **`AppSources/`** — Swift source code that gets compiled into binaries.
- **`Resources/`** — Static files (CSS, JavaScript) that get bundled into the app without compilation. Both the app and extension use these.

---

## Key Files Explained

### Info.plist

A **property list** (XML file) that tells macOS about your app or extension. Think of it as a manifest or `package.json`. It declares:

- Bundle identifier (like a unique ID: `com.nat.MarkdownQL.preview`)
- What file types the extension handles (`net.daringfireball.markdown`)
- The main class to instantiate (`MarkdownQLPreview.PreviewViewController`)
- Minimum macOS version required

macOS reads this file to know *when* to invoke your extension.

### Entitlements (.entitlements)

Entitlements are **permissions** your app requests from macOS. Like Android permissions or iOS privacy prompts, but declared at build time.

Our extension requests:
- `app-sandbox: true` — Required. Extensions must run in a sandbox (restricted environment).
- `files.user-selected.read-only` — Can read files the user selects.
- `network.client` — Can make outgoing network connections (needed by WebKit internals).
- `cs.jit` — Can use Just-In-Time compilation (needed for JavaScript execution in WKWebView).

Without the correct entitlements, the extension silently fails.

### PreviewProvider.swift

This is the core logic. It:
1. Reads the `.md` file from disk
2. Builds an HTML page with the CSS and marked.js embedded inline
3. Loads that HTML into a `WKWebView` (an embedded web browser)
4. marked.js converts the Markdown to HTML client-side
5. macOS displays the WKWebView as the QuickLook preview

### AppMain.swift

The host app. A minimal macOS window app that can also open and render `.md` files. macOS requires a host app to exist for the extension to be registered, but users primarily interact with the extension via Finder's Space key.

---

## How the Makefile Works

Most macOS apps are built with Xcode (Apple's IDE), which generates a `.xcodeproj` with hundreds of config files. This project skips all that and compiles directly with `swiftc` (the Swift compiler) from the command line.

### Build steps explained:

```makefile
# 1. Download marked.js (Markdown→HTML library) if not present
Resources/marked.min.js:
    curl -fsSL "$(MARKED_URL)" -o Resources/marked.min.js

# 2. Compile the extension Swift code into a binary
swiftc -sdk $(SDK) -target arm64-apple-macosx12.0 \
    -framework QuickLookUI -framework WebKit ...  \
    AppSources/ext/PreviewProvider.swift \
    -o build/.../MarkdownQLPreview

# 3. Compile the host app Swift code into a binary
swiftc ... AppSources/app/AppMain.swift \
    -o build/.../MarkdownQL

# 4. Copy plists and resources into the correct bundle locations
cp AppSources/ext/Info.plist  ...appex/Contents/Info.plist
cp Resources/marked.min.js   ...appex/Contents/Resources/
cp Resources/preview.css     ...appex/Contents/Resources/

# 5. Code-sign everything (ad-hoc, no Apple Developer account needed)
codesign --force --sign - --entitlements ... MarkdownQLPreview.appex
codesign --force --sign - --entitlements ... MarkdownQL.app
```

### Why `-framework QuickLookUI -framework WebKit`?

These are Apple system libraries. `-framework` tells the compiler to link against them:
- **QuickLookUI** — Provides the `QLPreviewingController` protocol (the interface macOS calls)
- **WebKit** — Provides `WKWebView` (embedded browser for rendering HTML)
- **JavaScriptCore** — JavaScript engine (used by the host app for server-side rendering)

### Why `-Xlinker -e -Xlinker _NSExtensionMain`?

Extensions don't have a `main()` function. This tells the linker to use Apple's `NSExtensionMain` as the entry point — it's the system function that bootstraps extensions.

### Why `codesign --force --sign -`?

macOS requires all executables to be signed. `--sign -` means "ad-hoc sign" — a free, local-only signature without an Apple Developer account ($99/year). The tradeoff: users see a security warning on first launch.

---

## How QuickLook Finds Your Extension

1. You run `make install` → copies `MarkdownQL.app` to `~/Applications/`
2. You open the app once → macOS registers it with **LaunchServices**
3. LaunchServices sees the embedded `.appex` and registers it with **pluginkit**
4. Next time you press Space on a `.md` file, macOS asks pluginkit "who handles `net.daringfireball.markdown`?"
5. pluginkit returns your extension → macOS launches it → preview appears

You can verify registration with:
```bash
pluginkit -mDvvv -p com.apple.quicklook.preview | grep MarkdownQL
```

---

## Common Gotchas

| Problem | Cause | Fix |
|---------|-------|-----|
| Extension doesn't register | App was never opened | `open ~/Applications/MarkdownQL.app` |
| Preview shows plain text | Another extension is winning | `pluginkit -e ignore -i <other-bundle-id>` |
| Preview is blank | Sandbox blocking WKWebView | Ensure `cs.jit` entitlement is set |
| Changes don't take effect | Old extension cached | `killall quicklookd; qlmanage -r` |
| Security warning on launch | Ad-hoc signed | Right-click → Open → "Open Anyway" |
