import AppKit
import WebKit

// Restyle grok.com so the window reads as a Mac app (Appearance → Style, DEC-073).
//
// grok.com paints from a small set of CSS custom properties: an ink color, a
// wash that tints every hover and fill, two surfaces, an accent, three font
// stacks, and a handful of sizes. Most of the Mac style is overrides for those
// properties. The rest are a few rules for the sidebar, menus, and switches,
// matched by id, role, and `data-` hook. Nothing matches a class name; they
// are hashed and change with every grok.com build.
//
// The properties are declared on `:root` and again on every `[data-theme]`
// wrapper inside the page, so each override names both. Light and dark come
// from `light-dark()`, which follows the `color-scheme` grok.com already sets,
// so no selector here has to know which theme is showing.
//
// Sidebar numbers come from Finder: rows 32pt tall and 10pt in from the
// edge, 13pt regular labels, 11pt semibold headers, glyphs in the accent
// color, and a gray fill with a semibold label on the selected row. Finder
// rows have no hover state.
extension WebViewStore {
    /// Color and type. Neutral grays for grok.com's warm ones, the system
    /// font for its own, and the accent color from System Settings.
    /// grok.com turns font smoothing off (`antialiased`), which draws the
    /// same font thinner than AppKit does; the last rule turns it back on.
    static let macTokenCSS = """
    html:root,html:root [data-theme]{
    --grok-base:light-dark(#262626,#dedede)!important;
    --grok-base-wash:light-dark(#000,#fff)!important;
    --grok-pane:light-dark(#fff,#2a2a2a)!important;
    --grok-chrome:light-dark(#fff,#1e1e1e)!important;
    --grok-bg-sidebar:light-dark(#e9eaebcc,#28282acc)!important;
    --grok-glass-fill:light-dark(#ffffffa3,#2a2a2aa8)!important;
    --grok-glass-fill-hover:light-dark(#ffffffbd,#2a2a2ac2)!important;
    --grok-glass-fill-active:light-dark(#ffffffc2,#2a2a2abd)!important;
    --grok-gray-1000:#fff!important;
    --grok-gray-150:#2c2c2c!important;
    --grok-accent:var(--grock-accent)!important;
    --grok-blue:var(--grock-accent)!important;
    --grok-bg-accent-primary-hover:color-mix(in srgb,var(--grock-accent) 88%,white)!important;
    --grok-bg-accent-primary-active:color-mix(in srgb,var(--grock-accent) 88%,black)!important;
    --grok-bg-primary:var(--grock-accent)!important;
    --grok-bg-primary-hover:color-mix(in srgb,var(--grock-accent) 90%,white)!important;
    --grok-bg-primary-active:color-mix(in srgb,var(--grock-accent) 88%,black)!important;
    --grok-bg-primary-disabled:color-mix(in srgb,var(--grock-accent) 35%,transparent)!important;
    --grok-text-on-primary:#fff!important;
    --grok-bg-text-selection:Highlight!important;
    --grok-border-primary:light-dark(#d1d1d1,#5c5c5c)!important;
    --grok-border-secondary:light-dark(#0000001a,#ffffff1a)!important;
    --grok-border-tertiary:light-dark(#0000000f,#ffffff0f)!important;
    --grok-border-secondary-translucent:color-mix(in srgb,light-dark(#000,#fff) var(--grok-alpha-border-secondary),transparent)!important;
    --grok-border-focus-primary:color-mix(in srgb,var(--grock-accent) 55%,transparent)!important;
    --grok-focus-ring-width:3px!important;
    --grok-elevation-raised:0 1px 2px light-dark(#0000000d,#0000002e),0 2px 8px light-dark(#0000000d,#0000002e)!important;
    --grok-elevation-outline-diffuse:0 0 0 1px light-dark(#00000012,#ffffff16),0 12px 32px light-dark(#00000008,#00000040)!important;
    --grok-elevation-menu:0 0 0 .5px light-dark(#00000026,#ffffff2e),0 8px 24px light-dark(#00000026,#00000080)!important;
    --grok-elevation-composer:0 0 0 .5px light-dark(#0000001f,#ffffff24),0 1px 3px light-dark(#0000000d,#0000004d)!important;
    --grok-elevation-overlay:0 4px 16px light-dark(#0000001a,#0006),0 1px 3px light-dark(#0000000f,#0000004d)!important;
    --grok-elevation-modal:0 12px 40px light-dark(#0000002e,#0000008c),0 2px 8px light-dark(#00000014,#00000059)!important;
    --grok-font-sans:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif!important;
    --grok-font-display:-apple-system,BlinkMacSystemFont,"SF Pro Display",system-ui,sans-serif!important;
    --grok-font-mono:ui-monospace,"SF Mono",Menlo,monospace!important;
    --grok-font-size-chrome:13px!important;
    --grok-font-size-section-headline:11px!important;
    --grok-font-weight-hint:400!important;
    --grok-font-weight-regular:400!important;
    --grok-font-weight-compact:400!important;
    --grok-font-weight-code:400!important;
    --grok-font-weight-display:500!important;
    --grok-font-weight-medium:500!important;
    --grok-font-weight-title-medium:500!important;
    --grok-font-weight-emphasized:600!important;
    --grok-font-weight-semibold:600!important;
    --grok-font-weight-title-small:600!important;
    --grok-font-weight-body-heading:600!important;
    --grok-font-weight-body-heading-strong:700!important;
    --grok-letter-spacing-chrome:0em!important;
    --grok-letter-spacing-body:0em!important;
    --grok-letter-spacing-section-headline:0em!important;
    --grok-letter-spacing-hint:0em!important;
    --font-sans:-apple-system,BlinkMacSystemFont,system-ui,sans-serif!important;
    --font-mono:ui-monospace,"SF Mono",Menlo,monospace!important;
    }
    html:root body{
    --warm-white:light-dark(0 0% 96%,0 0% 9%)!important;
    --warm-black:light-dark(0 0% 4%,0 0% 100%)!important;
    --surface-base:light-dark(#fff,#1e1e1e)!important;
    --surface-l1-hover:light-dark(#f0f0f0,#262626)!important;
    --surface-l2:light-dark(#ebebeb,#242424)!important;
    --surface-l2-active:light-dark(#e5e5e5,#2e2e2e)!important;
    --surface-elevated:light-dark(#fff,#2a2a2a)!important;
    --popover:light-dark(#f2f2f2,#2a2a2a)!important;
    --input-button-background:light-dark(#f4f4f4,#262626)!important;
    --input-button-background-hover:light-dark(#efefef,#2e2e2e)!important;
    --fg-primary:light-dark(#1f1f1f,#f2f2f2)!important;
    --fg-accent:var(--grock-accent)!important;
    --fg-accent-hover:color-mix(in srgb,var(--grock-accent) 88%,black)!important;
    }
    html:root body,html:root body *{-webkit-font-smoothing:auto!important;}
    """

    /// The sidebar as Finder draws one: a full-height column, mostly opaque
    /// gray over the glass the window keeps behind the WebView, so the
    /// wallpaper only tints it faintly. Rows sit 10pt in from each edge.
    static let macSidebarCSS = """
    html:root #app-sidebar{
    background-color:light-dark(#e9eaebcc,#28282acc)!important;
    border:0!important;border-inline-end:.5px solid light-dark(#00000021,#000000a6)!important;
    --grok-row-height:32px!important;
    --grok-radius-lg:6px!important;
    --grok-icon-size-xl:18px!important;
    --grok-icon-size-lg:18px!important;
    --grok-text-chrome:light-dark(#000,#fff)!important;
    --grok-text-tertiary:light-dark(#0000007a,#ffffff7a)!important;
    }
    html:root #app-sidebar > div:first-child{padding-inline:2px!important;box-sizing:border-box!important;}
    html:root #app-sidebar [data-icon-size-owner]{color:var(--grock-accent)!important;}
    html:root #app-sidebar button:has(> span > [data-sidebar-item-label]){padding-inline:9px!important;}
    html:root #app-sidebar button:has(> span > [data-sidebar-item-label]) > span{gap:9px!important;}
    html:root #app-sidebar [data-slot^="sidebar-scrolling"] :is(div,button,a):hover{background-color:transparent!important;}
    html:root #app-sidebar :is([data-selected="true"],button[aria-current="true"]),html:root #app-sidebar [data-slot^="sidebar-scrolling"] :is([data-selected="true"],button[aria-current="true"]):hover{background-color:light-dark(#00000017,#ffffff1f)!important;}
    html:root #app-sidebar [data-selected="true"] button[aria-current="true"],html:root #app-sidebar [data-slot^="sidebar-scrolling"] [data-selected="true"] button[aria-current="true"]:hover{background-color:transparent!important;}
    html:root #app-sidebar button[aria-current="true"] [data-sidebar-item-label]{font-weight:600!important;}
    html:root #app-sidebar div:has(> button[aria-controls][aria-keyshortcuts]){height:32px!important;padding:13px 8px 0 7px!important;}
    html:root #app-sidebar div:has(> button[aria-controls][aria-keyshortcuts]) span{font-weight:600!important;}
    html:root #app-sidebar button[aria-keyshortcuts="Meta+J"]{background-color:transparent!important;box-shadow:none!important;margin:0!important;}
    html:root #app-sidebar footer{--grok-font-size-body:13px!important;font-size:13px!important;}
    html:root #app-sidebar footer button[data-account-action]{background-color:transparent!important;box-shadow:none!important;}
    """

    /// Controls as AppKit draws them: switches and the highlighted menu item
    /// in the accent color, menus on a blurred backdrop, and an arrow cursor
    /// where a web page shows a hand.
    static let macControlCSS = """
    html:root [role="switch"][aria-checked="true"]{background-color:var(--grock-accent)!important;}
    html:root [role="menu"]{border-radius:13px!important;background-color:light-dark(#f6f6f6c7,#2a2a2ac7)!important;-webkit-backdrop-filter:blur(40px) saturate(180%)!important;backdrop-filter:blur(40px) saturate(180%)!important;}
    html:root [role="menu"] [role^="menuitem"]{border-radius:7px!important;outline:none!important;}
    html:root [role="menu"] [role^="menuitem"][data-highlighted]{background-color:var(--grock-accent)!important;color:#fff!important;}
    html:root [role="menu"] [role^="menuitem"][data-highlighted] *{color:#fff!important;}
    html:root :is(button,summary,label,[role="button"],[role^="menuitem"],[role="option"],[role="tab"],[role="switch"],#app-sidebar a){cursor:default!important;}
    """

    /// Keeps one stylesheet of overrides in the page for the chosen style.
    /// Idle unless the style changes or grok.com rebuilds `<head>`.
    static let themeScript: String = {
        let styles: [String: String] = [
            PageStyle.mac.rawValue: macTokenCSS + macSidebarCSS + macControlCSS
        ]
        let json = (try? JSONSerialization.data(withJSONObject: styles))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        (function () {
          var host = String(location.hostname || '').toLowerCase();
          if (host !== 'grok.com' && host.slice(-9) !== '.grok.com') return;
          if (window.__grockTheme) return;
          var STYLE_ID = 'grock-theme-style';
          var STYLES = \(json);
          var state = { style: '', accentLight: '#007aff', accentDark: '#0a84ff' };

          function hex(value, fallback) {
            return /^#[0-9a-f]{6}$/i.test(String(value || '')) ? value : fallback;
          }

          function merge(next) {
            if (!next || typeof next !== 'object') return;
            if (typeof next.style === 'string') state.style = next.style;
            state.accentLight = hex(next.accentLight, state.accentLight);
            state.accentDark = hex(next.accentDark, state.accentDark);
          }

          function sheet() {
            var css = Object.prototype.hasOwnProperty.call(STYLES, state.style) ? STYLES[state.style] : '';
            if (!css) return '';
            return 'html:root,html:root [data-theme]{--grock-accent:light-dark('
              + state.accentLight + ',' + state.accentDark + ')!important;}' + css;
          }

          function ensure() {
            var root = document.documentElement;
            if (!root) return;
            var css = sheet();
            var el = document.getElementById(STYLE_ID);
            if (!css) {
              if (el) el.remove();
              return;
            }
            if (!el) {
              el = document.createElement('style');
              el.id = STYLE_ID;
            }
            if (!el.isConnected) (document.head || root).appendChild(el);
            if (el.textContent !== css) el.textContent = css;
          }

          window.__grockTheme = {
            set: function (next) { merge(next); ensure(); },
            style: function () { return state.style; }
          };

          merge(window.__grockThemeConfig);
          ensure();
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', ensure);
          }
          // Hydration can replace <head> or drop a node it does not know.
          var watched = [];
          function watch(node) {
            if (!node || watched.indexOf(node) !== -1) return;
            watched.push(node);
            observer.observe(node, { childList: true });
          }
          var observer = new MutationObserver(function () {
            watch(document.head);
            if (state.style && !document.getElementById(STYLE_ID)) ensure();
          });
          watch(document.documentElement);
          watch(document.head);
        })();
        """
    }()

    /// The style as the page should see it when a document starts loading,
    /// so a themed page never paints in grok.com's own colors first.
    static func themeConfigScript(_ style: PageStyle = .current) -> String {
        "window.__grockThemeConfig = \(style.scriptConfig);"
    }

    /// The style or the system accent color changed. Later documents start
    /// from the new one, and the page showing now is restyled in place.
    func pageStyleDidChange() {
        Self.installUserScripts(on: webView.configuration.userContentController)
        applyPageStyle()
    }

    /// Push the current style into the page (live, no reload) and line the
    /// native window up with it.
    func applyPageStyle(_ style: PageStyle = .current) {
        let json = style.scriptConfig
        webView.evaluateJavaScript(
            "window.__grockThemeConfig = \(json); window.__grockTheme && window.__grockTheme.set(\(json));",
            completionHandler: nil
        )
        // WKWebView has no public switch for an unpainted background on macOS.
        // This key is the long-standing way to get one. If WebKit ever drops
        // it, the sidebar falls back to the window's plain backdrop.
        if webView.responds(to: NSSelectorFromString("_setDrawsBackground:")) {
            webView.setValue(style != .mac, forKey: "drawsBackground")
        }
        applyPageBackdrop()
    }
}
