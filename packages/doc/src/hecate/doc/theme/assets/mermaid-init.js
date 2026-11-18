/* hecate.doc theme: draws the fenced `mermaid` blocks of a page as diagrams, in the reader's
   browser, with the vendored library (./mermaid/mermaid.min.js, ADR 0033). Loaded, after the
   library, only by pages that hold a diagram. Without JavaScript, or when a diagram cannot be
   drawn, the block stays what it is: a readable code block with the diagram source.

   The source of a diagram is untrusted text. The library runs in its strict security level
   (labels are escaped and the output is sanitised) and labels are drawn as SVG text, never as
   HTML; the `secure` list stops a `%%{init}%%` directive or a front matter block of a diagram
   from changing the security level, the theme or the colours. The result is parsed as an SVG
   document and imported node by node: the script never assigns markup.

   Colours are not defined here: they are read from the custom properties of the page (the
   brand tokens of theme.css, and the site's own colour file), so the light and the dark theme
   have matching diagrams, and a diagram is drawn again when the colour theme changes.

   A drawn diagram has a toolbar (zoom in, zoom out, reset, full screen) and can be moved and zoomed: drag
   (mouse, touch), pinch, Ctrl or Cmd with the wheel (the wheel alone only in full screen), and the keys
   + - 0 and the arrows while it has focus. Full screen uses the Fullscreen API when there is one and a fixed
   overlay otherwise. Nothing is animated. */
(function () {
  "use strict";

  var root = document.documentElement;
  var config = {};
  try { config = JSON.parse(document.getElementById("doc-config").textContent); } catch (error) { config = {}; }
  var strings = config.strings || {};

  var blocks = Array.prototype.slice.call(document.querySelectorAll('.code-block[data-language="mermaid"]'));
  var holder = window.__esbuild_esm_mermaid_nm;
  var library = holder && holder.mermaid;
  if (library && library.default) library = library.default;
  if (!blocks.length || !library || typeof library.render !== "function") return;

  var styles = getComputedStyle(root);
  function token(name) { return styles.getPropertyValue(name).trim(); }

  function initialise() {
    styles = getComputedStyle(root);
    library.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      htmlLabels: false,
      flowchart: { htmlLabels: false },
      suppressErrorRendering: true,
      secure: ["secure", "securityLevel", "startOnLoad", "maxTextSize", "suppressErrorRendering", "maxEdges",
        "htmlLabels", "theme", "themeVariables", "fontFamily"],
      theme: "base",
      fontFamily: token("--sans"),
      themeVariables: {
        darkMode: root.getAttribute("data-theme") === "dark" ||
          (!root.getAttribute("data-theme") && window.matchMedia("(prefers-color-scheme: dark)").matches),
        background: token("--surface-100"),
        fontFamily: token("--sans"),
        textColor: token("--ink"),
        primaryColor: token("--surface-300"),
        primaryTextColor: token("--ink"),
        primaryBorderColor: token("--earth"),
        secondaryColor: token("--surface-200"),
        secondaryTextColor: token("--ink"),
        secondaryBorderColor: token("--border-strong"),
        tertiaryColor: token("--surface-200"),
        tertiaryTextColor: token("--ink"),
        tertiaryBorderColor: token("--border-strong"),
        lineColor: token("--ink-muted"),
        mainBkg: token("--surface-300"),
        nodeBorder: token("--earth"),
        nodeTextColor: token("--ink"),
        clusterBkg: token("--surface-200"),
        clusterBorder: token("--border-strong"),
        edgeLabelBackground: token("--surface-100"),
        titleColor: token("--ink"),
        noteBkgColor: token("--surface-200"),
        noteTextColor: token("--ink"),
        noteBorderColor: token("--border-strong"),
        actorBkg: token("--surface-300"),
        actorBorder: token("--earth"),
        actorTextColor: token("--ink"),
        actorLineColor: token("--ink-muted"),
        signalColor: token("--ink"),
        signalTextColor: token("--ink"),
        labelBoxBkgColor: token("--surface-200"),
        labelBoxBorderColor: token("--border-strong"),
        labelTextColor: token("--ink"),
        loopTextColor: token("--ink"),
        activationBkgColor: token("--surface-200"),
        activationBorderColor: token("--border-strong"),
        sequenceNumberColor: token("--on-earth"),
        errorBkgColor: token("--surface-200"),
        errorTextColor: token("--danger")
      }
    });
  }

  var entries = blocks.map(function (block) {
    var code = block.querySelector("pre code");
    return { block: block, source: code ? code.textContent : "", figure: null, notice: null };
  });
  var counter = 0;

  function parseSvg(text) {
    var parsed = new DOMParser().parseFromString(text, "image/svg+xml");
    if (parsed.getElementsByTagName("parsererror").length > 0) throw new Error("invalid SVG");
    return document.importNode(parsed.documentElement, true);
  }

  // Navigation of a drawn diagram: pan, zoom and full screen, in plain pointer, wheel and keyboard code
  // (no library, no markup assigned, no inline handler). The view is a scale and a translation applied to the SVG
  // with CSS (`transform`, origin at its top left corner); they are kept when the diagram is drawn again for a new
  // colour theme, and reset to the fit when the diagram enters or leaves full screen.
  var ICONS = {
    plus: "M12 5v14M5 12h14",
    minus: "M5 12h14",
    reset: "M4 12a8 8 0 1 0 2.5-5.8M4 4v4.5h4.5",
    expand: "M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5",
    close: "M6 6l12 12M18 6L6 18"
  };
  var MIN_SCALE = 0.2, MAX_SCALE = 10, STEP = 1.25, PAN_STEP = 48, KEEP = 48, FIT_PADDING = 32;

  // The namespace of the icons is the one of the drawn SVG (no address is written in this script).
  function icon(name, namespace) {
    var svg = document.createElementNS(namespace, "svg");
    svg.setAttribute("class", "icon");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    var path = document.createElementNS(namespace, "path");
    path.setAttribute("d", ICONS[name]);
    svg.appendChild(path);
    return svg;
  }

  function clamp(value, low, high) { return Math.min(high, Math.max(low, value)); }
  function fullscreenElement() { return document.fullscreenElement || document.webkitFullscreenElement || null; }

  function requestNative(element) {
    var request = element.requestFullscreen || element.webkitRequestFullscreen;
    if (!request) return;
    try {
      var result = request.call(element);
      if (result && result.catch) result.catch(function () {});
    } catch (error) { /* the overlay alone is the full screen */ }
  }

  function exitNative() {
    var exit = document.exitFullscreen || document.webkitExitFullscreen;
    if (!exit) return;
    try {
      var result = exit.call(document);
      if (result && result.catch) result.catch(function () {});
    } catch (error) { /* already left */ }
  }

  function anyFullscreen() {
    return entries.some(function (entry) { return entry.state && entry.state.full; });
  }

  // The untransformed box of the SVG in the viewport, measured with the transform removed and cached until the
  // layout changes (new SVG, resize, full screen).
  function measure(entry) {
    var state = entry.state;
    if (state.box) return state.box;
    var svg = entry.viewport.querySelector("svg");
    if (!svg) return { left: 0, top: 0, width: 1, height: 1, vw: 1, vh: 1 };
    var previous = svg.style.transform;
    svg.style.transform = "none";
    var frame = entry.viewport.getBoundingClientRect();
    var box = svg.getBoundingClientRect();
    svg.style.transform = previous;
    state.box = {
      left: box.left - frame.left, top: box.top - frame.top,
      width: Math.max(box.width, 1), height: Math.max(box.height, 1), vw: frame.width, vh: frame.height
    };
    return state.box;
  }

  function apply(entry) {
    var state = entry.state;
    var svg = entry.viewport.querySelector("svg");
    if (!svg) return;
    var box = measure(entry);
    // Keep a part of the diagram in view so that it cannot be lost outside the frame.
    var keepX = Math.min(KEEP, box.width * state.scale / 2), keepY = Math.min(KEEP, box.height * state.scale / 2);
    state.x = clamp(state.x, keepX - box.width * state.scale - box.left, box.vw - keepX - box.left);
    state.y = clamp(state.y, keepY - box.height * state.scale - box.top, box.vh - keepY - box.top);
    svg.style.transform = "translate(" + state.x + "px, " + state.y + "px) scale(" + state.scale + ")";
  }

  function zoomAt(entry, factor, px, py) {
    var state = entry.state, box = measure(entry);
    var scale = clamp(state.scale * factor, MIN_SCALE, MAX_SCALE);
    var ratio = scale / state.scale;
    state.x = (px - box.left) - ((px - box.left) - state.x) * ratio;
    state.y = (py - box.top) - ((py - box.top) - state.y) * ratio;
    state.scale = scale;
    apply(entry);
  }

  function zoomCentre(entry, factor) {
    var box = measure(entry);
    zoomAt(entry, factor, box.vw / 2, box.vh / 2);
  }

  // Fit: the natural layout in the page; the whole diagram centred in the frame in full screen.
  function fit(entry) {
    var state = entry.state;
    state.box = null;
    var box = measure(entry);
    if (state.full) {
      var scale = Math.min((box.vw - 2 * FIT_PADDING) / box.width, (box.vh - 2 * FIT_PADDING) / box.height);
      state.scale = clamp(scale, MIN_SCALE, MAX_SCALE);
      state.x = (box.vw - box.width * state.scale) / 2 - box.left;
      state.y = (box.vh - box.height * state.scale) / 2 - box.top;
    } else {
      state.scale = 1; state.x = 0; state.y = 0;
    }
    apply(entry);
  }

  function enter(entry) {
    var state = entry.state;
    if (state.full) return;
    entries.forEach(function (other) { if (other !== entry && other.state && other.state.full) leave(other); });
    state.full = true;
    entry.figure.classList.add("is-fullscreen");
    entry.buttons.fullscreen.hidden = true;
    entry.buttons.close.hidden = false;
    root.classList.add("diagram-fullscreen");
    requestNative(entry.figure);
    fit(entry);
    entry.viewport.focus({ preventScroll: true });
  }

  function leave(entry) {
    var state = entry.state;
    if (!state.full) return;
    state.full = false;
    entry.figure.classList.remove("is-fullscreen");
    entry.buttons.fullscreen.hidden = false;
    entry.buttons.close.hidden = true;
    if (!anyFullscreen()) root.classList.remove("diagram-fullscreen");
    if (fullscreenElement() === entry.figure) exitNative();
    fit(entry);
    entry.buttons.fullscreen.focus({ preventScroll: true });
  }

  function onFullscreenChange() {
    var element = fullscreenElement();
    entries.forEach(function (entry) {
      var state = entry.state;
      if (!state) return;
      if (element === entry.figure) {
        state.native = true;
        if (state.full) fit(entry);
      } else if (state.native) {
        state.native = false;
        if (state.full) leave(entry);
      }
    });
  }

  var resizePending = false;
  function onResize() {
    if (resizePending) return;
    resizePending = true;
    window.requestAnimationFrame(function () {
      resizePending = false;
      entries.forEach(function (entry) {
        if (!entry.state) return;
        if (entry.state.full) fit(entry);
        else { entry.state.box = null; apply(entry); }
      });
    });
  }

  function wheelDelta(event, entry) {
    var delta = event.deltaY;
    if (event.deltaMode === 1) delta *= 16;
    else if (event.deltaMode === 2) delta *= measure(entry).vh;
    return delta;
  }

  function attachPointers(entry) {
    var viewport = entry.viewport, state = entry.state;
    var pointers = new Map();
    var pinch = null;

    function pinchPoints() {
      var points = Array.from(pointers.values());
      var dx = points[1].x - points[0].x, dy = points[1].y - points[0].y;
      return { distance: Math.max(Math.hypot(dx, dy), 1), x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2 };
    }

    function end(event) {
      if (!pointers.delete(event.pointerId)) return;
      try { viewport.releasePointerCapture(event.pointerId); } catch (error) { /* not captured */ }
      pinch = pointers.size === 2 ? pinchPoints() : null;
      if (pointers.size === 0) viewport.classList.remove("is-panning");
    }

    viewport.addEventListener("pointerdown", function (event) {
      if (event.pointerType === "mouse" && event.button !== 0) return;
      var frame = viewport.getBoundingClientRect();
      pointers.set(event.pointerId, { x: event.clientX - frame.left, y: event.clientY - frame.top });
      try { viewport.setPointerCapture(event.pointerId); } catch (error) { /* not capturable */ }
      viewport.classList.add("is-panning");
      pinch = pointers.size === 2 ? pinchPoints() : null;
    });

    viewport.addEventListener("pointermove", function (event) {
      var point = pointers.get(event.pointerId);
      if (!point) return;
      var frame = viewport.getBoundingClientRect();
      var x = event.clientX - frame.left, y = event.clientY - frame.top;
      if (pointers.size === 1) {
        state.x += x - point.x;
        state.y += y - point.y;
        point.x = x; point.y = y;
        apply(entry);
      } else if (pointers.size === 2 && pinch) {
        point.x = x; point.y = y;
        var next = pinchPoints();
        state.x += next.x - pinch.x;
        state.y += next.y - pinch.y;
        zoomAt(entry, next.distance / pinch.distance, next.x, next.y);
        pinch = next;
      }
    });

    viewport.addEventListener("pointerup", end);
    viewport.addEventListener("pointercancel", end);
    viewport.addEventListener("lostpointercapture", end);

    // The wheel zooms only with Ctrl or Cmd (a trackpad pinch arrives as a Ctrl wheel) or in full screen, so
    // that scrolling the page over a diagram is never taken.
    viewport.addEventListener("wheel", function (event) {
      if (!(state.full || event.ctrlKey || event.metaKey)) return;
      event.preventDefault();
      var delta = wheelDelta(event, entry);
      var rate = event.ctrlKey && Math.abs(delta) < 50 ? 0.01 : 0.0015;
      var frame = viewport.getBoundingClientRect();
      zoomAt(entry, Math.exp(-delta * rate), event.clientX - frame.left, event.clientY - frame.top);
    }, { passive: false });
  }

  function attachKeys(entry) {
    var state = entry.state;
    entry.figure.addEventListener("keydown", function (event) {
      if (event.ctrlKey || event.metaKey || event.altKey) return;
      var handled = true;
      switch (event.key) {
        case "+": case "=": zoomCentre(entry, STEP); break;
        case "-": case "_": zoomCentre(entry, 1 / STEP); break;
        case "0": fit(entry); break;
        case "ArrowLeft": state.x += PAN_STEP; apply(entry); break;
        case "ArrowRight": state.x -= PAN_STEP; apply(entry); break;
        case "ArrowUp": state.y += PAN_STEP; apply(entry); break;
        case "ArrowDown": state.y -= PAN_STEP; apply(entry); break;
        case "Tab":
          // The overlay is modal: Tab cycles inside it.
          handled = false;
          if (state.full) {
            var stops = Array.prototype.slice.call(entry.figure.querySelectorAll("button:not([hidden]), [tabindex='0']"));
            var last = stops.length - 1;
            if (event.shiftKey && document.activeElement === stops[0]) { stops[last].focus(); handled = true; }
            else if (!event.shiftKey && document.activeElement === stops[last]) { stops[0].focus(); handled = true; }
          }
          break;
        default: handled = false;
      }
      if (handled) event.preventDefault();
    });
  }

  function button(namespace, name, key, fallback, shortcut, handler) {
    var element = document.createElement("button");
    var label = strings[key] || fallback;
    element.type = "button";
    element.className = "diagram-button";
    element.setAttribute("aria-label", label);
    element.title = label;
    if (shortcut) element.setAttribute("aria-keyshortcuts", shortcut);
    element.appendChild(icon(name, namespace));
    element.addEventListener("click", handler);
    return element;
  }

  function createFigure(entry, namespace) {
    var figure = document.createElement("figure");
    figure.className = "diagram";
    var toolbar = document.createElement("div");
    toolbar.className = "diagram-toolbar";
    toolbar.setAttribute("role", "toolbar");
    toolbar.setAttribute("aria-label", strings.diagram_controls || "Diagram controls");
    var viewport = document.createElement("div");
    viewport.className = "diagram-viewport";
    viewport.tabIndex = 0;
    viewport.setAttribute("role", "group");
    viewport.setAttribute("aria-label", strings.diagram || "Diagram");
    entry.figure = figure;
    entry.viewport = viewport;
    entry.state = { scale: 1, x: 0, y: 0, full: false, native: false, box: null };
    entry.buttons = {
      zoomIn: button(namespace, "plus", "diagram_zoom_in", "Zoom in", "+", function () { zoomCentre(entry, STEP); }),
      zoomOut: button(namespace, "minus", "diagram_zoom_out", "Zoom out", "-", function () { zoomCentre(entry, 1 / STEP); }),
      reset: button(namespace, "reset", "diagram_reset", "Reset the view", "0", function () { fit(entry); }),
      fullscreen: button(namespace, "expand", "diagram_fullscreen", "Full screen", null, function () { enter(entry); }),
      close: button(namespace, "close", "diagram_exit_fullscreen", "Exit full screen", "Escape", function () { leave(entry); })
    };
    entry.buttons.close.hidden = true;
    entry.buttons.close.classList.add("diagram-close");
    ["zoomIn", "zoomOut", "reset", "fullscreen", "close"].forEach(function (name) {
      toolbar.appendChild(entry.buttons[name]);
    });
    figure.appendChild(toolbar);
    figure.appendChild(viewport);
    attachPointers(entry);
    attachKeys(entry);
    entry.block.parentNode.insertBefore(figure, entry.block);
  }

  function show(entry, svg) {
    if (entry.notice) { entry.notice.remove(); entry.notice = null; }
    if (!entry.figure) createFigure(entry, svg.namespaceURI);
    entry.viewport.replaceChildren(svg);
    // The same source drawn in other colours has the same size: the current view stays.
    entry.state.box = null;
    apply(entry);
    entry.block.hidden = true;
  }

  function fail(entry) {
    if (entry.figure) {
      leave(entry);
      entry.figure.remove(); entry.figure = null; entry.state = null;
    }
    entry.block.hidden = false;
    if (!entry.notice) {
      entry.notice = document.createElement("p");
      entry.notice.className = "diagram-notice";
      entry.notice.setAttribute("role", "note");
      entry.notice.textContent = strings.diagram_failed || "The diagram could not be drawn; its source is shown instead.";
      entry.block.parentNode.insertBefore(entry.notice, entry.block);
    }
  }

  function draw(entry) {
    counter += 1;
    var id = "hecate-diagram-" + counter;
    return Promise.resolve()
      .then(function () { return library.render(id, entry.source); })
      .then(function (result) { show(entry, parseSvg(result.svg)); })
      .catch(function () { fail(entry); })
      .then(function () {
        var leftover = document.getElementById("d" + id);
        if (leftover) leftover.remove();
      });
  }

  var queue = Promise.resolve();
  function drawAll() {
    queue = queue.then(function () {
      initialise();
      return entries.reduce(function (previous, entry) {
        return previous.then(function () { return draw(entry); });
      }, Promise.resolve());
    });
  }

  drawAll();
  if (window.MutationObserver) {
    new MutationObserver(drawAll).observe(root, { attributes: true, attributeFilter: ["data-theme"] });
  }
  document.addEventListener("fullscreenchange", onFullscreenChange);
  document.addEventListener("webkitfullscreenchange", onFullscreenChange);
  document.addEventListener("keydown", function (event) {
    if (event.key !== "Escape" || !anyFullscreen()) return;
    entries.forEach(function (entry) { if (entry.state && entry.state.full) leave(entry); });
  });
  window.addEventListener("resize", onResize);
  var colourQuery = window.matchMedia("(prefers-color-scheme: dark)");
  if (colourQuery.addEventListener) colourQuery.addEventListener("change", drawAll);
}());
