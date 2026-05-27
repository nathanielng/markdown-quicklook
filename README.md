# MarkdownQuickLook

A macOS QuickLook plugin that renders `.md` Markdown files as styled HTML instead of raw text.

## Features

- Full GitHub Flavored Markdown (GFM) via [marked.js](https://marked.js.org/)
- GitHub-style CSS with automatic light/dark mode
- Tables, task lists, fenced code blocks, blockquotes, strikethrough
- No external network requests — everything is bundled

## Requirements

- macOS 12+ (arm64)
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```bash
make install
```

This compiles the plugin, ad-hoc signs it, copies it to `~/Library/QuickLook/`, and resets QuickLook.

## Approve the Plugin (required once)

macOS Gatekeeper blocks unsigned plugins. After installing, run:

```bash
make approve
# → runs: sudo spctl --add ~/Library/QuickLook/MarkdownQuickLook.qlgenerator
```

Or do it manually in System Settings → Privacy & Security → (scroll down) → Allow Anyway.

## Verify

Check registration:

```bash
qlmanage -m plugins 2>&1 | grep -i "markdown\|daring"
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

**If previews don't update after reinstalling:**

```bash
make approve   # re-approve after each rebuild
```

Or run:

```bash
sudo spctl --add ~/Library/QuickLook/MarkdownQuickLook.qlgenerator
killall quicklookd Finder
```

**If `make approve` fails with sudo error, run directly in your terminal** (not via Claude Code):

```bash
sudo spctl --add ~/Library/QuickLook/MarkdownQuickLook.qlgenerator
qlmanage -r
```

## Development

```bash
make clean build    # compile without installing
make test           # build and test preview with sample.md
```
