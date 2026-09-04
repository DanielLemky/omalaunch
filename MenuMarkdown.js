// A small, bounded Markdown-to-HTML parser for host-owned document rendering.
// Provider HTML is always escaped. Only http and https links become anchors.
var MAX_MARKDOWN_LENGTH = 32768
var MAX_MARKDOWN_LINES = 2048
var MAX_LINE_LENGTH = 4096

function escapeHtml(value) {
  return String(value || "").replace(/[&<>"']/g, function(character) {
    return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]
  })
}

function safeLink(value) {
  var target = String(value || "").trim()
  return /^https?:\/\/[^\s<>]+$/i.test(target) ? target : ""
}

function inlineMarkdown(value) {
  var source = String(value || "")
  var output = ""
  var index = 0
  while (index < source.length) {
    var rest = source.substring(index)
    var match = /^`([^`\n]+)`/.exec(rest)
    if (match) {
      output += "<code>" + escapeHtml(match[1]) + "</code>"
      index += match[0].length
      continue
    }
    match = /^\[([^\]\n]+)\]\(([^)\s]+)\)/.exec(rest)
    if (match) {
      var href = safeLink(match[2])
      var label = inlineMarkdown(match[1])
      output += href ? '<a href="' + escapeHtml(href) + '">' + label + "</a>" : label
      index += match[0].length
      continue
    }
    match = /^\*\*([^*\n]+)\*\*/.exec(rest) || /^__([^_\n]+)__/.exec(rest)
    if (match) {
      output += "<strong>" + inlineMarkdown(match[1]) + "</strong>"
      index += match[0].length
      continue
    }
    match = /^\*([^*\n]+)\*/.exec(rest) || /^_([^_\n]+)_/.exec(rest)
    if (match) {
      output += "<em>" + inlineMarkdown(match[1]) + "</em>"
      index += match[0].length
      continue
    }
    output += escapeHtml(source.charAt(index))
    index += 1
  }
  return output
}

function colorizeLinks(value, color) {
  var linkColor = String(color || "")
  if (!/^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(linkColor)) return String(value || "")
  return String(value || "").replace(/<a href=/g, '<a style="color: ' + linkColor + '" href=')
}

function renderMarkdown(value) {
  var source = String(value === undefined || value === null ? "" : value)
  if (source.length > MAX_MARKDOWN_LENGTH) source = source.substring(0, MAX_MARKDOWN_LENGTH)
  source = source.replace(/\r\n?/g, "\n")
  var lines = source.split("\n").slice(0, MAX_MARKDOWN_LINES).map(function(line) {
    return line.substring(0, MAX_LINE_LENGTH)
  })
  var blocks = []
  var paragraph = []
  function flushParagraph() {
    if (!paragraph.length) return
    blocks.push("<p>" + inlineMarkdown(paragraph.join("\n")).replace(/\n/g, " ") + "</p>")
    paragraph = []
  }
  for (var i = 0; i < lines.length;) {
    var line = lines[i]
    if (!line.trim()) { flushParagraph(); i += 1; continue }
    var fence = /^\s{0,3}```\s*([A-Za-z0-9_+-]*)\s*$/.exec(line)
    if (fence) {
      flushParagraph()
      var code = []
      i += 1
      while (i < lines.length && !/^\s{0,3}```\s*$/.test(lines[i])) { code.push(lines[i]); i += 1 }
      if (i < lines.length) i += 1
      var language = fence[1] ? ' class="language-' + escapeHtml(fence[1]) + '"' : ""
      blocks.push("<pre><code" + language + ">" + escapeHtml(code.join("\n")) + "</code></pre>")
      continue
    }
    var heading = /^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line)
    if (heading) {
      flushParagraph(); var level = heading[1].length
      blocks.push("<h" + level + ">" + inlineMarkdown(heading[2]) + "</h" + level + ">")
      i += 1; continue
    }
    var quote = /^\s{0,3}>\s?(.*)$/.exec(line)
    if (quote) {
      flushParagraph(); var quoteLines = []
      while (i < lines.length && (quote = /^\s{0,3}>\s?(.*)$/.exec(lines[i]))) { quoteLines.push(quote[1]); i += 1 }
      blocks.push("<blockquote>" + inlineMarkdown(quoteLines.join(" ")) + "</blockquote>")
      continue
    }
    var list = /^\s{0,3}([-+*])\s+(.+)$/.exec(line)
    var ordered = /^\s{0,3}\d+[.)]\s+(.+)$/.exec(line)
    if (list || ordered) {
      flushParagraph(); var tag = ordered ? "ol" : "ul"; var items = []
      while (i < lines.length) {
        var item = ordered ? /^\s{0,3}\d+[.)]\s+(.+)$/.exec(lines[i]) : /^\s{0,3}[-+*]\s+(.+)$/.exec(lines[i])
        if (!item) break
        items.push("<li>" + inlineMarkdown(item[1]) + "</li>"); i += 1
      }
      blocks.push("<" + tag + ">" + items.join("") + "</" + tag + ">")
      continue
    }
    paragraph.push(line); i += 1
  }
  flushParagraph()
  return blocks.join("\n")
}

// Split fenced code from prose so the host can render code in its own safe,
// scrollable surface. Prose still passes through the escaped Markdown subset.
function documentBlocks(value) {
  var source = String(value === undefined || value === null ? "" : value)
    .substring(0, MAX_MARKDOWN_LENGTH).replace(/\r\n?/g, "\n")
  var lines = source.split("\n").slice(0, MAX_MARKDOWN_LINES)
  var blocks = []
  var prose = []
  function flushProse() {
    if (!prose.length) return
    var html = renderMarkdown(prose.join("\n"))
    if (html) blocks.push({ kind: "markdown", html: html, text: "", language: "" })
    prose = []
  }
  for (var i = 0; i < lines.length;) {
    var fence = /^\s{0,3}```\s*([A-Za-z0-9_+-]*)\s*$/.exec(lines[i])
    if (!fence) { prose.push(lines[i].substring(0, MAX_LINE_LENGTH)); i += 1; continue }
    flushProse()
    var code = []
    i += 1
    while (i < lines.length && !/^\s{0,3}```\s*$/.test(lines[i])) {
      code.push(lines[i].substring(0, MAX_LINE_LENGTH)); i += 1
    }
    if (i < lines.length) i += 1
    blocks.push({ kind: "code", html: "", text: code.join("\n"), language: fence[1] || "" })
  }
  flushProse()
  return blocks
}

if (typeof module !== "undefined") module.exports = {
  escapeHtml: escapeHtml,
  safeLink: safeLink,
  inlineMarkdown: inlineMarkdown,
  colorizeLinks: colorizeLinks,
  renderMarkdown: renderMarkdown,
  documentBlocks: documentBlocks
}
