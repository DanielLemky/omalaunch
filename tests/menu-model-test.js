const fs = require('fs')
const vm = require('vm')
const path = require('path')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const source = fs.readFileSync(path.join(__dirname, '..', 'MenuModel.js'), 'utf8')
const context = { module: { exports: {} } }
vm.runInNewContext(source, context)
const menu = context.module.exports

const extensions = menu.parseExtensions(JSON.stringify([{
  id: 'pi-agent',
  label: 'Pi Agent',
  prefixes: ['pi'],
  icon: 'pi-icon',
  iconFont: 'omarchy',
  description: 'Start new session',
  command: ['omarchy-launch-terminal', 'pi', '--', '{prompt}']
}]))
assert(extensions.length === 1, 'valid extension manifests are parsed')
assert(menu.parseExtensions('{bad json').length === 0, 'invalid extension manifests are ignored')
assert(menu.parseExtensions('[{"id":"missing-fields"}]').length === 0, 'incomplete extension manifests are ignored')
assert(menu.suggestExtensions(extensions, 'p')[0].prefix === 'pi', 'partial prefixes suggest extensions')
assert(menu.suggestExtensions(extensions, 'PI')[0].prefix === 'pi', 'extension suggestions ignore case')
assert(menu.suggestExtensions(extensions, 'pi explain').length === 0, 'extension suggestions stop after prompt entry begins')
assert(menu.matchExtensions(extensions, 'pi explain this code')[0].prompt === 'explain this code', 'extension prefixes extract prompts')
assert(menu.matchExtensions(extensions, 'PI   fix the tests  ')[0].prompt === 'fix the tests', 'extension matching ignores prefix case and surrounding whitespace')
assert(menu.matchExtensions(extensions, 'pi').length === 0, 'a prefix without a prompt does not match')
assert(menu.matchExtensions(extensions, 'pilot a plane').length === 0, 'extension prefixes must be standalone')

const searchTree = {
  setup: { id: 'setup', parent: 'root' },
  'setup.default': { id: 'setup.default', parent: 'setup' },
  'setup.default.agent': { id: 'setup.default.agent', parent: 'setup.default' },
  'setup.security': { id: 'setup.security', parent: 'setup' }
}
assert(menu.isSearchExcluded(searchTree, 'setup.default', ['setup.default']), 'excluded search roots are hidden')
assert(menu.isSearchExcluded(searchTree, 'setup.default.agent', ['setup.default']), 'descendants of excluded search roots are hidden')
assert(!menu.isSearchExcluded(searchTree, 'setup.security', ['setup.default']), 'sibling menu results remain searchable')

assert(menu.searchMatchPriority({ label: 'Apps', aliases: ['app', 'applications'] }, 'apps') === 4, 'exact labels have highest priority')
assert(menu.searchMatchPriority({ label: 'Apps', aliases: ['app', 'applications'] }, 'app') === 3, 'exact aliases outrank prefixes')
assert(menu.searchMatchPriority({ label: 'Apps', aliases: ['app', 'applications'] }, 'ap') === 2, 'alias prefixes outrank label prefixes')
assert(menu.searchMatchPriority({ label: 'Apple Music', aliases: [] }, 'ap') === 1, 'label prefixes are recognized')

assert(menu.compareSearchRows(
  { matchPriority: 0, starred: false, usageCount: 2, lastUsedAt: 100, score: 20, path: 'A' },
  { matchPriority: 0, starred: false, usageCount: 1, lastUsedAt: 200, score: 0, path: 'B' },
  true
) < 0, 'frequency ranks before recency and text relevance')

assert(menu.compareSearchRows(
  { matchPriority: 0, starred: false, usageCount: 2, lastUsedAt: 200, score: 20, path: 'A' },
  { matchPriority: 0, starred: false, usageCount: 2, lastUsedAt: 100, score: 0, path: 'B' },
  true
) < 0, 'recency breaks equal frequency ties')

assert(menu.compareSearchRows(
  { matchPriority: 3, starred: false, usageCount: 0, lastUsedAt: 0, score: 20, path: 'Apps' },
  { matchPriority: 1, starred: true, usageCount: 10, lastUsedAt: 200, score: 0, path: 'Apple Music' },
  true
) < 0, 'exact aliases remain ahead of learned prefix matches')

assert(menu.compareSearchRows(
  { matchPriority: 0, starred: false, usageCount: 10, lastUsedAt: 200, score: 20, path: 'A' },
  { matchPriority: 0, starred: false, usageCount: 0, lastUsedAt: 0, score: 0, path: 'B' },
  false
) > 0, 'queries shorter than three characters ignore usage history')
