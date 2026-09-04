const markdown = require('../MenuMarkdown.js')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const rendered = markdown.renderMarkdown(`# Report

A **bold** and *italic* paragraph with \`<code>\` and [docs](https://example.test/a?q=1&x=2).

- first
- second

1. one
2. two

> quoted <script>alert(1)</script>

\`\`\`js
const value = "<safe>";
\`\`\``)
assert(rendered.includes('<h1>Report</h1>'), 'headings render')
assert(rendered.includes('<strong>bold</strong>') && rendered.includes('<em>italic</em>'), 'emphasis renders')
assert(rendered.includes('<code>&lt;code&gt;</code>'), 'inline code renders escaped text')
assert(rendered.includes('<a href="https://example.test/a?q=1&amp;x=2">docs</a>'), 'HTTP links render safe escaped anchors')
const coloredLinks = markdown.colorizeLinks(rendered, '#d8dee9')
assert(coloredLinks.includes('<a style="color: #d8dee9" href="https://example.test/a?q=1&amp;x=2">docs</a>'),
  'document links receive the current foreground color')
assert(markdown.colorizeLinks(rendered, 'blue') === rendered, 'invalid link colors do not enter rich text')
assert(rendered.includes('<ul><li>first</li><li>second</li></ul>'), 'unordered lists render')
assert(rendered.includes('<ol><li>one</li><li>two</li></ol>'), 'ordered lists render')
assert(rendered.includes('<blockquote>quoted &lt;script&gt;alert(1)&lt;/script&gt;</blockquote>'), 'blockquotes escape raw HTML')
assert(rendered.includes('<pre><code class="language-js">const value = &quot;&lt;safe&gt;&quot;;</code></pre>'), 'fenced code renders with a bounded language class')
assert(!rendered.includes('<script>'), 'raw HTML never passes through')
assert(markdown.renderMarkdown('[bad](javascript:alert(1))') === '<p>bad)</p>', 'unsafe links do not become anchors')
assert(markdown.renderMarkdown('<img src=x onerror=alert(1)>').includes('&lt;img'), 'raw HTML is escaped')
assert(markdown.renderMarkdown('x'.repeat(40000)).length < 40000, 'Markdown input and lines are bounded')
const blocks = markdown.documentBlocks('Before\n\n```js\nconst value = 1;\n```\n\nAfter')
assert(blocks.length === 3 && blocks[0].kind === 'markdown' && blocks[1].kind === 'code'
  && blocks[1].language === 'js' && blocks[1].text === 'const value = 1;'
  && blocks[2].kind === 'markdown', 'document blocks separate fenced code from safe Markdown prose')
