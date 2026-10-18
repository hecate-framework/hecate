/* hecate.doc theme: colour theme toggle, mobile menus, copy buttons, outline highlighting
   and client-side search. Vanilla JavaScript, no dependency; pages are fully readable
   without it. Every string shown to readers comes from the page (#doc-config), so the
   locale of the page is respected. Text from the search index is only ever inserted as
   text nodes, never as markup. */
(function () {
  "use strict";

  var root = document.documentElement;
  var config = {};
  try { config = JSON.parse(document.getElementById("doc-config").textContent); } catch (error) { config = {}; }
  var strings = config.strings || {};

  function $(selector, scope) { return (scope || document).querySelector(selector); }
  function $$(selector, scope) { return Array.prototype.slice.call((scope || document).querySelectorAll(selector)); }
  function label(key, fallback) { return strings[key] || fallback; }

  /* Colour theme ----------------------------------------------------------------------- */
  var toggle = $(".theme-toggle");
  var colourQuery = window.matchMedia("(prefers-color-scheme: dark)");

  function isDark() {
    var explicit = root.getAttribute("data-theme");
    return explicit ? explicit === "dark" : colourQuery.matches;
  }

  function updateToggle() {
    if (!toggle) return;
    toggle.setAttribute("aria-label", isDark() ? label("switch_to_light", "Switch to light theme") : label("switch_to_dark", "Switch to dark theme"));
    toggle.setAttribute("aria-pressed", isDark() ? "true" : "false");
  }

  if (toggle) {
    toggle.addEventListener("click", function () {
      var next = isDark() ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("hecate-theme", next); } catch (error) { /* ignore */ }
      updateToggle();
    });
    if (colourQuery.addEventListener) colourQuery.addEventListener("change", updateToggle);
    updateToggle();
  }

  /* Disclosure widgets: header panel, sidebar, outline ----------------------------------- */
  var panels = [];

  function register(button, panel, scrim) {
    if (!button || !panel) return;
    var entry = { button: button, panel: panel, scrim: scrim };
    panels.push(entry);
    button.setAttribute("aria-expanded", "false");
    button.addEventListener("click", function () {
      if (panel.classList.contains("is-open")) close(entry, true); else { closeAll(); open(entry); }
    });
  }

  function open(entry) {
    entry.panel.classList.add("is-open");
    if (entry.scrim) entry.scrim.classList.add("is-open");
    entry.button.setAttribute("aria-expanded", "true");
  }

  function close(entry, restoreFocus) {
    entry.panel.classList.remove("is-open");
    if (entry.scrim) entry.scrim.classList.remove("is-open");
    entry.button.setAttribute("aria-expanded", "false");
    if (restoreFocus) entry.button.focus();
  }

  function closeAll() { panels.forEach(function (entry) { close(entry, false); }); }

  register($(".menu-toggle"), $("#header-panel"));
  register($(".sidebar-toggle"), $("#sidebar"), $(".scrim"));
  register($(".outline-toggle"), $("#outline"));

  document.addEventListener("keydown", function (event) {
    if (event.key !== "Escape") return;
    var details = $(".locale-menu[open]");
    if (details) { details.removeAttribute("open"); $("summary", details).focus(); return; }
    for (var i = 0; i < panels.length; i++) {
      if (panels[i].panel.classList.contains("is-open")) { close(panels[i], true); return; }
    }
  });

  document.addEventListener("click", function (event) {
    var target = event.target;
    var details = $(".locale-menu[open]");
    if (details && !details.contains(target)) details.removeAttribute("open");
    panels.forEach(function (entry) {
      if (!entry.panel.classList.contains("is-open")) return;
      if (entry.panel.contains(target) || entry.button.contains(target)) {
        if (target.closest && target.closest("a")) close(entry, false);
        return;
      }
      close(entry, false);
    });
  });

  /* Copy buttons ----------------------------------------------------------------------- */
  var status = document.createElement("div");
  status.className = "visually-hidden";
  status.setAttribute("role", "status");
  document.body.appendChild(status);

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) return navigator.clipboard.writeText(text);
    return new Promise(function (resolve, reject) {
      var area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (error) { ok = false; }
      document.body.removeChild(area);
      if (ok) resolve(); else reject(new Error("copy failed"));
    });
  }

  $$(".code-block").forEach(function (block) {
    var toolbar = $(".code-toolbar", block);
    var code = $("pre code", block);
    if (!toolbar || !code) return;
    var button = document.createElement("button");
    button.type = "button";
    button.className = "copy-button";
    button.textContent = label("copy", "Copy");
    button.setAttribute("aria-label", label("copy_code", "Copy code"));
    var timer = null;
    button.addEventListener("click", function () {
      copyText(code.textContent).then(function () {
        button.textContent = label("copied", "Copied");
        status.textContent = label("copied", "Copied");
      }, function () {
        button.textContent = label("copy_failed", "Copy failed");
        status.textContent = label("copy_failed", "Copy failed");
      });
      clearTimeout(timer);
      timer = setTimeout(function () { button.textContent = label("copy", "Copy"); status.textContent = ""; }, 2000);
    });
    toolbar.appendChild(button);
  });

  /* Wide tables become keyboard-scrollable ---------------------------------------------- */
  $$(".table-wrap").forEach(function (wrap) {
    if (wrap.scrollWidth > wrap.clientWidth) {
      wrap.setAttribute("tabindex", "0");
      wrap.setAttribute("role", "region");
      wrap.setAttribute("aria-label", label("table", "Table"));
    }
  });

  /* Sidebar: show the current page ------------------------------------------------------ */
  var current = $(".sidebar a[aria-current='page']");
  if (current && current.scrollIntoView) {
    var sidebar = $(".sidebar");
    var offset = current.offsetTop - sidebar.clientHeight / 2;
    if (offset > 0) sidebar.scrollTop = offset;
  }

  /* Outline: mark the heading being read ------------------------------------------------- */
  var links = $$(".outline a[href^='#']");
  if (links.length) {
    var targets = links.map(function (link) {
      var id = decodeURIComponent(link.getAttribute("href").slice(1));
      return document.getElementById(id);
    });
    var ticking = false;
    var update = function () {
      ticking = false;
      var line = (parseFloat(getComputedStyle(root).scrollPaddingTop) || 80) + 8;
      var active = -1;
      for (var i = 0; i < targets.length; i++) {
        if (targets[i] && targets[i].getBoundingClientRect().top <= line) active = i;
      }
      if (active === -1 && targets[0] && window.scrollY < 8) active = -1;
      links.forEach(function (link, index) {
        if (index === active) link.setAttribute("aria-current", "location"); else link.removeAttribute("aria-current");
      });
    };
    window.addEventListener("scroll", function () {
      if (!ticking) { ticking = true; window.requestAnimationFrame(update); }
    }, { passive: true });
    window.addEventListener("resize", update);
    update();
  }

  /* Search ------------------------------------------------------------------------------ */
  var dialog = $("#search-dialog");
  var openers = $$("[data-search-open]");
  if (dialog && typeof dialog.showModal === "function" && config.index) {
    var input = $(".search-input", dialog);
    var list = $(".search-results", dialog);
    var live = $(".search-live", dialog);
    var documents = null;
    var loading = null;
    var selected = -1;
    var isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
    $$(".search-shortcut").forEach(function (node) { node.textContent = isMac ? "⌘ K" : "Ctrl K"; });

    var fold = function (text) {
      return text.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    };

    var load = function () {
      if (documents) return Promise.resolve(documents);
      if (!loading) {
        loading = fetch(config.index).then(function (response) {
          if (!response.ok) throw new Error("index " + response.status);
          return response.json();
        }).then(function (data) {
          documents = (data.documents || []).map(function (doc) {
            return { doc: doc, title: fold(doc.t || ""), heading: fold(doc.h || ""), text: fold(doc.x || "") };
          });
          return documents;
        });
      }
      return loading;
    };

    var words = function (text) { return text.split(/[^a-z0-9À-￿]+/).filter(Boolean); };

    /* A document matches when every query word is a prefix of a word of some field;
       title and heading weigh more than the text. The last word may be a partial word. */
    var score = function (entry, tokens) {
      var total = 0;
      for (var i = 0; i < tokens.length; i++) {
        var token = tokens[i];
        var best = 0;
        /* A section's page title is context, not a match of its own: it weighs less once
           the section has a heading of its own. */
        var fields = [[entry.title, entry.heading ? 4 : 12], [entry.heading, 12], [entry.text, 2]];
        for (var f = 0; f < fields.length; f++) {
          var field = fields[f][0];
          var weight = fields[f][1];
          if (!field) continue;
          var fieldWords = words(field);
          for (var w = 0; w < fieldWords.length; w++) {
            if (fieldWords[w] === token) { best = Math.max(best, weight * 1.5); break; }
            if (fieldWords[w].indexOf(token) === 0) best = Math.max(best, weight);
          }
          if (!best && token.length > 2 && field.indexOf(token) !== -1) best = Math.max(best, weight / 4);
        }
        if (!best) return 0;
        total += best;
      }
      return total;
    };

    var snippet = function (doc, tokens) {
      var text = doc.x || "";
      var folded = fold(text);
      var at = -1;
      for (var i = 0; i < tokens.length && at === -1; i++) at = folded.indexOf(tokens[i]);
      if (at === -1) return { text: text.slice(0, 120), at: -1, length: 0 };
      var start = Math.max(0, at - 40);
      var end = Math.min(text.length, at + 100);
      return { text: (start > 0 ? "…" : "") + text.slice(start, end) + (end < text.length ? "…" : ""), at: at - start + (start > 0 ? 1 : 0), length: tokens[i - 1].length };
    };

    var render = function (matches, tokens) {
      list.textContent = "";
      selected = -1;
      if (!tokens.length) {
        var hint = document.createElement("li");
        hint.className = "search-hint";
        hint.setAttribute("role", "presentation");
        hint.textContent = label("search_hint", "Type to search the documentation.");
        list.appendChild(hint);
        live.textContent = "";
        input.removeAttribute("aria-activedescendant");
        return;
      }
      if (!matches.length) {
        var empty = document.createElement("li");
        empty.className = "search-empty";
        empty.setAttribute("role", "presentation");
        empty.textContent = label("no_results", "No results for") + " “" + input.value.trim() + "”";
        list.appendChild(empty);
        live.textContent = empty.textContent;
        input.removeAttribute("aria-activedescendant");
        return;
      }
      matches.forEach(function (match, index) {
        var doc = match.doc;
        var item = document.createElement("li");
        item.className = "search-result";
        item.setAttribute("role", "presentation");
        var link = document.createElement("a");
        link.href = doc.u;
        link.id = "search-result-" + index;
        link.setAttribute("role", "option");
        link.setAttribute("aria-selected", "false");
        var title = document.createElement("span");
        title.className = "search-result-title";
        title.textContent = doc.h ? doc.h : doc.t;
        link.appendChild(title);
        if (doc.h || doc.c) {
          var path = document.createElement("span");
          path.className = "search-result-path";
          path.textContent = [doc.c, doc.h ? doc.t : ""].filter(Boolean).join(" / ");
          link.appendChild(path);
        }
        var part = snippet(doc, tokens);
        if (part.text) {
          var body = document.createElement("span");
          body.className = "search-result-snippet";
          if (part.at >= 0) {
            body.appendChild(document.createTextNode(part.text.slice(0, part.at)));
            var mark = document.createElement("mark");
            mark.textContent = part.text.slice(part.at, part.at + part.length);
            body.appendChild(mark);
            body.appendChild(document.createTextNode(part.text.slice(part.at + part.length)));
          } else {
            body.textContent = part.text;
          }
          link.appendChild(body);
        }
        item.appendChild(link);
        list.appendChild(item);
      });
      live.textContent = matches.length + " " + label("results", "results");
    };

    var search = function () {
      var tokens = words(fold(input.value));
      if (!tokens.length) { render([], tokens); return; }
      load().then(function (entries) {
        var matches = [];
        entries.forEach(function (entry) {
          var points = score(entry, tokens);
          if (points) matches.push({ doc: entry.doc, points: points });
        });
        matches.sort(function (a, b) { return b.points - a.points; });
        render(matches.slice(0, 12), tokens);
      }, function () {
        list.textContent = "";
        var failure = document.createElement("li");
        failure.className = "search-empty";
        failure.setAttribute("role", "presentation");
        failure.textContent = label("search_failed", "The search index could not be loaded.");
        list.appendChild(failure);
      });
    };

    var choose = function (index) {
      var options = $$("[role='option']", list);
      if (!options.length) return;
      if (index < 0) index = options.length - 1;
      if (index >= options.length) index = 0;
      options.forEach(function (option, i) { option.setAttribute("aria-selected", i === index ? "true" : "false"); });
      selected = index;
      input.setAttribute("aria-activedescendant", options[index].id);
      options[index].scrollIntoView({ block: "nearest" });
    };

    var show = function () {
      if (!dialog.open) dialog.showModal();
      input.focus();
      input.select();
      load();
      search();
    };

    openers.forEach(function (button) { button.addEventListener("click", show); });
    document.addEventListener("keydown", function (event) {
      var typing = /^(INPUT|TEXTAREA|SELECT)$/.test((event.target || {}).tagName || "") || (event.target && event.target.isContentEditable);
      if ((event.key === "k" || event.key === "K") && (event.ctrlKey || event.metaKey)) { event.preventDefault(); show(); }
      else if (event.key === "/" && !typing && !dialog.open && !event.ctrlKey && !event.metaKey && !event.altKey) { event.preventDefault(); show(); }
    });
    input.addEventListener("input", search);
    input.addEventListener("keydown", function (event) {
      if (event.key === "ArrowDown") { event.preventDefault(); choose(selected + 1); }
      else if (event.key === "ArrowUp") { event.preventDefault(); choose(selected - 1); }
      else if (event.key === "Escape") { event.preventDefault(); dialog.close(); }
      else if (event.key === "Enter") {
        var options = $$("[role='option']", list);
        var target = options[selected >= 0 ? selected : 0];
        if (target) { event.preventDefault(); window.location.href = target.href; }
      }
    });
    list.addEventListener("click", function (event) { if (event.target.closest && event.target.closest("a")) dialog.close(); });
    dialog.addEventListener("click", function (event) { if (event.target === dialog) dialog.close(); });
  } else {
    openers.forEach(function (button) { button.hidden = true; });
  }
})();
