# MarkdownQL

A macOS QuickLook extension that renders `.md` and `.yaml` files with styled formatting instead of raw text. Press Space on any supported file in Finder to see a formatted preview.

## Features

- Full GitHub Flavored Markdown (GFM) via [marked.js](https://marked.js.org/)
- YAML syntax highlighting via [highlight.js](https://highlightjs.org/)
- GitHub-style CSS with automatic light/dark mode
- Tables, task lists, fenced code blocks, blockquotes, strikethrough
- Standalone viewer app with 4 themes (including WCAG AA/AAA accessible options)
- No external network requests — everything is bundled
- No Xcode.app required — builds from the command line

## Prerequisites

- **macOS 12+** (Apple Silicon / arm64)
- **Xcode Command Line Tools** — provides `swiftc`, `codesign`, and macOS SDK
  ```bash
  xcode-select --install
  ```
- **curl** — downloads marked.js on first build (pre-installed on macOS)
- **Internet connection** — only needed once for `make deps` to fetch marked.js

## Install

```bash
make install
```

This compiles the app + extension, ad-hoc signs them, and copies `MarkdownQL.app` to `~/Applications/`.

Then open the app once to register the QuickLook extension:

```bash
open ~/Applications/MarkdownQL.app
```

You may need to right-click → Open → "Open Anyway" on first launch (Gatekeeper warning for unsigned apps).

## Verify

Check the extension is registered:

```bash
pluginkit -mDvvv -p com.apple.quicklook.preview | grep MarkdownQL
```

Test a preview:

```bash
qlmanage -p some-file.md
```

Or select any `.md` file in Finder and press **Space**.

## Uninstall

```bash
make uninstall
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed diagnostics.

**Quick fixes:**

```bash
# If preview doesn't update after rebuild
killall quicklookd; qlmanage -r
open ~/Applications/MarkdownQL.app

# If another extension is handling .md files
pluginkit -mDvvv -p com.apple.quicklook.preview | grep -i markdown
pluginkit -e ignore -i <competing-bundle-id>
```

## Development

```bash
make clean build    # compile without installing
make test           # build and test preview with sample.md
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — How the project works (beginner-friendly)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Debugging guide and known issues
