# Troubleshooting & Learnings

Everything we learned building a QuickLook extension without Xcode or a Developer ID certificate.

---

## Quick Diagnostic Commands

```bash
# Is the extension registered?
pluginkit -mDvvv -p com.apple.quicklook.preview | grep MarkdownQL

# What UTI does macOS assign to .md files?
mdls -name kMDItemContentType -name kMDItemContentTypeTree file.md

# Who else handles markdown previews?
pluginkit -mDvvv -p com.apple.quicklook.preview | grep -B2 -A10 "markdown\|Mindle"

# Disable a competing extension
pluginkit -e ignore -i <bundle-id>
# Re-enable it
pluginkit -e use -i <bundle-id>

# Reset QuickLook after changes
killall quicklookd; qlmanage -r

# Check extension logs
log show --predicate 'process == "MarkdownQLPreview"' --last 30s --style compact

# Check for sandbox denials
log show --predicate 'process == "kernel" AND eventMessage CONTAINS "deny"' --last 30s --style compact

# Verify code signature
codesign -dvvv ~/Applications/MarkdownQL.app/Contents/PlugIns/MarkdownQLPreview.appex
```

---

## Problem: Preview Shows Plain Text (Wrong Extension Wins)

**Symptom:** Pressing Space on a `.md` file shows raw text or another app's rendering.

**Cause:** Another QuickLook extension (e.g., Mindle) is registered for the same UTI and wins the conflict. macOS has no UI to choose between competing extensions. Properly signed extensions (Developer ID) always beat ad-hoc signed ones.

**Diagnosis:**
```bash
# Check what's actually running when you preview
log show --predicate 'eventMessage CONTAINS "sandbox"' --last 15s --style compact | grep -i "quicklook\|preview"
```

**Fix:**
```bash
pluginkit -e ignore -i local.fnp.mindle.quicklook   # or whatever bundle-id
killall quicklookd
```

---

## Problem: Extension Not Registered (pluginkit Shows Nothing)

**Symptom:** `pluginkit -m -i com.nat.MarkdownQL.preview` returns empty.

**Possible causes:**

1. **App never opened.** macOS registers extensions only after the host app launches at least once.
   ```bash
   open ~/Applications/MarkdownQL.app
   ```

2. **Sandbox disabled.** Extensions *must* have `com.apple.security.app-sandbox = true` to register. Without it, pluginkit silently ignores the extension — no error message.

3. **Wrong class name in Info.plist.** Must be module-qualified:
   ```xml
   <!-- ✗ Wrong -->
   <string>PreviewViewController</string>
   <!-- ✓ Correct -->
   <string>MarkdownQLPreview.PreviewViewController</string>
   ```

4. **Stale registration.** After reinstalling:
   ```bash
   killall quicklookd
   open ~/Applications/MarkdownQL.app
   pluginkit -mDvvv -p com.apple.quicklook.preview | grep MarkdownQL
   ```

---

## Problem: Preview is Blank (Extension Runs But Shows Nothing)

**Symptom:** Extension launches (visible in logs) but the preview window is empty.

**Cause:** WKWebView's web content subprocess crashes inside the sandbox. With ad-hoc signing, macOS doesn't trust the extension enough to let WKWebView's separate XPC process launch.

**Diagnosis:**
```bash
log show --predicate 'process == "MarkdownQLPreview" AND eventMessage CONTAINS "didTerminate"' --last 30s
# If you see: "WebPageProxy::dispatchProcessDidTerminate" → this is the problem
```

**Fix:** The extension needs `com.apple.security.cs.jit` in its entitlements:
```xml
<key>com.apple.security.cs.jit</key>
<true/>
```

This allows JIT compilation that WKWebView requires for JavaScript execution. Developer ID signed apps don't need this explicitly because macOS grants it automatically to trusted code.

---

## Problem: Host App Window is Blank

**Symptom:** The app opens but the markdown viewer window shows nothing.

**Cause:** Same as above — the host app was sandboxed, and WKWebView's subprocess can't launch with ad-hoc signing + sandbox.

**Fix:** The host app doesn't need sandboxing (only the extension does for pluginkit registration). Set:
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

---

## Problem: Markdown Renders as Raw Text (Partially or Fully)

**Symptom:** QuickLook shows unformatted text with visible `\`` escapes, raw JS code at the bottom, or content starting mid-file.

**Cause:** The markdown file contains a literal `</script>` tag (common in files with HTML examples). When the extension embeds markdown inside a `<script>` tag, the HTML parser sees `</script>` in the content and prematurely closes the script block. Everything after that point renders as raw text.

**How to verify:**
```bash
grep -i '</script>' problematic-file.md
```

**Fix (already applied):** The extension escapes `</script>` → `<\/script>` before embedding. The `\/` is valid in JS and prevents the HTML parser from matching the closing tag. If you see this issue, ensure `PreviewProvider.swift` includes:
```swift
.replacingOccurrences(of: "</script>", with: "<\\/script>", options: .caseInsensitive)
```

**Note:** This only affects the QuickLook extension (which embeds markdown in a JS template literal inside `<script>` tags). The host app uses `JSContext` for server-side rendering and is not affected.

---

## Problem: Changes Don't Take Effect After Rebuild

**Symptom:** You rebuild and reinstall but the old behavior persists.

**Fix:**
```bash
killall quicklookd
killall MarkdownQL 2>/dev/null
qlmanage -r
open ~/Applications/MarkdownQL.app   # re-register
```

macOS caches extension binaries aggressively. Killing `quicklookd` forces it to reload.

---

## Entitlements Reference

### Extension (`ext.entitlements`) — all required:

| Entitlement | Why |
|-------------|-----|
| `app-sandbox = true` | Required for pluginkit registration |
| `files.user-selected.read-only` | Read the file being previewed |
| `files.bookmarks.app-scope` | Access file bookmarks |
| `network.client` | WebKit internals need network stack |
| `cs.jit` | WKWebView JS execution with ad-hoc signing |

### Host app (`app.entitlements`):

| Entitlement | Why |
|-------------|-----|
| `app-sandbox = false` | Not needed; avoids WKWebView subprocess crash |

---

## Key Learnings

### WKWebView in Sandboxed Extensions

WKWebView runs JavaScript in a separate XPC subprocess (WebContent process). This subprocess needs to be trusted by macOS to launch. With ad-hoc signing:
- The sandbox blocks the subprocess from connecting to system services
- The web process terminates immediately after launch
- No error is shown — the preview is just blank

The `cs.jit` entitlement grants the JIT permission the subprocess needs. Properly signed apps (Developer ID) get this implicitly.

### Extension Priority / UTI Conflicts

macOS picks one extension per UTI with no user override. Priority factors:
1. Developer ID signed > ad-hoc signed
2. System apps > user apps
3. No documented tiebreaker beyond that

The only workaround is `pluginkit -e ignore -i <competing-bundle-id>`.

### Silent Failures

pluginkit gives almost no feedback when rejecting an extension. Common silent failures:
- Missing sandbox entitlement → not registered, no error
- Wrong principal class name → not registered, no error
- Missing UTI declaration → registered but never invoked

Always verify with `pluginkit -mDvvv` after changes.

### UTI Trust Without Notarization

Without app notarization, macOS may assign `.md` files `public.plain-text` instead of `net.daringfireball.markdown`. The extension declares support for both UTIs and filters by file extension in code:
```swift
let ext = url.pathExtension.lowercased()
guard ["md","markdown","mdown","mkd","mkdn"].contains(ext) else {
    handler(nil); return
}
```

### Legacy qlgenerator Approach is Dead

The old CFPlugin-based `.qlgenerator` approach (using `spctl --add` for approval) is fully removed in modern macOS. The only viable path is the App Extension model with a host app + embedded `.appex`.

### Async Rendering in QuickLook

QuickLook uses the completion handler call as a signal to capture the view. If you call it before WKWebView finishes loading, you get a blank capture. The fix is to defer the handler call to `WKNavigationDelegate.webView(_:didFinish:)`.

---

## Development History

This project went through several iterations:

1. **Legacy `.qlgenerator` (Obj-C CFPlugin)** — abandoned because `spctl --add` is removed on modern macOS
2. **Data-based `QLPreviewProvider`** — abandoned because its WebKit context doesn't execute JavaScript
3. **View-based `QLPreviewingController` + WKWebView** — works, but required solving sandbox/JIT issues
4. **Host app with WKWebView** — works after disabling sandbox on the app side

The archived legacy code is in the `archive/` directory (not tracked in git).
