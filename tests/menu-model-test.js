const fs = require('fs')
const vm = require('vm')
const path = require('path')
const os = require('os')
const childProcess = require('child_process')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const source = fs.readFileSync(path.join(__dirname, '..', 'MenuModel.js'), 'utf8')
const context = { module: { exports: {} } }
vm.runInNewContext(source, context)
const menu = context.module.exports

const extensions = menu.parseExtensions(JSON.stringify([{
  schemaVersion: 1,
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
assert(!menu.safeExtensionPattern('(a+)+$'), 'nested quantified extension regexes are rejected')
assert(!menu.safeExtensionPattern('a'.repeat(257)), 'oversized extension regexes are rejected')
assert(menu.safeExtensionPattern('^\\s*\\d+(?: km)?$'), 'ordinary extension regexes remain accepted')
assert(menu.parseExtensions(JSON.stringify([{
  schemaVersion: 1,
  id: 'unsafe-regex',
  mode: 'query',
  label: 'Unsafe',
  command: ['printf', 'x'],
  match: { all: ['(a+)+$'] }
}])).length === 0, 'extensions with unsafe regexes are ignored')
assert(menu.suggestExtensions(extensions, 'p')[0].prefix === 'pi', 'partial prefixes suggest extensions')
assert(menu.suggestExtensions(extensions, 'PI')[0].prefix === 'pi', 'extension suggestions ignore case')
assert(menu.suggestExtensions(extensions, 'pi explain').length === 0, 'extension suggestions stop after prompt entry begins')
assert(menu.matchExtensions(extensions, 'pi explain this code')[0].prompt === 'explain this code', 'extension prefixes extract prompts')
assert(menu.matchExtensions(extensions, 'PI   fix the tests  ')[0].prompt === 'fix the tests', 'extension matching ignores prefix case and surrounding whitespace')
assert(menu.matchExtensions(extensions, 'pi').length === 0, 'a prefix without a prompt does not match')
assert(menu.matchExtensions(extensions, 'pilot a plane').length === 0, 'extension prefixes must be standalone')

const filesExtension = menu.parseExtensions(JSON.stringify([{
  schemaVersion: 1,
  id: 'files',
  capability: 'files',
  mode: 'files',
  label: 'Files',
  prefixes: ['files'],
  root: '~',
  command: ['xdg-open', '{path}'],
  directoryCommand: ['xdg-open', '{path}'],
  terminalCommand: ['xdg-terminal-exec', '--dir={path}'],
  copyCommand: ['wl-copy', '--', '{path}'],
  copyFileCommand: ['copy-file', '{path}']
}]))
assert(filesExtension.length === 1 && filesExtension[0].mode === 'files', 'file browser extensions are parsed')
assert(menu.suggestExtensions(filesExtension, 'fil')[0].extension.id === 'files', 'file browser extensions appear in prefix suggestions')
assert(filesExtension[0].copyCommand[2] === '{path}', 'file browser copy path commands are retained')
assert(filesExtension[0].copyFileCommand[1] === '{path}', 'file browser copy file commands are retained')
assert(filesExtension[0].terminalCommand[1] === '--dir={path}', 'file browser terminal commands are retained')
assert(menu.isImagePath('/tmp/Photo.JPEG'), 'image paths are recognized case-insensitively')
assert(menu.isImagePath('/tmp/vector.svg'), 'SVG paths are recognized for previews')
assert(!menu.isImagePath('/tmp/photo.jpeg.txt'), 'non-image paths do not get previews')
assert(menu.localFileUrl('/tmp/My photo #1.png') === 'file:///tmp/My%20photo%20%231.png', 'local image URLs encode reserved characters')
assert(menu.localFileUrl('relative.png') === '', 'relative paths are not converted to local file URLs')

const queryExtensions = menu.parseExtensions(JSON.stringify([
  {
    schemaVersion: 1,
    id: 'bundled-calculator',
    capability: 'calculator',
    mode: 'query',
    label: 'Calculator',
    command: ['qalc', '{query}'],
    match: { all: ['^\\d'], any: ['[+]'] },
    _bundled: true
  },
  {
    schemaVersion: 1,
    id: 'replacement-calculator',
    capability: 'calculator',
    mode: 'query',
    label: 'Replacement',
    command: ['other-calc', '{query}'],
    match: { all: ['^\\d'], any: ['[+]'] },
    _bundled: false
  }
]))
assert(queryExtensions.length === 1 && queryExtensions[0].id === 'replacement-calculator', 'equal-priority external extensions replace bundled capabilities')
assert(menu.queryExtension(queryExtensions, '2+2').id === 'replacement-calculator', 'query extensions match live input')
assert(Object.prototype.toString.call(queryExtensions[0].matchAllRegex[0]) === '[object RegExp]', 'query extension regular expressions are compiled once')
assert(menu.queryExtension(queryExtensions, 'hello') === null, 'query extensions ignore unrelated input')

const replacementFixture = {
  schemaVersion: 1,
  id: 'fixture-calculator',
  capability: 'calculator',
  mode: 'query',
  label: 'Fixture',
  priority: 10,
  command: ['printf', 'fixture'],
  match: { all: ['^\\d'], any: ['[+]'] },
  _bundled: false
}
const bundledFixture = {
  schemaVersion: 1,
  id: 'bundled-fixture',
  capability: 'calculator',
  mode: 'query',
  label: 'Bundled',
  priority: 10,
  command: ['printf', 'bundled'],
  match: { all: ['^\\d'], any: ['[+]'] },
  _bundled: true
}
assert(menu.parseExtensions(JSON.stringify([bundledFixture, { ...replacementFixture, priority: 9 }]))[0].id === 'bundled-fixture', 'lower-priority external extensions do not replace bundled extensions')
assert(menu.parseExtensions(JSON.stringify([bundledFixture, { ...replacementFixture, priority: 11 }]))[0].id === 'fixture-calculator', 'higher-priority external extensions replace bundled extensions')
assert(menu.parseExtensions(JSON.stringify([bundledFixture]))[0].id === 'bundled-fixture', 'removing a replacement restores the bundled extension')
assert(menu.parseExtensions(JSON.stringify([bundledFixture, { ...replacementFixture, _missingRequires: ['fixture-calc'] }]))[0].id === 'bundled-fixture', 'unavailable replacements fall back to bundled extensions')

const bundledExtensions = menu.parseExtensions(JSON.stringify([
  { ...JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'extensions', 'calculator', 'extension.json'), 'utf8')), _bundled: true },
  { ...JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'extensions', 'currency', 'extension.json'), 'utf8')), _bundled: true }
]))
assert(menu.queryExtension(bundledExtensions, '2 + 2').capability === 'calculator', 'bundled calculator matches arithmetic')
assert(menu.queryExtension(bundledExtensions, '10 USD to CAD').capability === 'currency', 'bundled currency extension outranks general conversions')
assert(menu.queryExtension(bundledExtensions, 'hello') === null, 'bundled extensions ignore ordinary searches')

const timezoneExtension = menu.parseExtensions(JSON.stringify([{
  ...JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'extensions', 'timezone', 'extension.json'), 'utf8')),
  _bundled: true,
  _sourceDir: '/tmp/timezone'
}]))
assert(menu.suggestExtensions(timezoneExtension, 'tim')[0].prefix === 'time', 'live query extensions can suggest prefixes')
assert(menu.queryExtension(timezoneExtension, 'time seattle').capability === 'timezone', 'timezone extension matches explicit time queries')
assert(menu.queryExtension(timezoneExtension, 'timer') === null, 'timezone extension ignores unrelated searches')
assert(timezoneExtension[0].sourceDir === '/tmp/timezone', 'extension source directories are retained for bundled scripts')

const unavailableCatalog = menu.parseExtensionCatalog(JSON.stringify([
  {
    schemaVersion: 1,
    id: 'needs-tool',
    mode: 'prefix',
    label: 'Needs Tool',
    prefixes: ['needs'],
    command: ['missing-tool', '{prompt}'],
    requires: ['missing-tool'],
    _missingRequires: ['missing-tool']
  },
  {
    schemaVersion: 1,
    id: 'needs-tool',
    mode: 'prefix',
    label: 'Duplicate',
    prefixes: ['duplicate'],
    command: ['duplicate', '{prompt}']
  }
]))
assert(!unavailableCatalog.extensions[0].available, 'missing dependencies mark extensions unavailable')
assert(unavailableCatalog.diagnostics.some(message => message.indexOf('missing-tool') >= 0), 'missing dependencies produce diagnostics')
assert(unavailableCatalog.diagnostics.some(message => message.indexOf('duplicate extension id') >= 0), 'duplicate extension ids produce diagnostics')

const bundledMissingQalc = menu.parseExtensions(JSON.stringify([{
  ...JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'extensions', 'calculator', 'extension.json'), 'utf8')),
  _bundled: true,
  _missingRequires: ['qalc']
}]))[0]
const qalcSetup = menu.dependencySetup(bundledMissingQalc)
assert(qalcSetup.packageName === 'libqalculate', 'bundled qalc requirements map to libqalculate setup')
assert(qalcSetup.installCommand.join(' ') === 'omarchy pkg add libqalculate', 'dependency setup exposes the exact supported install command')
assert(menu.unavailableExtensionDetail(bundledMissingQalc).indexOf('Press Enter to install') >= 0, 'known bundled dependencies are actionable')
assert(menu.firstSetupExtension([bundledMissingQalc]) === bundledMissingQalc, 'missing bundled dependencies produce a root setup extension')
assert(menu.firstSetupExtension(bundledExtensions) === null, 'available bundled dependencies do not produce root setup')
assert(menu.dependencySetup(unavailableCatalog.extensions[0]) === null, 'external extensions cannot authorize package installation')
assert(menu.firstSetupExtension(unavailableCatalog.extensions) === null, 'external dependencies cannot produce root package setup')
assert(menu.unavailableExtensionDetail(unavailableCatalog.extensions[0]) === 'Missing dependency: missing-tool', 'unknown dependencies retain diagnostic-only messaging')

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

const marker = path.join(os.tmpdir(), `omalaunch-guard-${process.pid}`)
const hostileId = `row; touch ${marker}; #`
const guardRun = childProcess.spawnSync('bash', ['-c', menu.guardScript({
  [hostileId]: { id: hostileId, when: 'true' }
})], { encoding: 'utf8' })
assert(guardRun.status === 0, 'guard scripts remain valid for shell metacharacters in ids')
assert(guardRun.stdout.trim() === `${hostileId}:w:1`, 'guard ids round-trip without shell interpretation')
assert(!fs.existsSync(marker), 'guard ids cannot inject shell commands')
