import Foundation

// DOM adaptation stays separate from the native session and composer lifecycle.
extension WebViewStore {
    /// Hide grok.com chrome from Settings. Match visible labels, not hrefs.
    /// Sidebar is full labels or gone (DEC-034). Collapse rail is muted, not hidden.
    static let chromeScript = """
    (function () {
      function hostOk() {
        var host = String(location.hostname || '').toLowerCase();
        return host === 'grok.com' || host.slice(-9) === '.grok.com';
      }
      if (!hostOk()) {
        var handlers = window.webkit && window.webkit.messageHandlers;
        var bridge = handlers && handlers.grockSession;
        if (bridge) {
          try {
            bridge.postMessage({ more: false, share: false, panel: false, authenticated: false });
          } catch (err) {}
        }
        return;
      }
      if (window.__grockChrome) return;
      var ATTR = 'data-grock-hide';
      var STYLE_ID = 'grock-chrome-style';
      var config = {
        collapseSidebar: true,
        sidebarHidden: true,
        hideImagine: false,
        hideLibrary: false,
        hideAutomations: false,
        hideProjects: false,
        hidePlugins: false,
        hideGrokBot: true,
        hidePrivate: true,
        hideDictation: false,
        hideVoice: false
      };
      var ITEMS = [
        { key: 'hideImagine', text: 'Imagine', href: '/imagine', group: false },
        { key: 'hideLibrary', text: 'Library', href: '/library', group: false },
        { key: 'hideAutomations', text: 'Automations', href: '/automations', group: false },
        { key: 'hideProjects', text: 'Projects', href: '/project', group: true },
        { key: 'hideGrokBot', text: 'Bots', href: '', group: true },
        { key: 'hidePlugins', text: 'Plugins', href: '', group: false }
      ];
      var collapseTried = false;
      var collapseTimer = null;
      function merge(next) {
        if (!next || typeof next !== 'object') return;
        Object.keys(config).forEach(function (key) {
          if (Object.prototype.hasOwnProperty.call(next, key)) config[key] = !!next[key];
        });
      }

      function ensureStyle() {
        var el = document.getElementById(STYLE_ID);
        if (!el) {
          el = document.createElement('style');
          el.id = STYLE_ID;
        }
        // Moving an unchanged stylesheet still invalidates WebKit's styles.
        // Only reclaim cascade order when a later stylesheet actually exists;
        // scripts/meta nodes appended by the site do not affect precedence.
        var parent = document.head || document.documentElement;
        var needsMove = el.parentNode !== parent;
        for (var sibling = el.nextElementSibling; !needsMove && sibling; sibling = sibling.nextElementSibling) {
          if (sibling.matches('style, link[rel~="stylesheet"]')) needsMove = true;
        }
        if (needsMove) parent.appendChild(el);
        var css = '[' + ATTR + ']:not([' + ATTR + '="space"]){display:none!important;}'
          + '[' + ATTR + '="space"],[' + ATTR + '="space"] *'
          + '{visibility:hidden!important;pointer-events:none!important;}';
        css += titlebarInsetCSS();
        css += contentInsetCSS();
        css += composerBackdropCSS();
        css += sidebarChromeCSS();
        css += imagineShellInsetCSS();
        css += imagineStickyCSS();
        css += artifactStickyCSS();
        css += libraryFillCSS();
        css += commandMenuInsetCSS();
        css += pluginsDialogInsetCSS();
        css += promoHideCSS();
        css += sessionActionsCSS();
        if (!usesShellInset()) {
          css += titlebarFadeCSS();
          css += pageHeaderCSS();
        }
        if (config.sidebarHidden) {
          css += sidebarHideCSS();
        }
        if (config.hideDictation) {
          css += composerHideCSS('Dictation');
        }
        if (config.hideVoice) {
          css += composerHideCSS('Enter voice mode');
        }
        if (el.textContent !== css) el.textContent = css;
      }

      var CONTENT_INSET = 'data-grock-content-inset';
      var HOME_INSET = 'data-grock-home-inset';
      var TITLEBAR_SPACER_PX = 52;
      var pinnedInsetTarget = null;
      var pinnedInsetRoot = null;
      var pinnedSidebarHidden = null;

      // Imagine home stays on Chat inset / fade / header-hide, plus
      // surgical sticky CSS (data-grock-imagine-path). Canvas / session
      // (/imagine/agent) is a viewport split: Chat inset clips the
      // composer and canvas tools, so that shell uses imagineShellInsetCSS.
      // Library / Automations are the same class of page (own top chrome,
      // 100dvh shell). The old all-/imagine overlay special-case is gone.
      function isImaginePath() {
        var p = String(location.pathname || '').toLowerCase();
        return p === '/imagine' || p.indexOf('/imagine/') === 0 || p.indexOf('/imagine-') === 0;
      }
      function isImagineAgentPath() {
        var p = String(location.pathname || '').toLowerCase();
        return p === '/imagine/agent' || p.indexOf('/imagine/agent/') === 0;
      }
      function isLibraryPath() {
        var p = String(location.pathname || '').toLowerCase();
        return p === '/library' || p.indexOf('/library/') === 0
          || p === '/files' || p.indexOf('/files/') === 0;
      }
      function isAutomationsPath() {
        var p = String(location.pathname || '').toLowerCase();
        return p === '/automations' || p.indexOf('/automations/') === 0;
      }
      function isImaginePage() {
        return isImagineAgentPath();
      }
      function usesShellInset() {
        return isImaginePage() || isLibraryPath() || isAutomationsPath();
      }

      function titlebarInsetCSS() {
        // Overlay bar is 52pt. The sidebar rail is a fixed column, so CSS
        // padding there is correct. The main column is a viewport shell;
        // padding that node leaves a dead gutter. Mark the first descendant
        // that actually scrolls; contentInsetCSS() puts a spacer on it.
        return ':root{--grock-titlebar:52px;}'
          + 'div[data-sidebar="sidebar"]'
          + '{padding-top:var(--grock-titlebar)!important;box-sizing:border-box!important;}';
      }

      function contentInsetCSS() {
        // Spacer is a ::before flex item, not padding-top on the scroller.
        // WebKit leaves padding off scrollHeight for overflow flex boxes, so
        // grok.com's jump-to-bottom control thought it never quite arrived
        // and bounced. A real box at the start of the flow is in scrollHeight.
        return '[' + CONTENT_INSET + ']::before{content:\"\";display:block;width:100%;'
          + 'height:var(--grock-titlebar);min-height:var(--grock-titlebar);'
          + 'flex:0 0 var(--grock-titlebar);align-self:stretch;pointer-events:none;}'
          // New Chat home is flex-col justify-center. A ::before spacer is a
          // flex item, so it only shifts the cluster by half the bar. Padding
          // insets the flex box so heading + composer center below the bar.
          // Threads stay on the spacer (DEC-030 scrollHeight).
          + '[' + HOME_INSET + ']{padding-top:var(--grock-titlebar)!important;'
          + 'margin-top:0!important;box-sizing:border-box!important;}';
      }

      function artifactStickyCSS() {
        // Code/text containers stick a type + Copy toolbar at top:0 of the
        // thread scroller. Our titlebar overlay (and a nested overflow-scroll
        // we flatten) made that land mid-column. Scroll with the block.
        // Imagine home keeps its own sticky New project / composer offsets.
        return 'html:not([data-grock-imagine-path]) [' + CONTENT_INSET + '] .sticky.top-0,'
          + 'html:not([data-grock-imagine-path]) [' + CONTENT_INSET + '] .sticky'
          + '{position:relative!important;top:auto!important;}';
      }

      function composerBackdropCSS() {
        // grok.com fades the thread under the composer with bg-surface-base.
        // Our page fill is white/black (html/body are transparent over
        // AppearancePreference.pageBackdrop), so that fill showed as a gray
        // slab. Keep their blur/mask; drop the fill.
        return 'html:not([data-grock-imagine]) .chat-input-backdrop'
          + '{background-color:transparent!important;}';
      }

      function imagineStickyCSS() {
        // Imagine home: New project is sticky top-0 in an h-16 bar; the
        // composer is sticky at 76px (that bar plus a gap). Native titlebar
        // overlays the scrollport, so both would stick under it. Offset by
        // the bar. Composer hero paints bg-surface-base (beige); match the
        // overlay page fill instead.
        // Masonry lives in an overflow scroller (composited). Chat's
        // #grock-titlebar-fade is a sibling and sits under that layer, and
        // its gradient is already see-through in the bar. Stick the inset
        // spacer in the scroller as an opaque mask so tiles cannot paint
        // through the titlebar.
        // Agent / session uses data-grock-imagine + shell shift instead.
        // Do not also offset sticky chrome there (double inset).
        var root = 'html[data-grock-imagine-path]:not([data-grock-imagine]) #grok-content-area';
        var mask = root + ' [' + CONTENT_INSET + ']::before,'
          + root + ' [' + HOME_INSET + ']::before';
        return root + ' .sticky.top-0.z-30.h-16'
          + '{top:var(--grock-titlebar)!important;}'
          + root + ' [data-composer-hero].sticky'
          + '{top:calc(76px + var(--grock-titlebar))!important;}'
          + root + ' [data-composer-hero] .bg-surface-base'
          + '{background-color:#fff!important;}'
          + root + ' [data-composer-hero] [class*="from-surface-base"]'
          + '{background-image:linear-gradient(to bottom,#fff,transparent)!important;}'
          + mask
          + '{position:sticky;top:0;z-index:50;background-color:#fff;}'
          + 'html[data-grock-imagine-path] #grock-titlebar-fade{display:none!important;}'
          + '@media (prefers-color-scheme: dark){'
          + root + ' [data-composer-hero] .bg-surface-base'
          + '{background-color:#000!important;}'
          + root + ' [data-composer-hero] [class*="from-surface-base"]'
          + '{background-image:linear-gradient(to bottom,#000,transparent)!important;}'
          + mask
          + '{background-color:#000;}}';
      }

      function imagineShellInsetCSS() {
        // Imagine canvas / session. Shifting `top` without shrinking leaves a
        // 100dvh split hanging 52px below the window (composer, zoom, tools).
        // Size the shell to the band under the titlebar. Viewport-tall
        // children (h-dvh / h-screen) must follow the parent, not 100dvh.
        var line = '1px solid color-mix(in srgb, CanvasText 12%, transparent)';
        var vhKids = 'html[data-grock-shell-inset] #grok-content-area [data-grock-imagine-vh],'
          + 'html[data-grock-shell-inset] #grok-content-area .h-dvh,'
          + 'html[data-grock-shell-inset] #grok-content-area .h-screen,'
          + 'html[data-grock-shell-inset] #grok-content-area .h-svh,'
          + 'html[data-grock-shell-inset] #grok-content-area .h-lvh,'
          + 'html[data-grock-shell-inset] #grok-content-area .min-h-dvh,'
          + 'html[data-grock-shell-inset] #grok-content-area .min-h-screen';
        return 'html[data-grock-shell-inset] #grok-content-area{'
          + 'box-sizing:border-box!important;min-height:0!important;'
          + 'max-height:calc(100dvh - var(--grock-titlebar))!important;overflow:hidden!important;}'
          + 'html[data-grock-shell-inset] #grok-content-area[data-grock-imagine-inset="pad"]{'
          + 'margin-top:var(--grock-titlebar)!important;'
          + 'height:calc(100dvh - var(--grock-titlebar))!important;}'
          + 'html[data-grock-shell-inset] #grok-content-area[data-grock-imagine-inset="shift"]{'
          + 'top:var(--grock-titlebar)!important;bottom:auto!important;'
          + 'height:calc(100dvh - var(--grock-titlebar))!important;}'
          // Library / Automations sit fully below the bar; no hairline.
          // Imagine agent still gets a clip-edge line (content can meet the bar).
          + 'html[data-grock-imagine] #grok-content-area[data-grock-imagine-inset="pad"],'
          + 'html[data-grock-imagine] #grok-content-area[data-grock-imagine-inset="shift"]{'
          + 'border-top:' + line + '!important;}'
          + vhKids
          + '{height:100%!important;max-height:100%!important;min-height:0!important;}';
      }

      function libraryFillCSS() {
        // Library / Automations paint bg-surface-base (beige). Chat home and
        // the overlay page fill are white/black. Sticky page-nav fade is
        // from-surface-base; retint it so scrolled cards wash out in white.
        // Do not run this on Imagine (data-grock-imagine): the canvas already
        // matches.
        var root = 'html[data-grock-shell-inset]:not([data-grock-imagine]) #grok-content-area';
        return root + ',' + root + ' .bg-surface-base'
          + '{background-color:#fff!important;}'
          + 'html[data-grock-shell-inset]:not([data-grock-imagine]) #grok-content-area [class*="from-surface-base"]'
          + '{background-image:linear-gradient(to bottom,#fff,transparent)!important;}'
          + '@media (prefers-color-scheme: dark){'
          + root + ',' + root + ' .bg-surface-base'
          + '{background-color:#000!important;}'
          + 'html[data-grock-shell-inset]:not([data-grock-imagine]) #grok-content-area [class*="from-surface-base"]'
          + '{background-image:linear-gradient(to bottom,#000,transparent)!important;}}';
      }

      function commandMenuInsetCSS() {
        // Search is grok.com's command menu everywhere (Chats / Media).
        // Centered fixed dialog (`top:50%` + `translateY(-50%)`). The list
        // is 80dvh, then header (h-14) and footer (h-12) stack on it, so
        // the card is taller than the viewport and sits under the overlay
        // titlebar. 32px is 16px air below the bar plus 16px from the
        // bottom once max-height binds. 136px is that plus header and footer.
        // grok.com's command variant now anchors it at top-[18vh] with
        // translate-y-0 and max-h-[72vh], which clears the bar at the 520pt
        // minimum window. Shifting that one by half the viewport put it
        // half off-screen, so only the centered form moves.
        var dialog = '[role="dialog"]:has([cmdk-root],[cmdk-list],[cmdk-input]):not(.translate-y-0)';
        return dialog
          + '{top:calc(50% + (var(--grock-titlebar) / 2))!important;'
          + 'max-height:calc(100dvh - var(--grock-titlebar) - 32px)!important;'
          + 'overflow:hidden!important;box-sizing:border-box!important;}'
          + dialog + ' [cmdk-list],'
          + dialog + ' [cmdk-list-sizer]>*'
          + '{max-height:calc(100dvh - var(--grock-titlebar) - 136px)!important;}';
      }

      function promoHideCSS() {
        // First-paint net so campaign cards never draw. JS markPromos is the
        // precise pass. The named Build Mode announcement is a nonmodal
        // popover; hide its wrapper too so its arrow cannot remain visible.
        // The New Chat subscription card rotates its title, but its See plans
        // link always carries grok.com's source tag for that one card.
        return 'div.w-full.flex.justify-center.mt-2.px-2.cursor-pointer:has(button)'
          + ':not([role="dialog"]):not(form){display:none!important;}'
          + 'div.fixed.z-50:has(button[aria-label="Dismiss"])'
          + ':not([role="dialog"]):not(form){display:none!important;}'
          + '[data-radix-popper-content-wrapper]:has(> [role="dialog"]'
          + '[aria-label="Introducing Build Mode"]:not([aria-modal="true"]))'
          + '{display:none!important;}'
          + ':has(> a[href*="src=grok_web_new_chat_card"])'
          + ':not([role="dialog"]):not(form){display:none!important;}';
      }

      function pluginsDialogInsetCSS() {
        // Plugins is grok.com's connectors/skills modal, same centered-fixed
        // trap as Search (DEC-038). Same modal on every page. Marked in JS
        // so we do not shift every dialog.
        return '[data-grock-plugins-dialog]{'
          + 'top:calc(50% + (var(--grock-titlebar) / 2))!important;'
          + 'max-height:calc(100dvh - var(--grock-titlebar) - 32px)!important;'
          + 'overflow:auto!important;box-sizing:border-box!important;}'
          + '[data-grock-plugins-overlay]{'
          + 'padding-top:var(--grock-titlebar)!important;box-sizing:border-box!important;}';
      }

      function looksLikePluginsDialog(el) {
        if (!el || el.querySelector('[cmdk-root],[cmdk-list],[cmdk-input]')) return false;
        var text = String(el.textContent || '');
        if (text.indexOf('Connectors') === -1) return false;
        return text.indexOf('Skills') !== -1 || text.indexOf('New Connector') !== -1;
      }

      function markPluginsDialog() {
        var nodes = document.querySelectorAll('[role="dialog"]');
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (!looksLikePluginsDialog(el)) {
            if (el.hasAttribute('data-grock-plugins-dialog')) {
              el.removeAttribute('data-grock-plugins-dialog');
            }
            continue;
          }
          if (!el.hasAttribute('data-grock-plugins-dialog')) {
            el.setAttribute('data-grock-plugins-dialog', '1');
          }
          var ds = window.getComputedStyle(el);
          if (ds && (ds.position === 'fixed' || ds.position === 'absolute')) continue;
          var parent = el.parentElement;
          if (!parent) continue;
          var s = window.getComputedStyle(parent);
          var box = parent.getBoundingClientRect();
          if (s && (s.position === 'fixed' || s.position === 'absolute')
              && box.height >= window.innerHeight - 8) {
            if (!parent.hasAttribute('data-grock-plugins-overlay')) {
              parent.setAttribute('data-grock-plugins-overlay', '1');
            }
          }
        }
      }

      function clearImagineViewportHeights() {
        var nodes = document.querySelectorAll('[data-grock-imagine-vh]');
        for (var i = 0; i < nodes.length; i++) {
          nodes[i].removeAttribute('data-grock-imagine-vh');
        }
      }

      function markImagineViewportHeights(root) {
        if (!root) {
          clearImagineViewportHeights();
          return;
        }
        var limit = window.innerHeight - 4;
        function walk(el, depth) {
          if (!el || depth > 5) return;
          var kids = el.children;
          for (var i = 0; i < kids.length; i++) {
            var c = kids[i];
            if (c.offsetHeight >= limit) {
              if (!c.hasAttribute('data-grock-imagine-vh')) {
                c.setAttribute('data-grock-imagine-vh', '1');
              }
              walk(c, depth + 1);
            } else if (c.hasAttribute('data-grock-imagine-vh')) {
              c.removeAttribute('data-grock-imagine-vh');
            }
          }
        }
        walk(root, 0);
      }

      function restoreImagineShellInline(el) {
        if (!el) return;
        el.removeAttribute('data-grock-imagine-inset');
        el.style.removeProperty('top');
        el.style.removeProperty('height');
        el.style.removeProperty('max-height');
        el.style.removeProperty('min-height');
        el.style.removeProperty('margin-top');
        el.style.removeProperty('box-sizing');
      }

      function applyImagineShellInset() {
        var el = document.getElementById('grok-content-area');
        if (!el) return;
        if (!usesShellInset()) {
          restoreImagineShellInline(el);
          clearImagineViewportHeights();
          return;
        }
        var pos = window.getComputedStyle(el).position;
        var mode = (pos === 'fixed' || pos === 'absolute') ? 'shift' : 'pad';
        if (el.getAttribute('data-grock-imagine-inset') !== mode) {
          el.setAttribute('data-grock-imagine-inset', mode);
        }
        // Inline !important beats grok.com's later 100dvh / inset-0 sheets.
        var insetH = 'calc(100dvh - var(--grock-titlebar))';
        el.style.setProperty('height', insetH, 'important');
        el.style.setProperty('max-height', insetH, 'important');
        el.style.setProperty('min-height', '0', 'important');
        el.style.setProperty('box-sizing', 'border-box', 'important');
        if (mode === 'shift') {
          el.style.setProperty('top', 'var(--grock-titlebar)', 'important');
          el.style.removeProperty('margin-top');
        } else {
          el.style.setProperty('margin-top', 'var(--grock-titlebar)', 'important');
          el.style.removeProperty('top');
        }
        markImagineViewportHeights(el);
      }

      function titlebarFadeCSS() {
        // WKWebView's remote layer paints over sibling NSViews, so the fade
        // lives in the page (transparent native titlebar). Extra 28px matches
        // PanelGeometry.titlebarFadeExtra. The node is parented to the main
        // column so an open sidebar's rail is never under it.
        return '#grock-titlebar-fade{position:absolute;top:0;left:0;right:0;'
          + 'height:calc(var(--grock-titlebar) + 28px);pointer-events:none;z-index:100;'
          + 'background:linear-gradient(to bottom,#fff 0%,#fff 38%,rgba(255,255,255,.5) 68%,rgba(255,255,255,0) 100%);}'
          // Blur the content's own colors in dark mode. A black fill makes
          // gray code blocks and other surfaces read as a shadow under the bar.
          + '@media (prefers-color-scheme: dark){#grock-titlebar-fade{'
          + 'background:transparent;backdrop-filter:blur(12px);'
          + 'mask-image:linear-gradient(to bottom,#000 0%,#000 38%,rgba(0,0,0,.5) 68%,transparent 100%);}}';
      }

      function ensureTitlebarFade() {
        var root = contentRoot();
        var parent = root || document.body || document.documentElement;
        if (!parent) return;
        var el = document.getElementById('grock-titlebar-fade');
        if (!el) {
          el = document.createElement('div');
          el.id = 'grock-titlebar-fade';
          el.setAttribute('aria-hidden', 'true');
          parent.appendChild(el);
        } else if (el.parentElement !== parent) {
          parent.appendChild(el);
        }
        el.style.left = '';
        if (root && window.getComputedStyle(root).position === 'static') {
          root.style.position = 'relative';
        }
      }

      function contentRoot() {
        return document.getElementById('grok-content-area') || document.querySelector('main');
      }

      function firstFlowChild(el) {
        if (!el) return null;
        var kids = el.children;
        var fallback = null;
        var best = null;
        var bestScore = -1;
        for (var i = 0; i < kids.length; i++) {
          var c = kids[i];
          var tag = c.tagName;
          if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'LINK' || tag === 'NOSCRIPT' || tag === 'TEMPLATE') continue;
          if (c.id === 'grock-titlebar-fade') continue;
          var s = window.getComputedStyle(c);
          if (!s || s.display === 'none' || s.visibility === 'hidden') continue;
          if (parseFloat(s.opacity) === 0) continue;
          // Collapsed in-page nav (`@container/nav`, height 0) still has
          // scrollHeight from its absolute h-14 child. That beat the
          // session column (overflow visible, so no scroller bonus) and
          // the spacer landed on the empty wrapper: gutter under the
          // titlebar, composer hanging off the bottom.
          if (c.offsetHeight < 8) continue;
          var oy = s.overflowY;
          var scrolls = oy === 'auto' || oy === 'scroll' || oy === 'overlay';
          var fills = c.offsetHeight >= el.clientHeight * 0.5
            && c.offsetWidth >= el.clientWidth * 0.5;
          // Skip overlay chrome (page header, fade). Keep absolutely
          // positioned thread scrollers — grok.com parks the messages
          // list inset-0 overflow-auto when the sidebar is open, and
          // the walker used to stop on the clipping parent instead.
          if ((s.position === 'absolute' || s.position === 'fixed') && !scrolls && !fills) continue;
          if (!fallback) fallback = c;
          var score = 0;
          if (c.offsetWidth >= el.clientWidth * 0.5) score += 2;
          if (c.offsetHeight >= el.clientHeight * 0.5) score += 2;
          if (c.scrollHeight > c.clientHeight + 8) score += 3;
          if (scrolls) score += 4;
          if (score > bestScore) {
            bestScore = score;
            best = c;
          }
        }
        return best || fallback;
      }

      function isRealScroller(el) {
        if (!el) return false;
        var s = window.getComputedStyle(el);
        if (!s) return false;
        var oy = s.overflowY;
        return oy === 'auto' || oy === 'scroll' || oy === 'overlay';
      }

      function bestScrollingDescendant(root) {
        if (!root || !root.querySelectorAll) return null;
        var best = null;
        var bestScore = -1;
        var nodes = root.querySelectorAll('div, section, main, article');
        var limit = Math.min(nodes.length, 80);
        for (var i = 0; i < limit; i++) {
          var c = nodes[i];
          if (c.id === 'grock-titlebar-fade') continue;
          if (isPromptLike(c)) continue;
          if (!isRealScroller(c)) continue;
          var s = window.getComputedStyle(c);
          if (!s || s.display === 'none' || s.visibility === 'hidden') continue;
          if (c.offsetHeight < 80) continue;
          var score = 0;
          if (c.scrollHeight > c.clientHeight + 8) score += 3;
          if (c.offsetHeight >= 200) score += 2;
          if (c.offsetWidth >= 200) score += 1;
          if (score > bestScore) {
            bestScore = score;
            best = c;
          }
        }
        return best;
      }

      function scrollerFillsContentTop(el) {
        var root = contentRoot();
        if (!root || !el || el === root) return false;
        var rr = root.getBoundingClientRect();
        var r = el.getBoundingClientRect();
        if (r.height < rr.height * 0.5) return false;
        if (r.top > rr.top + 24) return false;
        return true;
      }

      function isViewportShell(el) {
        if (!el || el === document.documentElement || el === document.body) return true;
        if (el.id === 'grok-content-area') return true;
        // Flattened overflow-scroll is often the thread scroller. Walking
        // past it lands on an inner box that starts below the titlebar
        // when the sidebar is open. Stop here if it fills the column top.
        if (el.getAttribute('data-grock-edge-shell')) {
          return !scrollerFillsContentTop(el);
        }
        var s = window.getComputedStyle(el);
        if (!s) return true;
        var pos = s.position;
        if (pos === 'fixed' || pos === 'sticky') return true;
        var oy = s.overflowY;
        if (oy === 'auto' || oy === 'scroll' || oy === 'overlay') return false;
        var clips = oy === 'hidden' || oy === 'clip';
        var parent = el.parentElement;
        var parentH = parent ? parent.clientHeight : window.innerHeight;
        var parentW = parent ? parent.clientWidth : window.innerWidth;
        var h = el.offsetHeight;
        var w = el.offsetWidth;
        var fillH = parentH > 0 && h >= parentH - 2;
        var fillW = parentW > 0 && w >= parentW - 2;
        var heightToken = s.height;
        var widthToken = s.width;
        if (heightToken === '100%' || heightToken === '100vh' || heightToken === '100dvh' || heightToken === '100svh') fillH = true;
        if (widthToken === '100%' || widthToken === '100vw' || widthToken === '100dvw') fillW = true;
        if (clips && fillH) return true;
        // Our ::before spacer is in scrollHeight. Count it or the walk hops
        // every time the placeholder animation or a hover reflows.
        var spacer = 0;
        if (el.hasAttribute && el.hasAttribute(CONTENT_INSET)) spacer = TITLEBAR_SPACER_PX;
        else if (el.querySelector && el.querySelector('[' + CONTENT_INSET + ']')) spacer = TITLEBAR_SPACER_PX;
        if (fillH && fillW && el.scrollHeight <= h + 2 + spacer) return true;
        return false;
      }

      function isCenteredHomeColumn(el) {
        if (!el) return false;
        var s = window.getComputedStyle(el);
        if (!s) return false;
        if (s.display !== 'flex' && s.display !== 'inline-flex') return false;
        var dir = s.flexDirection;
        if (dir !== 'column' && dir !== 'column-reverse') return false;
        var jc = s.justifyContent;
        return jc === 'center' || jc === 'safe center';
      }

      function isPromptLike(el) {
        if (!el) return false;
        var tag = String(el.tagName || '').toUpperCase();
        if (tag === 'TEXTAREA' || tag === 'INPUT') return true;
        var editable = el.getAttribute && el.getAttribute('contenteditable');
        if (editable !== null && editable !== 'false') return true;
        if ((el.getAttribute && el.getAttribute('role')) === 'textbox') return true;
        if (!el.querySelector) return false;
        if (!el.querySelector('textarea, [contenteditable="true"], [contenteditable=""], [role="textbox"]')) {
          return false;
        }
        var h = el.offsetHeight;
        return h > 0 && h < 280;
      }

      function findContentInsetTarget() {
        var root = contentRoot();
        if (!root) return null;
        var el = root;
        var guard = 0;
        while (el && isViewportShell(el) && guard++ < 24) {
          var next = firstFlowChild(el);
          if (!next || next === el) break;
          if (isPromptLike(next)) {
            var scroller = bestScrollingDescendant(el);
            if (scroller && scroller !== el) return scroller;
            break;
          }
          el = next;
        }
        if (isPromptLike(el) && el.parentElement) el = el.parentElement;
        if (el && !isRealScroller(el)) {
          var inner = bestScrollingDescendant(el);
          if (inner) return inner;
        }
        return el;
      }

      function restoreContentInset(el) {
        if (!el) return;
        var pad = el.style.getPropertyValue('padding-top');
        if (pad && pad.indexOf('grock-titlebar') !== -1) {
          el.style.removeProperty('padding-top');
          el.style.removeProperty('box-sizing');
        }
        el.removeAttribute(CONTENT_INSET);
        el.removeAttribute('data-grock-pad-base');
        el.removeAttribute(HOME_INSET);
        if (el.hasAttribute('data-grock-scroll-restore')) {
          el.style.removeProperty('overflow-y');
          el.style.removeProperty('overflow-x');
          el.removeAttribute('data-grock-scroll-restore');
        }
      }

      function restoreAllContentInsets() {
        var nodes = document.querySelectorAll('[' + CONTENT_INSET + '], [' + HOME_INSET + ']');
        for (var i = 0; i < nodes.length; i++) restoreContentInset(nodes[i]);
      }

      function applyInsetMark(el) {
        if (!el) return;
        // New Chat home is flex-col justify-center and does not scroll.
        // A thread can keep those classes; padding-top there is a dead
        // gutter (DEC-030). Prefer the spacer on a real scroller.
        var home = isCenteredHomeColumn(el);
        if (home && isRealScroller(el)
            && el.scrollHeight > el.clientHeight + TITLEBAR_SPACER_PX + 40) {
          home = false;
        }
        if (home) {
          if (el.hasAttribute(CONTENT_INSET)) el.removeAttribute(CONTENT_INSET);
          if (!el.hasAttribute(HOME_INSET)) el.setAttribute(HOME_INSET, '1');
          if (el.hasAttribute('data-grock-scroll-restore')) {
            el.style.removeProperty('overflow-y');
            el.style.removeProperty('overflow-x');
            el.removeAttribute('data-grock-scroll-restore');
          }
        } else {
          if (el.hasAttribute(HOME_INSET)) el.removeAttribute(HOME_INSET);
          if (!el.hasAttribute(CONTENT_INSET)) el.setAttribute(CONTENT_INSET, '1');
          restoreScrollerOverflow(el);
        }
      }

      function restoreScrollerOverflow(el) {
        if (!el || !el.hasAttribute(CONTENT_INSET)) return;
        var s = window.getComputedStyle(el);
        var oy = s ? s.overflowY : '';
        if (oy !== 'hidden' && oy !== 'clip') return;
        el.style.setProperty('overflow-y', 'auto', 'important');
        el.style.setProperty('overflow-x', 'hidden', 'important');
        el.setAttribute('data-grock-scroll-restore', '1');
      }

      function clearImagineOverlayChrome() {
        restoreAllContentInsets();
        var fade = document.getElementById('grock-titlebar-fade');
        if (fade && fade.parentNode) fade.parentNode.removeChild(fade);
      }

      function insetTargetIsStable(el) {
        if (!el || !el.isConnected) return false;
        if (el.offsetHeight < 8) return false;
        if (el.id === 'grok-content-area' || (el.tagName && el.tagName.toUpperCase() === 'MAIN')) {
          var inner = firstFlowChild(el);
          if (!inner || inner === el) return false;
        }
        if (isRealScroller(el)) return true;
        if (!isViewportShell(el)) return true;
        if (bestScrollingDescendant(el)) return false;
        var next = firstFlowChild(el);
        if (!next || next === el || isPromptLike(next)) return true;
        return false;
      }

      function applyContentInset() {
        if (usesShellInset()) {
          restoreAllContentInsets();
          pinnedInsetTarget = null;
          pinnedInsetRoot = null;
          pinnedSidebarHidden = null;
          return false;
        }
        var root = contentRoot();
        if (!root) return false;
        if (pinnedSidebarHidden !== config.sidebarHidden) {
          pinnedInsetTarget = null;
          pinnedInsetRoot = null;
          pinnedSidebarHidden = config.sidebarHidden;
        }
        if (pinnedInsetRoot !== root) {
          pinnedInsetTarget = null;
          pinnedInsetRoot = root;
        }
        var wasPinned = pinnedInsetTarget;
        if (pinnedInsetTarget && insetTargetIsStable(pinnedInsetTarget)) {
          applyInsetMark(pinnedInsetTarget);
          return false;
        }
        var target = findContentInsetTarget();
        var nodes = document.querySelectorAll('[' + CONTENT_INSET + '], [' + HOME_INSET + ']');
        for (var i = 0; i < nodes.length; i++) {
          if (nodes[i] !== target) restoreContentInset(nodes[i]);
        }
        if (!target) {
          pinnedInsetTarget = null;
          return false;
        }
        var pad = target.style.getPropertyValue('padding-top');
        if (pad && pad.indexOf('grock-titlebar') !== -1) {
          target.style.removeProperty('padding-top');
          target.style.removeProperty('box-sizing');
        }
        if (target.hasAttribute('data-grock-pad-base')) {
          target.removeAttribute('data-grock-pad-base');
        }
        applyInsetMark(target);
        if (insetTargetIsStable(target)) {
          pinnedInsetTarget = target;
          return wasPinned !== target;
        }
        pinnedInsetTarget = null;
        return true;
      }

      function sidebarChromeCSS() {
        // Titlebar owns show/hide. Collapse the header slot, not just hide it.
        // The trailing hover rail still collapses grok.com to icons. Do not
        // display:none it by pixel class (those tokens churn). Mute pointer
        // events and kill the hover hairline instead (DEC-034).
        return '[data-sidebar="trigger"],[data-sidebar="header"]'
          + '{display:none!important;height:0!important;min-height:0!important;padding:0!important;margin:0!important;overflow:hidden!important;}'
          + '[data-sidebar="rail"],[data-sidebar="resize-handle"],'
          + '[data-slot="sidebar-rail"],[data-slot="sidebar-resize-handle"],[data-grock-rail],'
          + '[data-slot="sidebar"] [class*="absolute"][class*="h-full"][class*="cursor-pointer"],'
          + '[data-sidebar="sidebar"] [class*="absolute"][class*="h-full"][class*="cursor-pointer"],'
          + '[data-collapsible][data-side] [class*="absolute"][class*="h-full"][class*="cursor-pointer"]'
          + '{pointer-events:none!important;cursor:default!important;}'
          + '[data-sidebar="rail"]::after,[data-sidebar="resize-handle"]::after,'
          + '[data-slot="sidebar-rail"]::after,[data-slot="sidebar-resize-handle"]::after,[data-grock-rail]::after,'
          + '[data-slot="sidebar"] [class*="absolute"][class*="h-full"][class*="cursor-pointer"]::after,'
          + '[data-sidebar="sidebar"] [class*="absolute"][class*="h-full"][class*="cursor-pointer"]::after,'
          + '[data-collapsible][data-side] [class*="absolute"][class*="h-full"][class*="cursor-pointer"]::after'
          + '{background:transparent!important;background-color:transparent!important;opacity:0!important;}';
      }

      var PAGE_TOP_BAR_SELECTOR = '.absolute.top-0.z-10.h-16,'
        + '.absolute.top-0.z-10.h-14,'
        + '.absolute.inset-x-0.top-0.h-16,'
        + '.absolute.inset-x-0.top-0.h-14,'
        + '.absolute.inset-x-0.top-0.z-10';

      function pageHeaderCSS() {
        // grok.com restyled the in-page top bar h-16 → h-14 (absolute inset-x-0).
        // Native titlebar owns that band. Hide the bar when Grok Bot and Private
        // are both hidden (the defaults), unless it contains the logged-out
        // Sign in control. Keep its layout space; otherwise shift it below
        // the titlebar with its controls visible.
        // Do not match .sticky.top-0: code/text container toolbars use that
        // and would hide or stick 52px too low.
        var bar = '#grok-content-area .absolute.top-0.z-10.h-16,'
          + '#grok-content-area .absolute.top-0.z-10.h-14,'
          + '#grok-content-area .absolute.inset-x-0.top-0.z-10';
        return bar + '{top:var(--grock-titlebar)!important;}'
          + 'html[data-grock-page-header-hidden] #grok-content-area .absolute.top-0.z-10.h-16,'
          + 'html[data-grock-page-header-hidden] #grok-content-area .absolute.top-0.z-10.h-14,'
          + 'html[data-grock-page-header-hidden] #grok-content-area .absolute.inset-x-0.top-0.z-10'
          + '{visibility:hidden!important;pointer-events:none!important;}'
          + '#grok-content-area [class*="from-surface-base"][class*="bg-gradient-to-b"]{display:none!important;}';
      }

      function sessionActionsCSS() {
        // Conversation More / Share / panel cluster. Native titlebar owns
        // those (DEC-055). Nodes stay so click-through still works.
        return '[data-grock-session-cluster],[data-grock-session-panel]{display:none!important;}'
          + 'html:not([data-grock-shell-inset]) [data-grock-right-panel]'
          + '{top:var(--grock-titlebar)!important;height:calc(100% - var(--grock-titlebar))!important;}'
          + 'html:not([data-grock-shell-inset]) [data-grock-panel-controls]'
          + '{top:calc(var(--grock-titlebar) + 15px)!important;}'
          + 'html[data-grock-picking-menu] [role="menu"],'
          + 'html[data-grock-picking-menu] [data-radix-popper-content-wrapper],'
          + 'html[data-grock-picking-menu] [data-slot="dropdown-menu-content"]'
          + '{opacity:0!important;}'
          + '[data-grock-project-popover]{position:fixed!important;top:calc(var(--grock-titlebar) + 8px)!important;'
          + 'right:12px!important;left:auto!important;transform:none!important;max-height:calc(100vh - var(--grock-titlebar) - 20px)!important;}'
          + '[data-grock-project-source]{opacity:0!important;pointer-events:none!important;}';
      }

      function sidebarHideCSS() {
        // grok.com sets --sidebar-width inline on .group/sidebar-wrapper.
        // Collapsed rail uses --sidebar-width-icon (~3.5rem). Zero both.
        return 'html[data-grock-sidebar-hidden] [style*="--sidebar-width"],'
          + 'html[data-grock-sidebar-hidden] .group\\/sidebar-wrapper'
          + '{--sidebar-width:0px!important;--sidebar-width-icon:0px!important;}'
          // MAIN's other siblings include the right panel and its spacer.
          // Only the identified sidebar belongs to this hide rule.
          + 'html[data-grock-sidebar-hidden] [data-slot="sidebar"],'
          + 'html[data-grock-sidebar-hidden] [data-slot="sidebar-gap"],'
          + 'html[data-grock-sidebar-hidden] [data-slot="sidebar-container"],'
          + 'html[data-grock-sidebar-hidden] [data-collapsible][data-side],'
          + 'html[data-grock-sidebar-hidden] [data-sidebar="sidebar"],'
          + 'html[data-grock-sidebar-hidden] [data-sidebar="gap"],'
          + 'html[data-grock-sidebar-hidden] [data-sidebar="rail"],'
          + 'html[data-grock-sidebar-hidden] [data-sidebar="resize-handle"],'
          + 'html[data-grock-sidebar-hidden] [data-sidebar="footer"]'
          + '{display:none!important;width:0!important;min-width:0!important;overflow:hidden!important;border:none!important;}';
      }

      function composerHideCSS(ariaPrefix) {
        var btn = 'button[aria-label^="' + ariaPrefix + '"]';
        return btn + '{display:none!important;}'
          + 'div.h-10.w-10:has(' + btn + '){display:none!important;}'
          + 'div:has(> div.h-10.w-10:has(' + btn + ')):not(:has([data-query-bar-mode-select])){display:none!important;}';
      }

      function norm(value) {
        return String(value || '').replace(/\\s+/g, ' ').trim();
      }

      function pathOf(el) {
        var href = el.getAttribute('href');
        if (!href) return '';
        try { return new URL(href, location.href).pathname; } catch (err) { return href; }
      }

      function matchesItem(el, item) {
        var aria = norm(el.getAttribute('aria-label'));
        if (item.group && /[\\-\\u2013\\u2014]\\s*toggle$/i.test(aria)) return false;
        if (aria === item.text) return true;
        var title = norm(el.getAttribute('title'));
        if (title === item.text) return true;
        var span = el.querySelector('span.whitespace-nowrap');
        var text = span ? norm(span.textContent) : '';
        if (!text) {
          var own = '';
          for (var n = el.firstChild; n; n = n.nextSibling) {
            if (n.nodeType === 3) own += n.textContent;
          }
          text = norm(own);
        }
        if (text === item.text) return true;
        var all = norm(el.textContent);
        if (all === item.text) return true;
        // Section headers (Projects) often have a chevron and no href.
        if (item.group && all.indexOf(item.text) === 0 && all.length <= item.text.length + 8) {
          return true;
        }
        var path = pathOf(el);
        if (item.href && path === item.href) return true;
        // Prefix match is for leaf items (Imagine /imagine/post). Do not
        // treat /project/abc as the Projects header or we hide Chats too.
        if (item.href && !item.group && path.indexOf(item.href + '/') === 0) return true;
        if (item.key === 'hideLibrary' && (path === '/files' || path.indexOf('/files/') === 0)) return true;
        return false;
      }

      function mark(el, preserveSpace) {
        if (el && !el.getAttribute(ATTR)) el.setAttribute(ATTR, preserveSpace ? 'space' : '1');
      }

      function clearMarks() {
        var nodes = document.querySelectorAll('[' + ATTR + ']');
        for (var i = 0; i < nodes.length; i++) nodes[i].removeAttribute(ATTR);
      }

      function isSectionTitle(text) {
        return text === 'Projects' || text === 'Bots' || text === 'Chats';
      }

      function groupHasForeignSection(group, itemText) {
        if (!group) return false;
        var nodes = group.querySelectorAll('[data-sidebar="group-label"], button, a');
        for (var i = 0; i < nodes.length; i++) {
          var t = norm(nodes[i].textContent);
          if (isSectionTitle(t) && t !== itemText) return true;
        }
        return false;
      }

      function markProjectSection(el) {
        var row = el.closest('[data-sidebar="group-label"]')
          || el.closest('[data-sidebar="menu-item"]')
          || el.closest('li')
          || el;
        mark(row);
        var sibling = row.nextElementSibling;
        while (sibling) {
          var stop = false;
          if (sibling.getAttribute('data-sidebar') === 'group-label'
              && isSectionTitle(norm(sibling.textContent))) {
            stop = true;
          }
          var label = sibling.querySelector('[data-sidebar="group-label"]');
          if (label && isSectionTitle(norm(label.textContent))) stop = true;
          var btns = sibling.querySelectorAll('button');
          for (var b = 0; b < btns.length && !stop; b++) {
            if (isSectionTitle(norm(btns[b].textContent))) stop = true;
          }
          if (stop) break;
          mark(sibling);
          sibling = sibling.nextElementSibling;
        }
      }

      function targetFor(el, item) {
        if (!item.group) {
          return el.closest('[data-sidebar="menu-item"]') || el.closest('li') || el;
        }
        var group = el.closest('[data-sidebar="group"]');
        if (group && !groupHasForeignSection(group, item.text)) {
          return group;
        }
        markProjectSection(el);
        return null;
      }

      function markNav(full) {
        var active = ITEMS.filter(function (item) { return config[item.key]; });
        var selector = '[data-sidebar="menu-item"] [data-sidebar="menu-button"],'
          + '[data-sidebar="group"] button[aria-label],'
          + '[data-sidebar="group-label"],'
          + 'nav a, nav button, aside a, aside button,'
          + '[data-sidebar] a, [data-sidebar] button';
        var candidates = document.querySelectorAll(selector);
        for (var i = 0; i < candidates.length; i++) {
          var el = candidates[i];
          if (el.closest('[' + ATTR + ']')) continue;
          for (var j = 0; j < active.length; j++) {
            if (!matchesItem(el, active[j])) continue;
            mark(targetFor(el, active[j]));
            break;
          }
        }
        if (config.hideGrokBot) markHeaderControl('Grok Bot');
        if (config.hidePrivate) markHeaderControl('Private');
        markPageTopBar(full);
        markComposer();
      }

      function markComposer() {
        if (config.hideDictation) markComposerControl('button[aria-label^="Dictation"]');
        if (config.hideVoice) markComposerControl('button[aria-label^="Enter voice mode"]');
      }

      function markComposerControl(selector) {
        var buttons = document.querySelectorAll(selector);
        for (var i = 0; i < buttons.length; i++) {
          var btn = buttons[i];
          var slot = btn.closest('div.h-10.w-10') || btn;
          var wrap = slot.parentElement;
          if (!wrap || wrap.querySelector('[data-query-bar-mode-select]')) {
            mark(slot);
            continue;
          }
          mark(wrap);
        }
      }

      function markHeaderControl(name) {
        var needle = name.toLowerCase();
        var nodes = document.querySelectorAll('a, button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (el.closest('nav, aside, [data-sidebar]')) continue;
          var aria = norm(el.getAttribute('aria-label') || el.getAttribute('title'));
          var text = norm(el.textContent);
          var blob = (aria + ' ' + text).toLowerCase();
          if (blob.indexOf(needle) === -1) continue;
          // Keep the header's size when its controls disappear. Collapsing
          // them (or their parent row) shifts the New Chat heading/composer.
          // Mark only this control so the other toggle remains independent.
          mark(el, true);
        }
      }

      function findLoggedOutSignIn(root) {
        if (!root) return null;
        var bars = root.querySelectorAll(PAGE_TOP_BAR_SELECTOR);
        for (var b = 0; b < bars.length; b++) {
          var nodes = bars[b].querySelectorAll('a, button, [role="button"]');
          for (var i = 0; i < nodes.length; i++) {
            var el = nodes[i];
            var label = norm(
              el.getAttribute('aria-label')
              || el.getAttribute('title')
              || el.textContent
            ).toLowerCase();
            if (
              label === 'sign in' || label.indexOf('sign in ') === 0
              || label === 'log in' || label.indexOf('log in ') === 0
            ) {
              return { bar: bars[b], control: el };
            }
          }
        }
        return null;
      }

      function markLoggedOutHeaderChrome(auth) {
        if (!auth || !auth.bar || !auth.control) return;
        var nodes = auth.bar.querySelectorAll('a, button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (el === auth.control || el.contains(auth.control) || auth.control.contains(el)) continue;
          mark(el);
        }
      }

      function shouldHidePageTopBar(root) {
        return config.hideGrokBot && config.hidePrivate && !findLoggedOutSignIn(root);
      }

      function markPageTopBar(full) {
        if (usesShellInset()) return;
        var root = document.getElementById('grok-content-area') || document.querySelector('main');
        if (!root) return;
        var rootBox = root.getBoundingClientRect();
        var auth = findLoggedOutSignIn(root);
        var hideBar = shouldHidePageTopBar(root);
        markLoggedOutHeaderChrome(auth);
        if (hideBar) {
          var bars = root.querySelectorAll(PAGE_TOP_BAR_SELECTOR);
          for (var b = 0; b < bars.length; b++) mark(bars[b], true);
        }
        var fades = root.querySelectorAll('[aria-hidden="true"][class*="bg-gradient-to-b"]');
        for (var f = 0; f < fades.length; f++) {
          if (fades[f].id === 'grock-titlebar-fade') continue;
          mark(fades[f]);
        }
        var nodes = root.querySelectorAll('button, a, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (el.closest('nav, aside, [data-sidebar]')) continue;
          var aria = norm(el.getAttribute('aria-label') || el.getAttribute('title')).toLowerCase();
          if (
            aria === 'menu' ||
            aria.indexOf('sidebar') !== -1 ||
            aria.indexOf('open menu') !== -1 ||
            aria.indexOf('toggle menu') !== -1
          ) {
            mark(el, true);
            var row = el.parentElement;
            // The toggle lives in the same h-14 as Grok Bot / Private.
            // Only hide that row when Appearance is hiding the whole bar,
            // and preserve its place in the page's layout.
            if (hideBar && row && full) {
              var box = row.getBoundingClientRect();
              if (box.height <= 88 && box.top < rootBox.top + 120) mark(row, true);
            }
          }
        }
        if (!full || !hideBar) return;
        var divs = root.querySelectorAll('div');
        var limit = Math.min(divs.length, 48);
        for (var j = 0; j < limit; j++) {
          var d = divs[j];
          if (d.id === 'grock-titlebar-fade') continue;
          if (d.closest('[' + ATTR + ']')) continue;
          if (d.hasAttribute('data-composer-hero') || d.closest('[data-composer-hero]')) continue;
          var r = d.getBoundingClientRect();
          var top = r.top - rootBox.top;
          var left = r.left - rootBox.left;
          if (top < -4 || top > 24 || r.height < 36 || r.height > 72) continue;
          if (left > 80 || r.width < 200) continue;
          if (d.querySelector('button, a, svg')) {
            mark(d, true);
            break;
          }
        }
      }

      function clearBrokenCollapseHints() {
        try {
          document.cookie = 'sidebar:state=; path=/; max-age=0';
          document.cookie = 'sidebar_state=; path=/; max-age=0';
          localStorage.removeItem('sidebar:state');
          localStorage.removeItem('sidebar_state');
        } catch (err) {}
      }

      function sidebarShowsFullLabels() {
        var names = ['Chat', 'Imagine', 'Library', 'Automations'];
        var nodes = document.querySelectorAll('[data-sidebar] button, [data-sidebar] a, [data-sidebar] span');
        for (var i = 0; i < nodes.length; i++) {
          var text = norm(nodes[i].textContent);
          for (var j = 0; j < names.length; j++) {
            if (text !== names[j] && text.indexOf(names[j]) !== 0) continue;
            var box = nodes[i].getBoundingClientRect();
            if (box.width >= 52 && box.height >= 10 && box.left >= 0 && box.left < 300) {
              return true;
            }
          }
        }
        return false;
      }

      function findCollapseButton() {
        var trigger = document.querySelector('[data-sidebar="trigger"]');
        if (trigger) return trigger;
        var header = document.querySelector('[data-sidebar="header"]');
        if (!header) return null;
        var buttons = header.querySelectorAll('button');
        for (var i = 0; i < buttons.length; i++) {
          var aria = (
            (buttons[i].getAttribute('aria-label') || '') + ' ' +
            (buttons[i].getAttribute('title') || '')
          ).toLowerCase();
          if (
            aria.indexOf('collapse') !== -1 ||
            aria.indexOf('toggle sidebar') !== -1 ||
            aria.indexOf('close sidebar') !== -1 ||
            aria.indexOf('hide sidebar') !== -1
          ) {
            return buttons[i];
          }
        }
        if (buttons.length === 1) return buttons[0];
        return null;
      }

      function markSidebarShell() {
        if (!config.sidebarHidden) return;
        var inner = document.querySelector('[data-sidebar="sidebar"]')
          || document.querySelector('[data-sidebar="header"]')
          || document.querySelector('[data-sidebar]');
        if (!inner) return;
        var el = inner;
        var best = inner;
        while (el.parentElement && el.parentElement !== document.body) {
          var parent = el.parentElement;
          if (parent.id === 'grok-app-root' || parent.id === 'grok-content-area') {
            best = el;
            break;
          }
          var childBox = el.getBoundingClientRect();
          var parentBox = parent.getBoundingClientRect();
          var childW = childBox.width || el.offsetWidth;
          var parentW = parentBox.width || parent.offsetWidth;
          if (parentW > 600 && childW > 0 && childW < parentW * 0.45) {
            best = el;
            break;
          }
          if (childW >= 40 && childW <= 440 && (childBox.left <= 20 || el.offsetLeft <= 20)) {
            best = el;
          }
          el = parent;
        }
        mark(best);
      }

      var RAIL_ATTR = 'data-grock-rail';

      function classText(el) {
        if (!el) return '';
        var c = el.className;
        if (typeof c === 'string') return c;
        if (c && typeof c.baseVal === 'string') return c.baseVal;
        return '';
      }

      function isCollapseRail(el) {
        if (!el || el.nodeType !== 1) return false;
        var side = (el.getAttribute('data-sidebar') || '').toLowerCase();
        if (side === 'rail' || side === 'resize-handle') return true;
        var slot = (el.getAttribute('data-slot') || '').toLowerCase();
        if (slot === 'sidebar-rail' || slot === 'sidebar-resize-handle') return true;
        if (el.hasAttribute(RAIL_ATTR)) return true;
        var tag = el.tagName;
        if (tag !== 'DIV' && tag !== 'BUTTON') return false;
        if (el.childElementCount > 0) return false;
        if (String(el.textContent || '').trim()) return false;
        var cls = classText(el);
        if (cls.indexOf('absolute') === -1) return false;
        if (cls.indexOf('h-full') === -1) return false;
        if (cls.indexOf('cursor-pointer') === -1) return false;
        var w = el.offsetWidth;
        if (!w) {
          var cs = window.getComputedStyle(el);
          w = cs ? parseFloat(cs.width) : 0;
        }
        return w > 0 && w <= 16;
      }

      function muteCollapseRails() {
        var nodes = document.querySelectorAll(
          '[data-sidebar="rail"],[data-sidebar="resize-handle"],'
          + '[data-slot="sidebar-rail"],[data-slot="sidebar-resize-handle"],'
          + '[data-slot="sidebar"] div,[data-sidebar="sidebar"] div,'
          + '[data-collapsible][data-side] div'
        );
        for (var i = 0; i < nodes.length; i++) {
          if (!nodes[i].hasAttribute(RAIL_ATTR) && isCollapseRail(nodes[i])) {
            nodes[i].setAttribute(RAIL_ATTR, '1');
          }
        }
      }

      function railEventTarget(e) {
        var t = e.target;
        if (t && t.nodeType === 3) t = t.parentElement;
        if (!t || !t.closest) return null;
        var marked = t.closest(
          '[' + RAIL_ATTR + '],[data-sidebar="rail"],[data-sidebar="resize-handle"],'
          + '[data-slot="sidebar-rail"],[data-slot="sidebar-resize-handle"]'
        );
        if (marked) return marked;
        if (isCollapseRail(t)) return t;
        return null;
      }

      function blockRailEvent(e) {
        if (config.sidebarHidden) return;
        if (!railEventTarget(e)) return;
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
      }

      var railEventsBound = false;
      function bindRailGuards() {
        if (railEventsBound) return;
        railEventsBound = true;
        var types = ['pointerdown', 'pointerup', 'click', 'mousedown', 'mouseup', 'mouseover'];
        for (var i = 0; i < types.length; i++) {
          document.addEventListener(types[i], blockRailEvent, true);
        }
      }

      function findCollapseControl() {
        return findCollapseButton()
          || document.querySelector('[data-sidebar="rail"]')
          || document.querySelector('[data-sidebar="resize-handle"]')
          || document.querySelector('[data-slot="sidebar-rail"]')
          || document.querySelector('[data-slot="sidebar-resize-handle"]')
          || document.querySelector('[' + RAIL_ATTR + ']');
      }

      function sidebarIsIconCollapsed() {
        return !!document.querySelector(
          '[data-slot="sidebar"][data-state="collapsed"],'
          + '[data-sidebar="sidebar"][data-state="collapsed"],'
          + '[data-collapsible][data-side][data-state="collapsed"]'
        );
      }

      var uncollapseLock = false;
      function keepSidebarExpanded() {
        if (config.sidebarHidden || uncollapseLock) return;
        if (!sidebarIsIconCollapsed()) return;
        var button = findCollapseControl();
        if (!button) return;
        uncollapseLock = true;
        button.click();
        setTimeout(function () { uncollapseLock = false; }, 400);
      }

      function expandIfCollapsed() {
        keepSidebarExpanded();
      }

      function collapseIfExpanded() {
        if (config.sidebarHidden || !config.collapseSidebar || collapseTried || collapseTimer) return;
        var tries = 0;
        function attempt() {
          collapseTimer = null;
          if (!config.collapseSidebar || collapseTried) return;
          if (sidebarShowsFullLabels()) {
            var button = findCollapseButton();
            if (button) {
              collapseTried = true;
              button.click();
              return;
            }
          }
          tries += 1;
          if (tries < 24) collapseTimer = setTimeout(attempt, 250);
        }
        attempt();
      }

      // Promo chrome (DEC-047): hide known campaign shapes. Never click Dismiss.
      function forbiddenPromoText(text) {
        var t = String(text || '').toLowerCase();
        if (/terms of (service|use)|privacy policy|cookie (policy|settings|consent)/.test(t)) return true;
        if (/we've updated|we have updated|updated our (terms|privacy)|please review|\\bi agree\\b/.test(t)) return true;
        if (/billing|invoice|update (payment|card)|payment (method|failed)|subscription (expired|ended)/.test(t)) return true;
        if (/\\bsupergrok\\b/.test(t)) return true;
        if (/sign in|log in|continue with|password|verify your|two-factor|two factor/.test(t)) return true;
        if (/time for a break|rate limit|usage limit|you(?:'|’)ve reached/.test(t)) return true;
        if (/account settings|\\byour account\\b/.test(t)) return true;
        if (/connect your .{0,12}account/.test(t)) return true;
        if (/confirm your age|age verification/.test(t)) return true;
        return false;
      }

      function isProtectedPromoHost(el) {
        if (!el || !el.closest) return true;
        if (el.closest('[role="dialog"], [role="alertdialog"]')) return true;
        if (el.closest('[cmdk-root], [cmdk-list], [cmdk-input], [cmdk-dialog]')) return true;
        if (el.closest('[data-grock-plugins-dialog], [data-sidebar], nav, aside')) return true;
        if (el.closest('form')) return true;
        return false;
      }

      function isDismissControl(el) {
        if (!el) return false;
        var aria = norm(el.getAttribute('aria-label') || el.getAttribute('title'));
        if (aria === 'Dismiss' || aria === 'Close') return true;
        return norm(el.textContent) === 'Dismiss';
      }

      function isPromoCta(el) {
        if (!el || isDismissControl(el)) return false;
        var t = norm(el.textContent);
        if (t === 'Add' || t === 'Enable') return true;
        return /^try\\b/i.test(t);
      }

      function cardHasPromoCta(card) {
        var nodes = card.querySelectorAll('button, a, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          if (isPromoCta(nodes[i])) return true;
        }
        return false;
      }

      function hasPromoSignal(card) {
        if (card.querySelector('video, img')) return true;
        if (cardHasPromoCta(card)) return true;
        return /\\bnow with\\b/i.test(norm(card.textContent));
      }

      function looksLikePromoToast(card) {
        if (!card || isProtectedPromoHost(card)) return false;
        if (forbiddenPromoText(card.textContent)) return false;
        if (!hasPromoSignal(card)) return false;
        var r = card.getBoundingClientRect();
        var vw = window.innerWidth || 1;
        var vh = window.innerHeight || 1;
        if (r.width < 200 || r.width > 480) return false;
        if (r.height < 80 || r.height > 640) return false;
        if (r.width >= vw - 16 && r.height >= vh - 16) return false;
        var cx = r.left + r.width / 2;
        if (Math.abs(cx - vw / 2) < 40 && r.width > 360) return false;
        var nearLeft = r.left < 80;
        var nearRight = (vw - r.right) < 80;
        var nearBottom = (vh - r.bottom) < 160;
        var nearTop = r.top < 120;
        if (!(nearLeft || nearRight)) return false;
        if (!(nearBottom || nearTop)) return false;
        return true;
      }

      function composerUpsellCard(dismissBtn) {
        var el = dismissBtn.parentElement;
        var best = null;
        var guard = 0;
        while (el && el !== document.body && guard++ < 12) {
          if (el.querySelector('textarea, [contenteditable="true"], [data-query-bar-mode-select]')) break;
          if (isProtectedPromoHost(el)) break;
          if (forbiddenPromoText(el.textContent)) break;
          if (cardHasPromoCta(el)) {
            var r = el.getBoundingClientRect();
            if (r.height <= 160 && (r.width >= 200 || r.width === 0)) best = el;
          }
          el = el.parentElement;
        }
        return best;
      }

      function isGrokBotPromo(el) {
        var t = norm(el && el.textContent).toLowerCase();
        if (t.indexOf('meet grok bot') === -1) return false;
        return t.indexOf('ai teammates you can give real work to') !== -1
          || t.indexOf('bots can sign in to your tools') !== -1;
      }

      function grokBotPromoCard(dismissBtn) {
        var el = dismissBtn.parentElement;
        var best = null;
        var guard = 0;
        while (el && el !== document.body && guard++ < 16) {
          if (isGrokBotPromo(el)) {
            var r = el.getBoundingClientRect();
            if (r.width >= 200 && r.width <= 520 && r.height >= 120 && r.height <= 700) best = el;
          }
          el = el.parentElement;
        }
        return best;
      }

      function markGrokBotPromo() {
        var nodes = document.querySelectorAll('button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          var btn = nodes[i];
          if (!isDismissControl(btn)) continue;
          var card = grokBotPromoCard(btn);
          if (card) mark(card);
        }
      }

      function markPromoToasts() {
        var nodes = document.querySelectorAll(
          'button[aria-label="Dismiss"], button[aria-label="Close"],'
          + '[role="button"][aria-label="Dismiss"], [role="button"][aria-label="Close"]'
        );
        for (var i = 0; i < nodes.length; i++) {
          var btn = nodes[i];
          if (isProtectedPromoHost(btn)) continue;
          var el = btn;
          var guard = 0;
          while (el && el !== document.body && guard++ < 16) {
            var s = window.getComputedStyle(el);
            if (s && s.position === 'fixed') {
              if (looksLikePromoToast(el)) mark(el);
              break;
            }
            el = el.parentElement;
          }
        }
      }

      function markComposerUpsells() {
        var nodes = document.querySelectorAll('button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          var btn = nodes[i];
          if (norm(btn.textContent) !== 'Dismiss') continue;
          if (isProtectedPromoHost(btn)) continue;
          var card = composerUpsellCard(btn);
          if (card) mark(card);
        }
      }

      function markPromos() {
        markGrokBotPromo();
        markPromoToasts();
        markComposerUpsells();
      }

      var lastSessionPosted = '';
      var SESSION_MORE = 'data-grock-session-more';
      var SESSION_SHARE = 'data-grock-session-share';
      var SESSION_PANEL = 'data-grock-session-panel';
      var SESSION_CLUSTER = 'data-grock-session-cluster';
      var RIGHT_PANEL = 'data-grock-right-panel';
      var PANEL_CONTROLS = 'data-grock-panel-controls';

      function isConversationPath() {
        return /^\\/c\\/[A-Za-z0-9_-]+/.test(String(location.pathname || ''));
      }

      function isSessionIconButton(el) {
        if (!el) return false;
        var tag = el.tagName && el.tagName.toUpperCase();
        if (tag !== 'BUTTON' && el.getAttribute('role') !== 'button') return false;
        if (el.closest('nav, aside, [data-sidebar], form, [data-query-bar-mode-select]')) return false;
        if (norm(el.textContent).length > 3) return false;
        return true;
      }

      function classifySessionButton(el) {
        var aria = (el.getAttribute('aria-label') || el.getAttribute('title') || '').toLowerCase();
        if (/^(more|more options|options)$/.test(aria)) return 'more';
        if (aria.indexOf('share') !== -1 || aria.indexOf('copy link') !== -1 || aria.indexOf('copied') !== -1) {
          return 'share';
        }
        if (
          aria.indexOf('panel') !== -1
          || aria.indexOf('artifact') !== -1
          || aria.indexOf('preview') !== -1
          || aria.indexOf('build') !== -1
        ) {
          return 'panel';
        }
        return '';
      }

      function findSessionCluster() {
        var root = document.getElementById('grok-content-area');
        if (!root || !isConversationPath()) return null;
        // Share can become a spinner, and opening the panel leaves a DIV
        // placeholder in its slot. Anchor to the labeled header More button,
        // not a count/order of icon-shaped children or screen coordinates.
        var bars = root.querySelectorAll(PAGE_TOP_BAR_SELECTOR);
        for (var i = 0; i < bars.length; i++) {
          var buttons = bars[i].querySelectorAll('button, [role="button"]');
          for (var j = 0; j < buttons.length; j++) {
            if (isSessionIconButton(buttons[j]) && classifySessionButton(buttons[j]) === 'more') {
              return buttons[j].parentElement;
            }
          }
        }
        return null;
      }

      function assignSessionButtons(cluster) {
        var kids = [];
        for (var i = 0; i < cluster.children.length; i++) {
          if (isSessionIconButton(cluster.children[i])) kids.push(cluster.children[i]);
        }
        var roles = { more: null, share: null, panel: null };
        for (var i = 0; i < kids.length; i++) {
          var role = classifySessionButton(kids[i]);
          if (role && !roles[role]) roles[role] = kids[i];
        }
        return roles;
      }

      function syncSessionMarks(wanted) {
        var attributes = [SESSION_CLUSTER, SESSION_MORE, SESSION_SHARE, SESSION_PANEL, RIGHT_PANEL, PANEL_CONTROLS];
        var nodes = document.querySelectorAll(attributes.map(function (name) { return '[' + name + ']'; }).join(','));
        for (var i = 0; i < nodes.length; i++) {
          var names = wanted.get(nodes[i]) || [];
          for (var j = 0; j < attributes.length; j++) {
            var name = attributes[j];
            if (names.indexOf(name) === -1 && nodes[i].hasAttribute(name)) nodes[i].removeAttribute(name);
          }
        }
        wanted.forEach(function (names, node) {
          names.forEach(function (name) {
            if (node.getAttribute(name) !== '1') node.setAttribute(name, '1');
          });
        });
      }

      function sessionButtonEnabled(button) {
        return !!button && !button.disabled && button.getAttribute('aria-disabled') !== 'true'
          && button.getAttribute('aria-busy') !== 'true';
      }

      function sessionStateFromDom() {
        return {
          more: !!document.querySelector('[' + SESSION_MORE + ']'),
          share: sessionButtonEnabled(document.querySelector('[' + SESSION_SHARE + ']')),
          panel: !!document.querySelector('[' + SESSION_PANEL + ']'),
          authenticated: authenticationStateFromDom()
        };
      }

      function authenticationStateFromDom() {
        var root = contentRoot();
        if (!root) return null;
        if (findLoggedOutSignIn(root)) return false;
        // React may not have mounted the logged-out header yet. Keep native
        // controls disabled until the finished document can answer.
        if (document.readyState !== 'complete') return null;
        return true;
      }

      function postSessionState(state) {
        var authKey = state.authenticated === true ? '1' : (state.authenticated === false ? '0' : '?');
        var key = (state.more ? '1' : '0') + (state.share ? '1' : '0')
          + (state.panel ? '1' : '0') + authKey;
        if (key === lastSessionPosted) return;
        lastSessionPosted = key;
        var handlers = window.webkit && window.webkit.messageHandlers;
        var bridge = handlers && handlers.grockSession;
        if (!bridge) return;
        try { bridge.postMessage(state); } catch (err) {}
      }

      function markSessionCluster() {
        // Reconcile, don't clear/reapply: unchanged markers must not trigger
        // style invalidation or other page observers on every refresh.
        var wanted = new Map();
        function want(node, name) {
          if (!node) return;
          var names = wanted.get(node) || [];
          if (names.indexOf(name) === -1) names.push(name);
          wanted.set(node, names);
        }
        // In the open layout the panel and its floating Expand / Toggle strip
        // are siblings of MAIN, not descendants of the conversation header.
        var app = document.getElementById('grok-app-root');
        var detachedPanelToggle = null;
        if (app) {
          for (var i = 0; i < app.children.length; i++) {
            var child = app.children[i];
            if (child.classList.contains('h-dvh') && child.classList.contains('absolute')
                && child.getAttribute('aria-hidden') === 'false') {
              want(child, RIGHT_PANEL);
            }
            var toggle = child.querySelector(':scope > button[aria-label="Toggle Right Panel"][aria-pressed="true"]');
            if (toggle && child.querySelector(':scope > button[aria-label="Expand"], :scope > button[aria-label="Collapse"]')) {
              want(child, PANEL_CONTROLS);
              detachedPanelToggle = toggle;
            }
          }
        }
        var cluster = findSessionCluster();
        if (!cluster) {
          syncSessionMarks(wanted);
          postSessionState(sessionStateFromDom());
          return;
        }
        var roles = assignSessionButtons(cluster);
        if (detachedPanelToggle) roles.panel = detachedPanelToggle;
        want(cluster, SESSION_CLUSTER);
        var parent = cluster.parentElement;
        while (parent && parent.id !== 'grok-content-area') {
          var cls = classNameOf(parent);
          if (cls.indexOf('absolute') !== -1 && cls.indexOf('top-0') !== -1) {
            want(parent, SESSION_CLUSTER);
            break;
          }
          parent = parent.parentElement;
        }
        want(roles.more, SESSION_MORE);
        want(roles.share, SESSION_SHARE);
        want(roles.panel, SESSION_PANEL);
        syncSessionMarks(wanted);
        postSessionState(sessionStateFromDom());
      }

      function classNameOf(el) {
        if (!el || el.className == null) return '';
        if (typeof el.className === 'string') return el.className;
        return String(el.className.baseVal || '');
      }

      function findSessionMenu(more) {
        if (!more || !more.isConnected) return null;
        var controlled = more.getAttribute('aria-controls');
        var menus = document.querySelectorAll('[role="menu"]');
        for (var i = 0; i < menus.length; i++) {
          var menu = menus[i];
          var labelledBy = (menu.getAttribute('aria-labelledby') || '').split(/\\s+/);
          if (!(controlled && menu.id === controlled) && !(more.id && labelledBy.indexOf(more.id) !== -1)) continue;
          if (menu.closest('[data-state="closed"], [aria-hidden="true"]')) continue;
          var style = window.getComputedStyle(menu);
          if (style.display !== 'none' && style.visibility !== 'hidden') return menu;
        }
        return null;
      }

      function findSessionMenuItem(needles, more) {
        var menu = findSessionMenu(more);
        if (!menu) return null;
        var nodes = menu.querySelectorAll(
          '[role="menuitem"], [role="menu"] button, [role="menu"] [role="button"],'
          + ' [data-radix-menu-content] button, [data-slot="dropdown-menu-item"]'
        );
        for (var i = 0; i < nodes.length; i++) {
          if (!nodes[i].isConnected) continue;
          if (nodes[i].closest('[data-state="closed"], [aria-hidden="true"]')) continue;
          var style = window.getComputedStyle(nodes[i]);
          if (!style || style.display === 'none' || style.visibility === 'hidden') continue;
          var text = norm(
            nodes[i].getAttribute('aria-label')
            || nodes[i].getAttribute('title')
            || nodes[i].textContent
          );
          for (var n = 0; n < needles.length; n++) {
            if (needles[n].test(text)) return nodes[i];
          }
        }
        return null;
      }

      var PIN_NEEDLES = [/^unpin\\b/i, /^pin\\b/i];
      var DELETE_NEEDLES = [/delete chat/i, /^delete$/i];
      var PROJECT_NEEDLES = [/^move to (a )?project\\b/i];
      var PANEL_NEEDLES = [
        /^(show|hide|toggle|open|close)(\\s+the)?\\s+(right\\s+)?panel$/i,
        /^(show|hide|toggle|open|close)\\s+(artifact|preview|build)(\\s+panel)?$/i
      ];

      function openHiddenMoreMenu() {
        markSessionCluster();
        var more = document.querySelector('[' + SESSION_MORE + ']');
        if (!more) return Promise.resolve(null);
        document.documentElement.setAttribute('data-grock-picking-menu', '');
        if (!findSessionMenu(more)) {
          // Radix opens dropdown triggers on pointerdown, not click.
          more.dispatchEvent(new PointerEvent('pointerdown', {
            bubbles: true, button: 0, pointerType: 'mouse', ctrlKey: false
          }));
        }
        return waitForSessionMenu(more, true).then(function () { return more; });
      }

      function waitForSessionMenu(more, opening) {
        return new Promise(function (resolve) {
          var observer = new MutationObserver(check);
          var timeout = setTimeout(function () { finish(false); }, 400);
          function finish(found) {
            observer.disconnect();
            clearTimeout(timeout);
            resolve(found);
          }
          function check() {
            if (!!findSessionMenu(more) === opening) finish(true);
          }
          observer.observe(document.documentElement, {
            childList: true, subtree: true, attributes: true,
            attributeFilter: ['data-state', 'aria-expanded', 'aria-hidden']
          });
          check();
        });
      }

      function closeHiddenMoreMenu(more) {
        var menu = findSessionMenu(more);
        if (menu) {
          menu.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        }
        return waitForSessionMenu(more, false);
      }

      var sessionMenuOperation = Promise.resolve();
      function withHiddenMoreMenu(work) {
        var operation = sessionMenuOperation.then(function () {
          var focus = document.activeElement;
          var more = null;
          var handedOff = false;
          return openHiddenMoreMenu().then(function (opened) {
            more = opened;
            return work(more, function () { handedOff = true; });
          }).finally(function () {
            if (handedOff) {
              // Grok now owns focus and dismissal. Escape here would dismiss
              // the project submenu (or its dialog) immediately after opening.
              document.documentElement.removeAttribute('data-grock-picking-menu');
              return;
            }
            return closeHiddenMoreMenu(more).finally(function () {
              document.documentElement.removeAttribute('data-grock-picking-menu');
              var active = document.activeElement;
              var inDialog = active && active.closest('[role="dialog"], [role="alertdialog"]');
              if (!inDialog && focus && focus.isConnected && typeof focus.focus === 'function') {
                focus.focus({ preventScroll: true });
              }
            });
          });
        });
        sessionMenuOperation = operation.catch(function () {});
        return operation;
      }

      function projectPickerNodes() {
        return Array.from(document.querySelectorAll(
          '[role="menu"], [role="dialog"], [role="alertdialog"], [data-slot="popover-content"], [cmdk-root]'
        )).filter(function (node) {
          if (node.closest('[data-state="closed"], [aria-hidden="true"]')) return false;
          var style = window.getComputedStyle(node);
          return style.display !== 'none' && style.visibility !== 'hidden';
        });
      }

      function waitForProjectPicker(before) {
        return new Promise(function (resolve) {
          var observer = new MutationObserver(check);
          var timeout = setTimeout(function () { finish(null); }, 700);
          function finish(picker) { observer.disconnect(); clearTimeout(timeout); resolve(picker); }
          function check() {
            var picker = projectPickerNodes().find(function (node) { return before.indexOf(node) === -1; });
            if (picker) finish(picker);
          }
          observer.observe(document.documentElement, {
            childList: true, subtree: true, attributes: true,
            attributeFilter: ['data-state', 'aria-hidden', 'style']
          });
          check();
        });
      }

      function positionProjectPicker(picker, source) {
        if (picker.getAttribute('role') !== 'menu') return;
        function anchor(node) {
          if (!node) return;
          var wrapper = node.closest('[data-radix-popper-content-wrapper]') || node;
          wrapper.setAttribute('data-grock-project-popover', '');
        }
        // The original trigger is hidden, so Radix's measured anchor is zero.
        // Keep its own picker below the native titlebar and within the window.
        anchor(picker);
        anchor(source);
        if (!source || source.contains(picker)) return;
        source.setAttribute('data-grock-project-source', '');
        var observer = new MutationObserver(function () {
          if (!picker.isConnected || picker.closest('[data-state="closed"], [aria-hidden="true"]')) {
            source.removeAttribute('data-grock-project-source');
            observer.disconnect();
          }
        });
        observer.observe(document.documentElement, {
          childList: true, subtree: true, attributes: true, attributeFilter: ['data-state', 'aria-hidden']
        });
      }

      function openProjectPicker() {
        return withHiddenMoreMenu(function (more, handOff) {
          var hit = findSessionMenuItem(PROJECT_NEEDLES, more);
          if (!hit || hit.disabled || hit.getAttribute('aria-disabled') === 'true') return 'unavailable';
          var before = projectPickerNodes();
          if (hit.getAttribute('aria-haspopup') === 'menu') {
            // Radix submenus open on ArrowRight; their parent menu stays open.
            hit.focus({ preventScroll: true });
            hit.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }));
          } else {
            hit.click();
          }
          return waitForProjectPicker(before).then(function (picker) {
            if (!picker) return 'missing';
            positionProjectPicker(picker, findSessionMenu(more));
            handOff();
            return 'opened';
          });
        });
      }

      function clickSession(name) {
        markSessionCluster();
        if (name === 'project') return openProjectPicker();
        if (name === 'share' || name === 'panel' || name === 'more') {
          var direct = document.querySelector('[data-grock-session-' + name + ']');
          if (direct) {
            if (!sessionButtonEnabled(direct)) return Promise.resolve('unavailable');
            direct.click();
            return Promise.resolve('clicked');
          }
          if (name !== 'panel') return Promise.resolve('missing');
        }
        if (name !== 'pin' && name !== 'delete' && name !== 'panel') return Promise.resolve('unknown');
        var needles = name === 'pin' ? PIN_NEEDLES : (name === 'delete' ? DELETE_NEEDLES : PANEL_NEEDLES);
        return withHiddenMoreMenu(function (more) {
          if (!more) return 'missing';
          var hit = findSessionMenuItem(needles, more);
          if (!hit) return 'missing';
          hit.click();
          // Let Radix close before cleanup, so Escape cannot dismiss any
          // dialog that the selected item may have opened.
          return waitForSessionMenu(more, false).then(function () { return 'clicked'; });
        });
      }

      function inspectSessionMenu() {
        return withHiddenMoreMenu(function (more) {
          if (!more) return { pin: 'missing', panel: false, project: false };
          var pin = findSessionMenuItem(PIN_NEEDLES, more);
          var text = pin ? norm(pin.textContent).toLowerCase() : '';
          var panel = !!document.querySelector('[' + SESSION_PANEL + ']')
            || !!findSessionMenuItem(PANEL_NEEDLES, more);
          return {
            pin: !pin ? 'missing' : (text.indexOf('unpin') === 0 ? 'unpin' : 'pin'),
            panel: panel,
            project: !!findSessionMenuItem(PROJECT_NEEDLES, more)
          };
        });
      }

      function sessionSnapshot() {
        markSessionCluster();
        return sessionStateFromDom();
      }

      function paint(full) {
        // A full/timer paint covers the pending frame pass too. This also
        // drains deferred work when an occluded WebView stops receiving rAF.
        cancelChromeFrame();
        if (full && paintTimer) {
          clearTimeout(paintTimer);
          paintTimer = null;
        }
        var root = document.documentElement;
        var wasHidden = root.hasAttribute('data-grock-sidebar-hidden');
        if (!config.sidebarHidden && wasHidden) {
          // Expand grok.com while the rail is still CSS-hidden. Unhiding a
          // collapsed rail first flashes full width, snaps to icons, then
          // we click expand (the open-close-open bounce).
          keepSidebarExpanded();
        }
        if (config.sidebarHidden) {
          if (!wasHidden) {
            root.setAttribute('data-grock-sidebar-hidden', '');
          }
        } else if (wasHidden) {
          root.removeAttribute('data-grock-sidebar-hidden');
        }
        if (isImaginePath()) {
          if (!root.hasAttribute('data-grock-imagine-path')) {
            root.setAttribute('data-grock-imagine-path', '');
          }
        } else if (root.hasAttribute('data-grock-imagine-path')) {
          root.removeAttribute('data-grock-imagine-path');
        }
        if (isImaginePage()) {
          if (!root.hasAttribute('data-grock-imagine')) {
            root.setAttribute('data-grock-imagine', '');
          }
        } else if (root.hasAttribute('data-grock-imagine')) {
          root.removeAttribute('data-grock-imagine');
        }
        if (usesShellInset()) {
          if (!root.hasAttribute('data-grock-shell-inset')) {
            root.setAttribute('data-grock-shell-inset', '');
          }
        } else if (root.hasAttribute('data-grock-shell-inset')) {
          root.removeAttribute('data-grock-shell-inset');
        }
        if (shouldHidePageTopBar(contentRoot())) {
          if (!root.hasAttribute('data-grock-page-header-hidden')) {
            root.setAttribute('data-grock-page-header-hidden', '');
          }
        } else if (root.hasAttribute('data-grock-page-header-hidden')) {
          root.removeAttribute('data-grock-page-header-hidden');
        }
        ensureStyle();
        markPluginsDialog();
        applyImagineShellInset();
        if (usesShellInset()) {
          clearImagineOverlayChrome();
        } else {
          ensureTitlebarFade();
        }
        if (full) clearMarks();
        markNav(!!full);
        markPromos();
        markSessionCluster();
        if (full) markSidebarShell();
        var insetChanged = applyContentInset();
        muteCollapseRails();
        bindRailGuards();
        if (full && !config.sidebarHidden) keepSidebarExpanded();
        if (!usesShellInset()) requestAnimationFrame(ensureTitlebarFade);
        if (insetChanged) chaseContentInset();
      }

      function apply(next, opts) {
        opts = opts || {};
        merge(window.__grockChromeConfig);
        merge(next);
        if (opts.forceCollapse) collapseTried = false;
        if (opts.expand) collapseTried = true;
        paint(true);
        if (opts.expand) {
          requestAnimationFrame(function () {
            requestAnimationFrame(expandIfCollapsed);
          });
        } else if (opts.forceCollapse && config.collapseSidebar && !config.sidebarHidden) {
          collapseIfExpanded();
        }
      }

      var paintTimer = null;
      var chromeFrame = null;
      function cancelChromeFrame() {
        if (chromeFrame === null) return;
        cancelAnimationFrame(chromeFrame);
        chromeFrame = null;
      }
      function refreshChromeFrame() {
        chromeFrame = null;
        markPluginsDialog();
        markPromos();
        if (usesShellInset()) applyImagineShellInset();
        else applyContentInset();
      }
      var insetChase = 0;
      function chaseContentInset() {
        insetChase += 1;
        var token = insetChase;
        var n = 0;
        function tick() {
          if (token !== insetChase) return;
          if (usesShellInset()) applyImagineShellInset();
          else applyContentInset();
          n += 1;
          if (n < 8) requestAnimationFrame(tick);
        }
        requestAnimationFrame(tick);
      }
      function schedule() {
        if (chromeFrame === null) chromeFrame = requestAnimationFrame(refreshChromeFrame);
        if (paintTimer) return;
        paintTimer = setTimeout(function () {
          paintTimer = null;
          paint(false);
        }, 200);
      }

      function isSidebarStateNode(el) {
        if (!el || el.nodeType !== 1) return false;
        if (el.hasAttribute('data-collapsible')) return true;
        var slot = (el.getAttribute('data-slot') || '').toLowerCase();
        var side = (el.getAttribute('data-sidebar') || '').toLowerCase();
        return slot.indexOf('sidebar') !== -1 || side === 'sidebar';
      }

      function isOwnChromeNode(el) {
        if (!el || el.nodeType !== 1) return false;
        var id = el.id || '';
        return id === STYLE_ID || id === 'grock-edge-fix' || id === 'grock-titlebar-fade';
      }

      function isComposerTree(el) {
        if (!el) return false;
        if (el.nodeType === 3) el = el.parentElement;
        if (!el || !el.closest) return false;
        if (el.closest('textarea, input, [contenteditable], [contenteditable="true"], [contenteditable=""], [role="textbox"]')) {
          return true;
        }
        if (el.closest('[data-query-bar-mode-select]')) return true;
        var host = el.closest('form');
        if (host && host.querySelector
            && host.querySelector('textarea, [contenteditable="true"], [role="textbox"]')) {
          var box = host.getBoundingClientRect();
          if (box.height > 0 && box.height < 320) return true;
        }
        return false;
      }

      var SESSION_MUTATION_SELECTOR = '#grok-app-root, #grok-content-area,'
        + PAGE_TOP_BAR_SELECTOR + ', button[aria-label="Toggle Right Panel"]';
      function touchesSessionChrome(record) {
        var target = record.target;
        if (target.closest('[' + SESSION_CLUSTER + '],[' + PANEL_CONTROLS + '],[' + RIGHT_PANEL + '],'
            + PAGE_TOP_BAR_SELECTOR)) return true;
        if (target.id === 'grok-app-root' || target.id === 'grok-content-area') return true;
        // Open/closed panel state can change without adding/removing a node.
        if (target.parentElement && target.parentElement.id === 'grok-app-root') return true;
        if (record.type === 'attributes') return false;
        var nodes = Array.from(record.addedNodes).concat(Array.from(record.removedNodes));
        for (var i = 0; i < nodes.length; i++) {
          var node = nodes[i];
          if (node.nodeType !== 1 || isOwnChromeNode(node)) continue;
          if (node.matches(SESSION_MUTATION_SELECTOR) || node.querySelector(SESSION_MUTATION_SELECTOR)) return true;
        }
        return false;
      }

      var observer = new MutationObserver(function (records) {
        var sessionDirty = false;
        var chromeDirty = false;
        for (var i = 0; i < records.length; i++) {
          var r = records[i];
          var t = r.target;
          if (isOwnChromeNode(t)) continue;
          if (r.type === 'attributes') {
            if (touchesSessionChrome(r)) sessionDirty = true;
            if (isSidebarStateNode(t)) chromeDirty = true;
            continue;
          }
          if (isComposerTree(t)) continue;
          var added = r.addedNodes;
          var saw = false;
          for (var j = 0; j < added.length; j++) {
            if (added[j].nodeType !== 1 || isOwnChromeNode(added[j])) continue;
            saw = true;
            break;
          }
          if (!saw) {
            var removed = r.removedNodes;
            for (var k = 0; k < removed.length; k++) {
              if (removed[k].nodeType !== 1 || isOwnChromeNode(removed[k])) continue;
              saw = true;
              break;
            }
          }
          if (!saw) continue;
          chromeDirty = true;
          if (!sessionDirty && touchesSessionChrome(r)) sessionDirty = true;
        }
        // Inspect the whole delivery: an unrelated first record must not
        // hide a later header remount. Only session chrome needs synchronous
        // discovery; promo/layout scans are coalesced before the next paint.
        if (sessionDirty) markSessionCluster();
        if (chromeDirty) schedule();
      });
      function watch() {
        if (document.documentElement) {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['data-state', 'disabled', 'aria-disabled', 'aria-busy', 'aria-pressed', 'aria-hidden']
          });
        }
        window.addEventListener('resize', function () {
          if (!usesShellInset()) ensureTitlebarFade();
        });
      }

      function dumpLayout() {
        var root = contentRoot();
        function clsOf(el) {
          if (!el || el.className == null) return '';
          if (typeof el.className === 'string') return el.className;
          return String(el.className.baseVal || '');
        }
        function brief(el) {
          if (!el) return null;
          var s = window.getComputedStyle(el);
          var r = el.getBoundingClientRect();
          return {
            tag: el.tagName,
            id: el.id || '',
            class: clsOf(el).slice(0, 220),
            grock: {
              content: !!(el.getAttribute && el.getAttribute(CONTENT_INSET)),
              home: !!(el.getAttribute && el.getAttribute(HOME_INSET)),
              edge: !!(el.getAttribute && el.getAttribute('data-grock-edge-shell'))
            },
            pos: s.position,
            oy: s.overflowY,
            box: { t: Math.round(r.top), b: Math.round(r.bottom), h: Math.round(r.height) },
            sh: el.scrollHeight,
            ch: el.clientHeight,
            oh: el.offsetHeight
          };
        }
        var tree = [];
        function walk(el, depth) {
          if (!el || depth > 6) return;
          var row = brief(el);
          row.depth = depth;
          tree.push(row);
          var kids = el.children;
          for (var i = 0; i < kids.length; i++) {
            var c = kids[i];
            if (c.tagName === 'SCRIPT' || c.tagName === 'STYLE' || c.tagName === 'LINK' || c.tagName === 'NOSCRIPT') continue;
            if (c.id === 'grock-titlebar-fade') continue;
            walk(c, depth + 1);
          }
        }
        if (root) walk(root, 0);
        var ta = document.querySelector('textarea, [contenteditable="true"], [role="textbox"]');
        return {
          path: String(location.pathname || ''),
          vp: { w: window.innerWidth, h: window.innerHeight },
          pinned: brief(pinnedInsetTarget),
          fade: brief(document.getElementById('grock-titlebar-fade')),
          textarea: brief(ta),
          tree: tree
        };
      }

      window.__grockChrome = {
        set: apply,
        dumpLayout: dumpLayout,
        session: sessionSnapshot,
        clickSession: clickSession,
        inspectSessionMenu: inspectSessionMenu
      };

      clearBrokenCollapseHints();
      merge(window.__grockChromeConfig);
      apply();
      watch();
      // Authentication stays unknown until readyState is complete. A full
      // DOMContentLoaded paint cancels older timers, so report load explicitly
      // instead of depending on another mutation or deferred layout pass.
      window.addEventListener('load', markSessionCluster, { once: true });
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () {
          apply();
        });
      }
    })();
    """
}
