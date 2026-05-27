# MarkdownQL Debugging Session — 2026-05-27

## Problem

QuickLook preview for `.md` files was not displaying rendered markdown — it showed nothing or fell back to plain text.

## Root Causes Found

### 1. Competing QuickLook Extension (Mindle)

**Mindle.app** (`local.fnp.mindle.quicklook`) was installed at `/Applications/Mindle.app` and registered for the same UTI (`net.daringfireball.markdown`). macOS was choosing Mindle over MarkdownQL because:

- Mindle is signed with a Developer ID certificate (proper code signing)
- MarkdownQL is ad-hoc signed — macOS gives lower priority to unsigned extensions
- There is no macOS UI to choose between competing QuickLook extensions for the same UTI

**Fix:** Disabled Mindle's extension:
```bash
pluginkit -e ignore -i local.fnp.mindle.quicklook
```

To re-enable later: `pluginkit -e use -i local.fnp.mindle.quicklook`

### 2. WKWebView Subprocess Crash in Sandbox

Once MarkdownQL's extension was selected, the preview was still blank. The WKWebView web content process was immediately terminating:

```
WebPageProxy::dispatchProcessDidTerminate: Not eagerly reloading the view because it is not currently visible
```

The sandbox was blocking the WKWebView's separate web content XPC process from launching properly. With ad-hoc signing (no team identifier), macOS doesn't grant the subprocess the trust it needs.

**Fix:** Added `com.apple.security.cs.jit` entitlement to `ext.entitlements`:
```xml
<key>com.apple.security.cs.jit</key>
<true/>
```

This allows JIT compilation that WKWebView requires for JavaScript execution (marked.js).

## Key Learnings

### QuickLook Extension Registration

- Extensions must be sandboxed (`com.apple.security.app-sandbox = true`) to register with `pluginkit`. Removing the sandbox entirely causes the extension to disappear from the registry.
- Opening the host app triggers LaunchServices registration of embedded extensions.
- After reinstalling, you may need to `open ~/Applications/MarkdownQL.app` to re-register.
- `pluginkit -mDvvv -p com.apple.quicklook.preview` lists all registered preview extensions.

### WKWebView in Sandboxed Extensions

- WKWebView runs JavaScript in a separate XPC subprocess (WebContent process).
- Ad-hoc signed sandboxed extensions don't automatically get permission for this subprocess to launch.
- The `com.apple.security.cs.jit` entitlement is required for WKWebView JS execution in sandboxed ad-hoc signed extensions.
- Developer ID signed apps (like Mindle) don't hit this issue because macOS trusts their subprocess spawning.

### Diagnosing QuickLook Issues

Useful commands:
```bash
# Check which extensions are registered
pluginkit -mDvvv -p com.apple.quicklook.preview

# Check what UTI macOS assigns to a file
mdls -name kMDItemContentType -name kMDItemContentTypeTree file.md

# Disable a competing extension
pluginkit -e ignore -i <bundle-id>

# Check system logs for extension process
log show --predicate 'process == "MarkdownQLPreview"' --last 30s --style compact

# Check for sandbox denials
log show --predicate 'process == "kernel" AND eventMessage CONTAINS "deny"' --last 30s

# Reset QuickLook
killall quicklookd; qlmanage -r
```

### Extension Priority Conflicts

- macOS has no user-facing UI to pick between competing QuickLook extensions for the same UTI.
- Properly signed (Developer ID) extensions win over ad-hoc signed ones.
- System-wide `/Applications/` doesn't necessarily beat `~/Applications/` — signing trust matters more.
- The only workaround is to disable the competing extension via `pluginkit -e ignore`.

## Final Working Entitlements

**ext.entitlements:**
```xml
<key>com.apple.security.app-sandbox</key>       <true/>
<key>com.apple.security.files.user-selected.read-only</key> <true/>
<key>com.apple.security.files.bookmarks.app-scope</key>     <true/>
<key>com.apple.security.network.client</key>    <true/>
<key>com.apple.security.cs.jit</key>            <true/>
```
