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
   have matching diagrams, and a diagram is drawn again when the colour theme changes. */
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

  function show(entry, svg) {
    if (entry.notice) { entry.notice.remove(); entry.notice = null; }
    if (!entry.figure) {
      entry.figure = document.createElement("figure");
      entry.figure.className = "diagram";
      entry.block.parentNode.insertBefore(entry.figure, entry.block);
    }
    entry.figure.replaceChildren(svg);
    entry.block.hidden = true;
  }

  function fail(entry) {
    if (entry.figure) { entry.figure.remove(); entry.figure = null; }
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
  var colourQuery = window.matchMedia("(prefers-color-scheme: dark)");
  if (colourQuery.addEventListener) colourQuery.addEventListener("change", drawAll);
}());
