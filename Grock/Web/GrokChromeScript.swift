import Foundation

// DOM adaptation stays separate from the native session and composer lifecycle.
extension WebViewStore {
    /// Fit grok.com's shell under the native titlebar and apply Appearance.
    ///
    /// grok.com keeps a 56px chrome band at the top of every view, so the 52pt
    /// titlebar sits in that band and nothing has to be pushed down. This script
    /// hides the controls the titlebar owns (sidebar toggle, Search, the chat
    /// title, Conversation Actions, the right pane toggle), hides what Settings
    /// asks it to, and reports what the titlebar may offer.
    ///
    /// Match ids, roles, labels, and `data-*` hooks. grok.com's class names are
    /// hashed and change with every build.
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
      // Sidebar rows with nothing but a label to go on. Groups and the
      // account-row button have their own hooks and are hidden in CSS.
      var ROWS = [
        { key: 'hideImagine', text: 'Imagine' },
        { key: 'hideLibrary', text: 'Library' },
        { key: 'hideAutomations', text: 'Automations' }
      ];
      function merge(next) {
        if (!next || typeof next !== 'object') return;
        Object.keys(config).forEach(function (key) {
          if (Object.prototype.hasOwnProperty.call(next, key)) config[key] = !!next[key];
        });
      }

      var SIDEBAR = '#app-sidebar';
      // The chrome band over the main column. Pages such as Library put a
      // second, in-flow header (breadcrumb and page actions) under it.
      // Signed out, grok.com serves a thinner shell whose band is a nav
      // holding the logo, Settings, Sign in, and Sign up.
      var PAGE_HEADER_PARTS = 'header:has(> [data-context-tray-yield]),'
        + 'header[data-header-over-column],'
        + 'nav[aria-label="Top navigation"]';
      var PAGE_HEADER = PAGE_HEADER_PARTS.split(',').map(function (part) {
        return '#grok-content-area ' + part;
      }).join(',');
      var PANE_TOGGLE = 'button[aria-label="Toggle right pane"], button[aria-label="Hide pane"]';

      function scoped(prefix, list, suffix) {
        return list.split(',').map(function (part) {
          return prefix + part.trim() + (suffix || '');
        }).join(',');
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
        var css = '[' + ATTR + ']{display:none!important;}'
          + ':root{--grock-titlebar:52px;}'
          + titlebarCSS()
          + pageHeaderCSS()
          + rightPaneCSS()
          + lightboxCSS()
          + signedOutCSS()
          + sessionMenuCSS()
          + sidebarHideCSS()
          + preferenceCSS();
        if (el.textContent !== css) el.textContent = css;
      }

      function titlebarCSS() {
        // The native titlebar has the sidebar toggle and Search. grok.com
        // draws its own pair where the traffic lights are. They stay in the
        // DOM so Search and the sidebar can still be driven by a click.
        return '[data-leading-chrome]{display:none!important;}';
      }

      function pageHeaderCSS() {
        // Title and Conversation Actions always belong to the titlebar. They
        // keep their box, so the menu they open still has an anchor.
        // The rest of the band (Private, a logged-out Sign in) is hidden with
        // its space kept when Appearance hides Private, and otherwise drops
        // below the titlebar with its controls visible.
        return scoped('', PAGE_HEADER, ' [data-testid="conversation-title"]') + ','
          + scoped('', PAGE_HEADER, ' [data-testid="conversation-actions-trigger"]')
          + '{visibility:hidden!important;pointer-events:none!important;}'
          + scoped('html[data-grock-page-header-hidden] ', PAGE_HEADER)
          + '{visibility:hidden!important;pointer-events:none!important;}'
          + scoped('html:not([data-grock-page-header-hidden]) ', PAGE_HEADER)
          + '{top:var(--grock-titlebar)!important;}';
      }

      function rightPaneCSS() {
        // The closed pane's toggle floats in the top-right corner, under the
        // titlebar's buttons; More has it. An open pane has a toolbar of its
        // own in the band, so the pane starts below the titlebar instead.
        return '#grok-app-root section > [data-context-tray-yield] button[aria-label="Toggle right pane"]'
          + '{visibility:hidden!important;pointer-events:none!important;}'
          + '#grok-app-root aside[aria-label="Right pane"]'
          + '{padding-top:var(--grock-titlebar)!important;box-sizing:border-box!important;}';
      }

      function signedOutCSS() {
        // Google's one-tap card floats in the titlebar's corner on the
        // signed-out page. Sign in opens grok.com's own dialog, which offers
        // Google along with everything else.
        return '#credential_picker_container{display:none!important;}';
      }

      function lightboxCSS() {
        // The media viewer (Library, images in a chat) covers the whole
        // window and puts Copy, Save, and Close in the corner where the
        // titlebar's buttons are. Start it below the bar so they can be hit;
        // Close is the only way out of it.
        return '[role="presentation"]:has(> [role="dialog"] button[aria-label="Close lightbox"])'
          + '{top:var(--grock-titlebar)!important;}';
      }

      function sessionMenuCSS() {
        // The titlebar reads and picks from Conversation Actions, so that
        // menu opens out of sight and stays that way until it closes. Add to
        // Project hands its picker to the user, pinned under the titlebar
        // because its anchor is hidden.
        return 'html[data-grock-picking-menu] [role="menu"]:not([data-nested]),'
          + '[data-grock-session-menu]{opacity:0!important;pointer-events:none!important;}'
          + '[data-grock-project-popover]{position:fixed!important;top:calc(var(--grock-titlebar) + 8px)!important;'
          + 'right:12px!important;left:auto!important;bottom:auto!important;transform:none!important;'
          + 'max-height:calc(100vh - var(--grock-titlebar) - 20px)!important;}';
      }

      function sidebarHideCSS() {
        // The sidebar is full labels or gone. Its wrapper is sized by the
        // sidebar, so both go and the main column takes the width.
        // The titlebar parks its toggle on the sidebar's edge, so the width
        // stays at grok.com's default: the resize handle is muted.
        return 'html[data-grock-sidebar-hidden] ' + SIDEBAR + ','
          + 'html[data-grock-sidebar-hidden] #grok-app-root > div:has(> ' + SIDEBAR + ')'
          + '{display:none!important;}'
          + '[role="separator"][aria-controls="app-sidebar"]'
          + '{pointer-events:none!important;cursor:default!important;}';
      }

      function preferenceCSS() {
        var css = '';
        if (config.hideGrokBot) css += SIDEBAR + ' [data-reorder-item="bots"]{display:none!important;}';
        if (config.hideProjects) css += SIDEBAR + ' [data-reorder-item="projects"]{display:none!important;}';
        if (config.hidePlugins) css += SIDEBAR + ' button[aria-label="Connect apps"]{display:none!important;}';
        if (config.hidePrivate) {
          css += scoped('', PAGE_HEADER, ' button[aria-label*="Private"]')
            + '{visibility:hidden!important;pointer-events:none!important;}';
        }
        // Voice mode and Send share a slot; only the voice control goes.
        if (config.hideDictation) css += 'form[data-composer] button[aria-label^="Dictat"]{display:none!important;}';
        if (config.hideVoice) {
          css += 'form[data-composer] button[data-composer-action="voice"],'
            + 'form[data-composer] button[aria-label="Voice mode"]{display:none!important;}';
        }
        return css;
      }

      function norm(value) {
        return String(value || '').replace(/\\s+/g, ' ').trim();
      }

      function labelOf(el) {
        if (!el) return '';
        return norm(el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent);
      }

      function isShown(el) {
        if (!el || !el.isConnected) return false;
        var style = window.getComputedStyle(el);
        return !!style && style.display !== 'none';
      }

      function mark(el) {
        if (el && !el.hasAttribute(ATTR)) el.setAttribute(ATTR, '1');
      }

      function clearMarks() {
        var nodes = document.querySelectorAll('[' + ATTR + ']');
        for (var i = 0; i < nodes.length; i++) nodes[i].removeAttribute(ATTR);
      }

      // A sidebar row is a button around a label. Hide the wrapper that holds
      // only that row, so its padding goes with it.
      function rowBox(button) {
        var el = button;
        var sidebar = document.querySelector(SIDEBAR);
        while (el.parentElement && el.parentElement !== sidebar
            && el.parentElement.childElementCount === 1
            && !el.parentElement.hasAttribute('data-slot')) {
          el = el.parentElement;
        }
        return el;
      }

      function markNav() {
        var active = ROWS.filter(function (row) { return config[row.key]; });
        if (!active.length) return;
        var sidebar = document.querySelector(SIDEBAR);
        if (!sidebar) return;
        var labels = sidebar.querySelectorAll('[data-sidebar-item-label]');
        for (var i = 0; i < labels.length; i++) {
          var text = norm(labels[i].textContent);
          var button = labels[i].closest('button, a');
          if (!button || button.closest('[data-reorder-item]') || button.closest('[' + ATTR + ']')) continue;
          for (var j = 0; j < active.length; j++) {
            if (text === active[j].text) mark(rowBox(button));
          }
        }
      }

      function sidebarToggle() {
        var direct = document.querySelector('button[aria-controls="app-sidebar"][aria-expanded]');
        if (direct) return direct;
        var nodes = document.querySelectorAll('[data-leading-chrome] button');
        for (var i = 0; i < nodes.length; i++) {
          if (/sidebar/i.test(labelOf(nodes[i]))) return nodes[i];
        }
        return null;
      }

      // grok.com can close its sidebar on its own (its shortcut, or the
      // resize handle dragged shut). The titlebar button is the control here:
      // when it says shown, the sidebar is open.
      var expandLock = false;
      function keepSidebarExpanded() {
        if (config.sidebarHidden || expandLock) return;
        var toggle = sidebarToggle();
        if (!toggle || toggle.getAttribute('aria-expanded') !== 'false') return;
        expandLock = true;
        toggle.click();
        setTimeout(function () { expandLock = false; }, 400);
      }

      function contentRoot() {
        return document.getElementById('grok-content-area') || document.querySelector('main');
      }

      function pageHeader() {
        var root = contentRoot();
        if (!root) return null;
        try {
          return root.querySelector(PAGE_HEADER_PARTS);
        } catch (err) {
          return root.querySelector('header');
        }
      }

      function isSignInLabel(el) {
        var label = labelOf(el).toLowerCase();
        return label === 'sign in' || label.indexOf('sign in ') === 0
          || label === 'log in' || label.indexOf('log in ') === 0;
      }

      function findSignIn(root) {
        if (!root) return null;
        var nodes = root.querySelectorAll('a, button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          if (isSignInLabel(nodes[i])) return nodes[i];
        }
        return null;
      }

      // Signed out, the band is the way in, so it is never hidden. Look in
      // every piece of shell chrome before calling the page signed in; a
      // thread that happens to say "Sign in" is not chrome.
      function findLoggedOutSignIn() {
        var hit = findSignIn(pageHeader()) || findSignIn(document.querySelector(SIDEBAR));
        if (hit) return hit;
        var chrome = document.querySelectorAll('#grok-app-root header, #grok-app-root nav, [data-leading-chrome]');
        for (var i = 0; i < chrome.length; i++) {
          if (chrome[i].closest('[data-testid="chat-transcript-scroller"]')) continue;
          hit = findSignIn(chrome[i]);
          if (hit) return hit;
        }
        return null;
      }

      // Signed out, the only thing to do here is sign in. The logo, Settings,
      // and Sign up in the band go; an account is made in a browser.
      function markSignedOutBand() {
        var header = pageHeader();
        var signIn = findSignIn(header);
        if (!signIn) return;
        var nodes = header.querySelectorAll('a, button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (el === signIn || el.contains(signIn) || signIn.contains(el)) continue;
          mark(el);
        }
      }

      function shouldHidePageHeader() {
        return config.hidePrivate && !findSignIn(pageHeader());
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
        if (el.closest('[role="dialog"], [role="alertdialog"], [role="menu"], [role="listbox"]')) return true;
        if (el.closest(SIDEBAR + ', nav, aside')) return true;
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
        if (t === 'Add' || t === 'Enable' || t === 'See plans') return true;
        return /^(try|upgrade)\\b/i.test(t);
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

      // A dismissible card floating in a corner of the window, not centered
      // and not a sheet. The New Chat subscription card is one of these.
      function looksLikePromoCard(card) {
        if (!card || isProtectedPromoHost(card)) return false;
        if (forbiddenPromoText(card.textContent)) return false;
        if (!hasPromoSignal(card)) return false;
        var r = card.getBoundingClientRect();
        var vw = window.innerWidth || 1;
        var vh = window.innerHeight || 1;
        if (r.width < 180 || r.width > 480) return false;
        if (r.height < 80 || r.height > 640) return false;
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

      function promoCardFor(dismiss) {
        var card = dismiss.closest('[data-slot="card"]');
        if (card) return card;
        var el = dismiss.parentElement;
        var guard = 0;
        while (el && el !== document.body && guard++ < 16) {
          var position = window.getComputedStyle(el).position;
          if (position === 'fixed' || position === 'absolute') return el;
          el = el.parentElement;
        }
        return null;
      }

      function markPromos() {
        var nodes = document.querySelectorAll('button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          var btn = nodes[i];
          if (!isDismissControl(btn) || isProtectedPromoHost(btn)) continue;
          if (btn.closest('[' + ATTR + ']')) continue;
          var card = promoCardFor(btn);
          if (looksLikePromoCard(card)) mark(card);
        }
      }

      // Conversation actions (DEC-055). grok.com has one Conversation Actions
      // menu on a chat (Share, Pin, Add to Project, Archive, …) and a right
      // pane toggle. The titlebar shows native copies and clicks the originals.
      var lastSessionPosted = '';

      function isConversationPath() {
        return /^\\/c\\/[A-Za-z0-9_-]+/.test(String(location.pathname || ''));
      }

      function sessionTrigger() {
        if (!isConversationPath()) return null;
        var header = pageHeader();
        if (!header) return null;
        var direct = header.querySelector('[data-testid="conversation-actions-trigger"]');
        if (direct) return direct;
        var nodes = header.querySelectorAll('button[aria-haspopup="menu"]');
        for (var i = 0; i < nodes.length; i++) {
          if (/^(conversation actions|more|more options|options)$/i.test(labelOf(nodes[i]))) return nodes[i];
        }
        return null;
      }

      // A closed pane stays in the DOM, inert, with its Hide button inside.
      function paneToggle() {
        var nodes = document.querySelectorAll(PANE_TOGGLE);
        for (var i = 0; i < nodes.length; i++) {
          if (isShown(nodes[i]) && !nodes[i].closest('[inert], [aria-hidden="true"]')) return nodes[i];
        }
        return null;
      }

      function controlEnabled(button) {
        return !!button && !button.disabled && button.getAttribute('aria-disabled') !== 'true'
          && button.getAttribute('aria-busy') !== 'true';
      }

      function authenticationStateFromDom() {
        if (!contentRoot()) return null;
        // The account row is proof of a session. Check it first: a chat or
        // project the user named "Sign in …" is a sidebar button too.
        if (document.querySelector(SIDEBAR + ' [data-account-trigger]')) return true;
        if (findLoggedOutSignIn()) return false;
        // React may not have mounted the logged-out controls yet. Keep native
        // controls disabled until the finished document can answer.
        if (document.readyState !== 'complete') return null;
        return true;
      }

      function sessionStateFromDom() {
        var more = controlEnabled(sessionTrigger());
        return {
          more: more,
          // Share is an item in that menu now, so it comes and goes with it.
          share: more,
          panel: isConversationPath() && !!paneToggle(),
          authenticated: authenticationStateFromDom()
        };
      }

      function postSessionState() {
        var state = sessionStateFromDom();
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

      function isClosed(node) {
        return !!node.closest('[data-closed], [data-state="closed"], [aria-hidden="true"]');
      }

      function findSessionMenu(more) {
        if (!more || !more.isConnected) return null;
        var controlled = more.getAttribute('aria-controls');
        var menus = document.querySelectorAll('[role="menu"]');
        for (var i = 0; i < menus.length; i++) {
          var menu = menus[i];
          var labelledBy = (menu.getAttribute('aria-labelledby') || '').split(/\\s+/);
          if (!(controlled && menu.id === controlled) && !(more.id && labelledBy.indexOf(more.id) !== -1)) continue;
          if (isClosed(menu)) continue;
          var style = window.getComputedStyle(menu);
          if (style.display !== 'none' && style.visibility !== 'hidden') return menu;
        }
        return null;
      }

      function findSessionMenuItem(needles, more) {
        var menu = findSessionMenu(more);
        if (!menu) return null;
        var nodes = menu.querySelectorAll('[role="menuitem"], button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          if (!nodes[i].isConnected || isClosed(nodes[i])) continue;
          var style = window.getComputedStyle(nodes[i]);
          if (!style || style.display === 'none' || style.visibility === 'hidden') continue;
          var text = labelOf(nodes[i]);
          for (var n = 0; n < needles.length; n++) {
            if (needles[n].test(text)) return nodes[i];
          }
        }
        return null;
      }

      var SHARE_NEEDLES = [/^share\\b/i];
      var PIN_NEEDLES = [/^unpin\\b/i, /^pin\\b/i];
      var ARCHIVE_NEEDLES = [/^archive\\b/i];
      var PROJECT_NEEDLES = [/^(add|move) to (a )?project\\b/i];

      function openHiddenMoreMenu() {
        var more = sessionTrigger();
        if (!controlEnabled(more)) return Promise.resolve(null);
        document.documentElement.setAttribute('data-grock-picking-menu', '');
        if (!findSessionMenu(more)) more.click();
        return waitForSessionMenu(more, true).then(function () {
          var menu = findSessionMenu(more);
          if (menu && !menu.hasAttribute('data-grock-session-menu')) {
            menu.setAttribute('data-grock-session-menu', '');
          }
          return more;
        });
      }

      function waitForSessionMenu(more, opening) {
        return new Promise(function (resolve) {
          if (!more) { resolve(false); return; }
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
            attributeFilter: ['data-open', 'data-closed', 'data-state', 'aria-expanded', 'aria-hidden']
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
              // the project picker immediately after opening.
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
          '[role="menu"], [role="dialog"], [role="alertdialog"], [role="listbox"]'
        )).filter(function (node) {
          if (isClosed(node)) return false;
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
            attributeFilter: ['data-open', 'data-closed', 'data-state', 'aria-hidden', 'style']
          });
          check();
        });
      }

      // A menu is placed by the wrapper around it.
      function menuPositioner(node) {
        var parent = node.parentElement;
        if (parent && parent.getAttribute('role') === 'presentation') return parent;
        return node;
      }

      function positionProjectPicker(picker, more) {
        if (picker.getAttribute('role') !== 'menu') return;
        // The original trigger is hidden, so the menu's own placement hangs
        // off a control nobody can see. Keep the picker under the titlebar.
        menuPositioner(picker).setAttribute('data-grock-project-popover', '');
        var source = findSessionMenu(more);
        if (!source) return;
        if (source.contains(picker)) {
          source.removeAttribute('data-grock-session-menu');
          return;
        }
        // Dismissing the picker leaves its hidden parent menu open, where it
        // would swallow the next click. Close that too.
        var observer = new MutationObserver(function () {
          if (picker.isConnected && !isClosed(picker)) return;
          observer.disconnect();
          closeHiddenMoreMenu(more);
        });
        observer.observe(document.documentElement, {
          childList: true, subtree: true, attributes: true,
          attributeFilter: ['data-open', 'data-closed', 'data-state', 'aria-hidden']
        });
      }

      function openProjectPicker() {
        return withHiddenMoreMenu(function (more, handOff) {
          var hit = findSessionMenuItem(PROJECT_NEEDLES, more);
          if (!hit || hit.disabled || hit.getAttribute('aria-disabled') === 'true') return 'unavailable';
          var before = projectPickerNodes();
          if (hit.getAttribute('aria-haspopup') === 'menu') {
            // Submenus open on ArrowRight; their parent menu stays open.
            hit.focus({ preventScroll: true });
            hit.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }));
          } else {
            hit.click();
          }
          return waitForProjectPicker(before).then(function (picker) {
            if (!picker) return 'missing';
            positionProjectPicker(picker, more);
            handOff();
            return 'opened';
          });
        });
      }

      function clickSession(name) {
        if (name === 'project') return openProjectPicker();
        if (name === 'panel') {
          var pane = paneToggle();
          if (!pane) return Promise.resolve('missing');
          if (!controlEnabled(pane)) return Promise.resolve('unavailable');
          pane.click();
          return Promise.resolve('clicked');
        }
        var needles = name === 'share' ? SHARE_NEEDLES
          : (name === 'pin' ? PIN_NEEDLES : (name === 'archive' ? ARCHIVE_NEEDLES : null));
        if (!needles) return Promise.resolve('unknown');
        return withHiddenMoreMenu(function (more) {
          if (!more) return 'missing';
          var hit = findSessionMenuItem(needles, more);
          if (!hit) return 'missing';
          if (hit.getAttribute('aria-disabled') === 'true') return 'unavailable';
          hit.click();
          // Let the menu close before cleanup, so Escape cannot dismiss any
          // dialog that the selected item may have opened.
          return waitForSessionMenu(more, false).then(function () { return 'clicked'; });
        });
      }

      function inspectSessionMenu() {
        return withHiddenMoreMenu(function (more) {
          var panel = isConversationPath() && !!paneToggle();
          if (!more) return { pin: 'missing', panel: panel, project: false, archive: false };
          var pin = findSessionMenuItem(PIN_NEEDLES, more);
          var text = pin ? labelOf(pin).toLowerCase() : '';
          return {
            pin: !pin ? 'missing' : (text.indexOf('unpin') === 0 ? 'unpin' : 'pin'),
            panel: panel,
            project: !!findSessionMenuItem(PROJECT_NEEDLES, more),
            archive: !!findSessionMenuItem(ARCHIVE_NEEDLES, more)
          };
        });
      }

      function setRootFlag(name, on) {
        var root = document.documentElement;
        if (on) {
          if (!root.hasAttribute(name)) root.setAttribute(name, '');
        } else if (root.hasAttribute(name)) {
          root.removeAttribute(name);
        }
      }

      function paint(full) {
        // A full/timer paint covers the pending frame pass too. This also
        // drains deferred work when an occluded WebView stops receiving rAF.
        cancelChromeFrame();
        if (full && paintTimer) {
          clearTimeout(paintTimer);
          paintTimer = null;
        }
        // Open grok.com's sidebar while it is still hidden here, so showing
        // it does not flash an empty column first.
        keepSidebarExpanded();
        setRootFlag('data-grock-sidebar-hidden', config.sidebarHidden);
        setRootFlag('data-grock-page-header-hidden', shouldHidePageHeader());
        ensureStyle();
        if (full) clearMarks();
        markNav();
        markSignedOutBand();
        markPromos();
        postSessionState();
      }

      function apply(next) {
        merge(window.__grockChromeConfig);
        merge(next);
        paint(true);
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
        setRootFlag('data-grock-page-header-hidden', shouldHidePageHeader());
        postSessionState();
      }
      function schedule() {
        if (chromeFrame === null) chromeFrame = requestAnimationFrame(refreshChromeFrame);
        if (paintTimer) return;
        paintTimer = setTimeout(function () {
          paintTimer = null;
          paint(false);
        }, 200);
      }

      function isOwnChromeNode(el) {
        if (!el || el.nodeType !== 1) return false;
        var id = el.id || '';
        return id === STYLE_ID || id === 'grock-edge-fix';
      }

      function isComposerTree(el) {
        if (!el) return false;
        if (el.nodeType === 3) el = el.parentElement;
        if (!el || !el.closest) return false;
        return !!el.closest('[contenteditable], textarea, [role="textbox"], [data-composer-field]');
      }

      // Streaming answers add nodes many times a second and none of them is
      // chrome. Only the transcript's own subtree is skipped; its header,
      // the sidebar, and floating cards are not inside it.
      function isTranscriptTree(el) {
        if (!el) return false;
        if (el.nodeType === 3) el = el.parentElement;
        return !!(el && el.closest && el.closest('[data-testid="chat-transcript-scroller"]'));
      }

      function hasElement(list) {
        for (var i = 0; i < list.length; i++) {
          if (list[i].nodeType === 1 && !isOwnChromeNode(list[i])) return true;
        }
        return false;
      }

      var observer = new MutationObserver(function (records) {
        for (var i = 0; i < records.length; i++) {
          var r = records[i];
          if (isOwnChromeNode(r.target)) continue;
          if (r.type === 'attributes') {
            schedule();
            return;
          }
          if (isComposerTree(r.target) || isTranscriptTree(r.target)) continue;
          if (hasElement(r.addedNodes) || hasElement(r.removedNodes)) {
            schedule();
            return;
          }
        }
      });
      function watch() {
        if (!document.documentElement) return;
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          // The sidebar and pane toggles, and a busy Conversation Actions.
          attributeFilter: ['aria-expanded', 'disabled', 'aria-disabled', 'aria-busy']
        });
      }

      window.__grockChrome = {
        set: apply,
        session: sessionStateFromDom,
        clickSession: clickSession,
        inspectSessionMenu: inspectSessionMenu
      };

      merge(window.__grockChromeConfig);
      apply();
      watch();
      // Authentication stays unknown until readyState is complete. Report the
      // load explicitly instead of depending on another mutation.
      window.addEventListener('load', postSessionState, { once: true });
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () {
          apply();
        });
      }
    })();
    """
}
