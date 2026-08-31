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

const validMenuSnapshot = menu.parseMenuJsoncSnapshot('{"items":{"root":{"label":"Root"}}}')
assert(validMenuSnapshot.valid && validMenuSnapshot.items.length === 1, 'valid menu snapshots are identified')
assert(menu.parseMenuJsoncSnapshot('{}').valid, 'empty menu objects remain valid snapshots')
assert(!menu.parseMenuJsoncSnapshot('{"items":').valid, 'partial menu JSON is an invalid snapshot')
assert(!menu.parseMenuJsoncSnapshot('').valid, 'empty menu files are invalid snapshots')

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
const partialFilesSuggestion = menu.suggestExtensions(filesExtension, 'fil')[0]
const exactFilesSuggestion = menu.suggestExtensions(filesExtension, 'files')[0]
assert(partialFilesSuggestion.extension.id === 'files', 'file browser extensions appear in prefix suggestions')
assert(menu.extensionSuggestionPriority(partialFilesSuggestion, 'fil') === 20, 'partial extension suggestions receive low priority')
assert(menu.extensionSuggestionPriority(exactFilesSuggestion, ' FILES ') === 95, 'exact extension prefixes outrank exact app titles')
assert(menu.extensionSuggestionPriority({ extension: { available: false }, prefix: 'files' }, 'files') === 0, 'unavailable extension suggestions receive no priority boost')
assert(menu.extensionMatchPriority(filesExtension[0]) === 100, 'explicit available extension invocations receive top priority')
assert(menu.extensionMatchPriority({ available: false }) === 0, 'unavailable extension invocations receive no priority boost')
assert(filesExtension[0].copyCommand[2] === '{path}', 'file browser copy path commands are retained')
assert(filesExtension[0].copyFileCommand[1] === '{path}', 'file browser copy file commands are retained')
assert(filesExtension[0].terminalCommand[1] === '--dir={path}', 'file browser terminal commands are retained')
assert(menu.extensionRootActivation(filesExtension[0]) === 'files', 'Files root activation selects the browser')
assert(menu.isImagePath('/tmp/Photo.JPEG'), 'image paths are recognized case-insensitively')
assert(menu.isImagePath('/tmp/vector.svg'), 'SVG paths are recognized for previews')
assert(!menu.isImagePath('/tmp/photo.jpeg.txt'), 'non-image paths do not get previews')
assert(menu.localFileUrl('/tmp/My photo #1.png') === 'file:///tmp/My%20photo%20%231.png', 'local image URLs encode reserved characters')
assert(menu.localFileUrl('relative.png') === '', 'relative paths are not converted to local file URLs')
const directoryFavorite = menu.fileFavoriteId('/tmp/Projects///', 'directory', 'files')
const fileFavorite = menu.fileFavoriteId('/tmp/Projects/notes.txt', 'file', 'project-files')
assert(directoryFavorite === 'file.favorite:["files","directory","/tmp/Projects"]', 'directory favorite ids use normalized absolute paths')
assert(fileFavorite === 'file.favorite:["project-files","file","/tmp/Projects/notes.txt"]', 'file favorite ids preserve their capability and path type')
assert(menu.fileFavoritePath(directoryFavorite) === '/tmp/Projects', 'directory favorite ids recover their paths')
assert(menu.fileFavoritePath(fileFavorite) === '/tmp/Projects/notes.txt', 'file favorite ids recover their paths')
assert(menu.fileFavoriteType(directoryFavorite) === 'directory', 'directory favorite ids recover their type')
assert(menu.fileFavoriteType(fileFavorite) === 'file', 'file favorite ids recover their type')
assert(menu.fileFavoriteCapability(directoryFavorite) === 'files', 'directory favorite ids recover their capability')
assert(menu.fileFavoriteCapability(fileFavorite) === 'project-files', 'external file-browser favorite ids recover their capability')
assert(menu.legacyFileFavoriteId('/tmp/Legacy/', 'directory') === 'file.favorite.directory:/tmp/Legacy', 'legacy favorite ids can be found for migration')
assert(menu.fileFavoriteCapability('file.favorite.directory:/tmp/Legacy') === 'files', 'legacy path favorites migrate to the Files capability')
const legacyFavorite = menu.fileFavorite('file.favorite.directory:/tmp/Projects')
assert(menu.fileFavoriteId(legacyFavorite.path, legacyFavorite.type, legacyFavorite.capability) === directoryFavorite, 'legacy and current ids share one canonical favorite identity')
assert(menu.fileFavoritePath('app.example') === '', 'non-file-browser favorites do not produce paths')
assert(menu.fileFavoriteId('relative/path', 'file', 'files') === '', 'relative paths cannot become file-browser favorites')
assert(menu.fileFavoriteId('/tmp/notes.txt', 'other', 'files') === '', 'unknown path types cannot become file-browser favorites')
assert(menu.fileFavoriteId('/tmp/notes.txt', 'file', '') === '', 'path favorites require a capability')
assert(menu.fileFavorite('file.favorite:not-json') === null, 'malformed path favorites are ignored')
assert(menu.fileFavoriteLabel('/tmp/Projects/') === 'Projects', 'path favorites use their basename as a label')
assert(menu.fileFavoriteLabel('/') === '/', 'the filesystem root has a useful favorite label')
const favoriteSearchItem = menu.fileFavoriteItem('file.favorite.directory:/home/quantumfire/Downloads')
assert(favoriteSearchItem.id === menu.fileFavoriteId('/home/quantumfire/Downloads', 'directory', 'files'), 'favorite search items canonicalize legacy ids')
assert(favoriteSearchItem.label === 'Downloads' && favoriteSearchItem.action === '/home/quantumfire/Downloads', 'favorite search items retain their label and path action')
assert(menu.matchesFileFavoriteQuery(favoriteSearchItem, menu.prepareSearchQuery('downloads')), 'favorite search items match their visible labels')
assert(menu.matchesFileFavoriteQuery(favoriteSearchItem, menu.prepareSearchQuery('home quantumfire')), 'favorite search items match path components')
assert(!menu.matchesFileFavoriteQuery(favoriteSearchItem, menu.prepareSearchQuery('documents')), 'nonmatching file favorites remain hidden from search')
assert(!menu.matchesFileFavoriteQuery(favoriteSearchItem, menu.prepareSearchQuery('files')), 'favorite search ignores the hidden extension capability in canonical ids')
assert(!menu.matchesFileFavoriteQuery(favoriteSearchItem, menu.prepareSearchQuery('directory')), 'favorite search ignores the hidden path type in canonical ids')
const filesPathFavorite = menu.fileFavoriteItem(menu.fileFavoriteId('/home/quantumfire/files/Downloads', 'directory', 'files'))
assert(menu.matchesFileFavoriteQuery(filesPathFavorite, menu.prepareSearchQuery('files')), 'favorite search still matches capability-like words when they occur in the visible path')
assert(menu.fileFavoriteItem('app.example') === null, 'ordinary starred items do not become synthetic file rows')

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
  description: 'Copy calculated result',
  rootDescription: 'Open fixture calculator',
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

const bundledRootId = menu.extensionRootId(bundledFixture)
const replacementRootId = menu.extensionRootId(replacementFixture)
assert(bundledRootId === replacementRootId, 'extension root ids remain stable across capability provider replacement')
assert(menu.extensionRootCapability(bundledRootId) === 'calculator', 'extension root ids recover their capability')
assert(menu.extensionRootCapability('extension.root:not-json') === '', 'malformed extension root ids are ignored')
const replacementRootItem = menu.extensionRootItem(menu.parseExtensions(JSON.stringify([replacementFixture]))[0])
assert(replacementRootItem.id === replacementRootId && replacementRootItem.parent === 'extensions', 'extension roots are children of the fixed Extensions directory')
assert(replacementRootItem.description === 'Open fixture calculator', 'extension roots can describe activation separately from result actions')
assert(menu.extensionRootActivation(menu.parseExtensions(JSON.stringify([replacementFixture]))[0]) === 'input', 'query-only extension roots select focused input')
assert(menu.extensionRootInput(menu.parseExtensions(JSON.stringify([replacementFixture]))[0]) === '', 'query-only extension roots start with empty functional input')
assert(replacementRootItem.aliases.includes('calculator') && replacementRootItem.aliases.includes('fixture-calculator'), 'extension roots are globally searchable by stable capability and provider id')
assert(menu.matchesQuery(replacementRootItem, menu.prepareSearchQuery('calculator'), true), 'extension roots participate in global search')
const unavailableRootExtension = menu.parseExtensions(JSON.stringify([{ ...replacementFixture, _missingRequires: ['fixture-calc'] }]))[0]
const unavailableRootItem = menu.extensionRootItem(unavailableRootExtension)
assert(unavailableRootItem.description === 'Missing dependency: fixture-calc', 'unavailable extension roots remain visible with dependency detail')
assert(menu.extensionRootActivation(unavailableRootExtension) === '', 'unavailable extension roots cannot dispatch an activation')
const sortedExtensionRoots = menu.sortExtensionRootRows([
  { itemId: 'timezone', label: 'Timezone', starred: false },
  { itemId: 'currency', label: 'Currency conversion', starred: false },
  { itemId: 'files', label: 'Files', starred: true },
  { itemId: 'calculator', label: 'Calculator', starred: true }
])
assert(sortedExtensionRoots.map(row => row.itemId).join(',') === 'calculator,files,currency,timezone', 'Extensions rows sort starred first and alphabetically within each group')

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
assert(menu.extensionRootActivation(timezoneExtension[0]) === 'input' && menu.extensionRootInput(timezoneExtension[0]) === '', 'Timezone root activation starts with a clean focused input')
assert(menu.focusedExtensionQuery(timezoneExtension[0], '') === 'time', 'focused Timezone input applies its hidden prefix')
assert(menu.focusedExtensionQuery(timezoneExtension[0], 'seattle') === 'time seattle', 'focused Timezone queries apply the hidden prefix')
assert(menu.focusedExtensionQuery(timezoneExtension[0], 'time seattle') === 'time seattle', 'focused Timezone queries do not duplicate an explicit prefix')

const workflowExtensions = menu.parseExtensions(JSON.stringify([{
  schemaVersion: 1,
  id: 'codex-agent',
  capability: 'codex-agent',
  mode: 'workflow',
  label: 'Codex',
  prefixes: ['codex'],
  command: [],
  workflow: {
    items: [{
      id: 'projects', kind: 'menu', label: 'Projects', items: [
        {
          id: 'saved', kind: 'menu', label: 'Saved', context: { path: '/tmp/Saved Project' }, items: [
            {
              id: 'session', kind: 'input', label: 'New Session', prompt: 'Prompt', allowEmpty: true,
              command: ['xdg-terminal-exec', '--dir={path}', '--', 'codex', '{input}'],
              emptyCommand: ['xdg-terminal-exec', '--dir={path}', '--', 'codex']
            }
          ]
        },
        {
          id: 'add', kind: 'directoryPicker', label: 'Add Project…', next: {
            id: 'name', kind: 'input', label: 'Name project', default: '{basename}', maxLength: 120,
            command: ['helper', 'add', '{path}', '{input}'],
            next: { id: 'selected', kind: 'menu', label: '{input}', items: [] }
          }
        }
      ]
    }]
  }
}]))
assert(workflowExtensions.length === 1 && workflowExtensions[0].mode === 'workflow', 'workflow extension menus are parsed')
assert(menu.extensionRootActivation(workflowExtensions[0]) === 'workflow', 'workflow extension roots enter their host-rendered workflow')
const projectsNode = workflowExtensions[0].workflow.items[0]
assert(projectsNode.label === 'Projects' && projectsNode.items.length === 2, 'workflow navigation data retains Projects and Add Project stages')
const directoryTransition = menu.workflowDirectoryTransition(projectsNode.items[1], '/tmp/Saved Project/', {})
assert(directoryTransition.node.id === 'name' && directoryTransition.context.path === '/tmp/Saved Project' && directoryTransition.context.basename === 'Saved Project', 'directory selection transitions to naming with a basename default context')
assert(menu.workflowInterpolate(directoryTransition.node.defaultValue, directoryTransition.context) === 'Saved Project', 'project naming defaults to the selected directory basename')
const sessionNode = projectsNode.items[0].items[0]
assert(menu.workflowCommand(sessionNode, '', { path: '/tmp/Saved Project' }).join('\0') === ['xdg-terminal-exec', '--dir=/tmp/Saved Project', '--', 'codex'].join('\0'), 'empty prompts launch blank interactive Codex without an empty argument')
const hostilePrompt = 'fix $(touch /tmp/nope); echo owned'
const promptedCommand = menu.workflowCommand(sessionNode, hostilePrompt, { path: '/tmp/Saved Project' })
assert(promptedCommand.length === 5 && promptedCommand[4] === hostilePrompt, 'nonempty prompts remain one literal command argument')
assert(menu.workflowInputTransition(sessionNode, '', { path: '/tmp/Saved Project' }).context.input === '', 'empty workflow input is accepted when declared')
assert(menu.workflowClosesOnDispatch(sessionNode, promptedCommand), 'terminal workflow leaf commands close immediately after dispatch')
assert(menu.workflowClosesOnDispatch(sessionNode, ['/usr/bin/omarchy-launch-terminal', 'codex']), 'terminal workflow detection accepts absolute launcher paths')
assert(!menu.workflowClosesOnDispatch({ ...sessionNode, next: { id: 'next', kind: 'menu', label: 'Next', items: [] } }, promptedCommand), 'workflow commands with a next stage stay open')
assert(!menu.workflowClosesOnDispatch(sessionNode, ['helper', 'save']), 'non-terminal workflow commands wait for successful completion')
assert(!menu.workflowClosesOnDispatch({ ...sessionNode, allowEmpty: false }, []), 'pre-dispatch validation failures do not request closure')
assert(menu.normalizeWorkflow({ items: [{ id: 'bad', kind: 'directoryPicker', label: 'Bad' }] }) === null, 'directory picker stages require a declared next transition')

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

const providerCatalog = menu.parseExtensionCatalog(JSON.stringify({
  diagnostics: ['plugin example provider #2 timed out'],
  extensions: [
    {
      schemaVersion: 1,
      id: 'provider-first',
      label: 'First',
      prefixes: ['shared'],
      command: ['printf', 'first'],
      _source: 'plugin example provider #1'
    },
    {
      schemaVersion: 1,
      id: 'provider-first',
      label: 'Duplicate id',
      prefixes: ['other'],
      command: ['printf', 'duplicate'],
      _source: 'plugin example provider #2'
    },
    {
      schemaVersion: 1,
      id: 'provider-prefix',
      label: 'Duplicate prefix',
      prefixes: ['shared'],
      command: ['printf', 'prefix'],
      _source: 'plugin example provider #3'
    },
    {
      _source: 'plugin example provider #4'
    }
  ]
}))
assert(providerCatalog.extensions.length === 2, 'loader catalog envelopes preserve valid provider extensions')
assert(providerCatalog.diagnostics.some(message => message.indexOf('provider #2 timed out') >= 0), 'loader diagnostics pass through catalog validation')
assert(providerCatalog.diagnostics.some(message => message.indexOf("duplicate extension id 'provider-first'") >= 0 && message.indexOf('provider #2') >= 0), 'duplicate provider ids identify their source')
assert(providerCatalog.diagnostics.some(message => message.indexOf("Duplicate extension prefix 'shared'") >= 0 && message.indexOf('provider #3') >= 0), 'duplicate provider prefixes identify their source')
assert(providerCatalog.diagnostics.some(message => message.indexOf('invalid extension from plugin example provider #4') >= 0), 'invalid provider definitions identify their source')

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

const metadataItems = {
  root: menu.normalizeItem('root', { label: 'Go' }),
  tools: menu.normalizeItem('tools', { label: 'Tools' }),
  'tools.editor': menu.normalizeItem('tools.editor', {
    label: 'Text Editor',
    action: 'editor',
    aliases: ['Edit'],
    description: 'Open text files'
  }),
  hidden: menu.normalizeItem('hidden', { label: 'Hidden' }),
  'hidden.child': menu.normalizeItem('hidden.child', { label: 'Guarded', action: 'guarded', when: 'false' }),
  provider: menu.normalizeItem('provider', { label: 'Dynamic', provider: 'apps' })
}
const metadataOrder = ['root', 'tools', 'tools.editor', 'hidden', 'hidden.child', 'provider']
metadataOrder.forEach((id, index) => { metadataItems[id].order = index })
const itemMetadata = menu.buildItemMetadata(metadataItems, metadataOrder, { 'hidden.child': false })
assert(itemMetadata['tools.editor'].path === 'Tools › Text Editor', 'derived metadata caches item paths')
assert(itemMetadata['tools.editor'].parentPath === 'Tools', 'derived metadata caches parent paths')
assert(itemMetadata['tools.editor'].depth === menu.depthFor(metadataItems, 'tools.editor'), 'derived metadata caches item depth')
assert(itemMetadata.tools.childCount === 1, 'derived metadata caches direct child counts')
assert(itemMetadata.tools.visible, 'derived metadata caches visible menu descendants')
assert(!itemMetadata.hidden.visible, 'derived metadata propagates guarded descendant visibility')
assert(itemMetadata.provider.visible, 'provider-backed menus remain visible in derived metadata')
assert(menu.isDescendantOf(metadataItems, 'tools.editor', 'tools', itemMetadata), 'derived ancestry answers descendant checks')
const preparedEditorQuery = menu.prepareSearchQuery('EDIT text')
assert(menu.matchesQuery(metadataItems['tools.editor'], preparedEditorQuery, true, itemMetadata['tools.editor']), 'prepared queries use cached aliases and description words')
assert(
  menu.searchScore(metadataItems, metadataItems['tools.editor'], preparedEditorQuery, itemMetadata['tools.editor'])
    === menu.searchScore(metadataItems, metadataItems['tools.editor'], 'EDIT text'),
  'cached metadata preserves search scoring'
)
const specialWordItem = menu.normalizeItem('special', { label: 'Special', action: 'special', description: '__proto__' })
specialWordItem.order = 0
const specialWordMetadata = menu.buildItemMetadata({ special: specialWordItem }, ['special'], {}).special
assert(menu.matchesQuery(specialWordItem, menu.prepareSearchQuery('__proto__'), true, specialWordMetadata), 'cached word sets retain special object-property names')

const deepItems = { root: menu.normalizeItem('root', { label: 'Go' }) }
const deepOrder = ['root']
let deepParent = 'root'
for (let depth = 0; depth < 34; depth++) {
  const id = `deep.${depth}`
  deepItems[id] = menu.normalizeItem(id, { label: `Depth ${depth}`, parent: deepParent })
  deepItems[id].order = deepOrder.length
  deepOrder.push(id)
  deepParent = id
}
deepItems['deep.leaf'] = menu.normalizeItem('deep.leaf', { label: 'Leaf', parent: deepParent, action: 'leaf' })
deepItems['deep.leaf'].order = deepOrder.length
deepOrder.push('deep.leaf')
const deepMetadata = menu.buildItemMetadata(deepItems, deepOrder, {})
assert(deepOrder.every(id => deepMetadata[id].visible === menu.isVisible(deepItems, deepOrder, {}, deepItems[id])), 'cached visibility preserves recursion-boundary behavior')

const specialParentItems = { root: menu.normalizeItem('root', { label: 'Go' }) }
specialParentItems.constructor = menu.normalizeItem('constructor', { label: 'Constructor' })
specialParentItems['constructor.child'] = menu.normalizeItem('constructor.child', { label: 'Child', parent: 'constructor', action: 'child' })
specialParentItems['toString.child'] = menu.normalizeItem('toString.child', { label: 'String Child', parent: 'toString', action: 'child' })
specialParentItems['__proto__.child'] = menu.normalizeItem('__proto__.child', { label: 'Proto Child', parent: '__proto__', action: 'child' })
const specialParentOrder = ['root', 'constructor', 'constructor.child', 'toString.child', '__proto__.child']
specialParentOrder.forEach((id, index) => { specialParentItems[id].order = index })
const specialParentMetadata = menu.buildItemMetadata(specialParentItems, specialParentOrder, {})
assert(specialParentMetadata.constructor.childCount === 1, 'derived child maps accept inherited object-property names')
assert(specialParentMetadata['constructor.child'].ancestorSet.$constructor, 'derived ancestry accepts inherited object-property names')
assert(specialParentMetadata['toString.child'].visible && specialParentMetadata['__proto__.child'].visible, 'special parent ids do not prevent metadata construction')

assert(menu.searchMatchPriority({ kind: 'app', label: 'Apps', aliases: ['app', 'applications'] }, 'apps') === 90, 'exact app titles have highest item priority')
assert(menu.searchMatchPriority({ kind: 'app', label: 'Apple Music', aliases: [] }, 'app') === 70, 'app title prefixes outrank menu shortcuts')
assert(menu.searchMatchPriority({ kind: 'action', parent: 'apps', label: 'Work Browser', aliases: [] }, 'browser') === 60, 'whole-word titles in the Apps menu outrank exact menu shortcuts')
assert(menu.searchMatchPriority({ kind: 'app', parent: 'apps', label: 'Chromium', aliases: ['Web Browser'] }, 'browser') === 55, 'apps matched through metadata outrank management shortcuts')
assert(menu.searchMatchPriority({ kind: 'app', parent: 'tools', label: 'Chromium', aliases: ['Web Browser'] }, 'browser') === 55, 'desktop apps retain app ranking outside the Apps menu')
assert(menu.searchMatchPriority({ kind: 'app', parent: 'apps', label: 'Chromium', aliases: ['Web Browser'] }, 'calculator') === 0, 'unmatched apps receive no metadata fallback priority')
assert(menu.searchMatchPriority({ kind: 'menu', parent: 'apps', label: 'Other', aliases: ['Browser'] }, 'browser') === 40, 'submenus under Apps do not receive app ranking')
assert(menu.searchMatchPriority({ kind: 'menu', label: 'Browser', aliases: [] }, 'browser') === 50, 'exact menu titles rank below matching apps')
assert(menu.searchMatchPriority({ label: 'Utilities', aliases: ['app', 'applications'] }, 'app') === 40, 'exact aliases outrank menu title prefixes')
assert(menu.searchMatchPriority({ label: 'Apps', aliases: ['app', 'applications'] }, 'ap') === 30, 'menu title prefixes outrank alias prefixes')
assert(menu.searchMatchPriority({ label: 'Utilities', aliases: ['applications'] }, 'ap') === 10, 'alias prefixes are recognized')

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
  { matchPriority: 70, starred: false, usageCount: 0, lastUsedAt: 0, score: 20, path: 'Apple Music' },
  { matchPriority: 40, starred: true, usageCount: 10, lastUsedAt: 200, score: 0, path: 'Apps' },
  true
) > 0, 'starred aliases outrank unstarred title prefixes')

assert(menu.compareSearchRows(
  { matchPriority: 95, starred: false, usageCount: 0, lastUsedAt: 0, score: -3, path: 'Exact extension' },
  { matchPriority: 90, starred: true, usageCount: 10, lastUsedAt: 200, score: 0, path: 'Exact app' },
  true
) > 0, 'starred exact apps outrank exact extension activations')

assert(menu.compareSearchRows(
  { matchPriority: 95, starred: false, usageCount: 0, lastUsedAt: 0, score: -3, path: 'Exact extension' },
  { matchPriority: 70, starred: true, usageCount: 10, lastUsedAt: 200, score: 0, path: 'App prefix' },
  true
) > 0, 'starred app title prefixes outrank exact extension activations')

assert(menu.compareSearchRows(
  { matchPriority: 60, starred: false, usageCount: 0, lastUsedAt: 0, score: 0, path: 'App word' },
  { matchPriority: 20, starred: true, usageCount: 10, lastUsedAt: 200, score: -3, path: 'Partial extension' },
  true
) > 0, 'starred weak matches outrank unstarred app title words')

const crowdedRows = []
for (let rowIndex = 0; rowIndex < 105; rowIndex++) {
  crowdedRows.push({
    itemId: `row-${rowIndex}`,
    matchPriority: 0,
    starred: false,
    usageCount: 0,
    lastUsedAt: 0,
    score: rowIndex,
    path: `Row ${rowIndex}`
  })
}
const diagnosticRow = {
  itemId: 'extension.unavailable.test',
  matchPriority: 0,
  starred: false,
  usageCount: 0,
  lastUsedAt: 0,
  score: -3,
  path: 'Unavailable extension'
}
const cappedRows = menu.rankSearchRows(crowdedRows, [diagnosticRow], true, 100)
assert(cappedRows.length === 100, 'ranked search rows respect the result cap')
assert(cappedRows[0].itemId === 'row-0', 'highest ordinary result remains first after capping')
assert(cappedRows[98].itemId === 'row-98', 'diagnostics reserve space inside the result cap')
assert(cappedRows[99].itemId === diagnosticRow.itemId, 'unavailable extension diagnostics remain visible at the bottom')

const saturatedDiagnostics = []
for (let diagnosticIndex = 0; diagnosticIndex < 4; diagnosticIndex++) {
  saturatedDiagnostics.push({
    itemId: `diagnostic-${diagnosticIndex}`,
    matchPriority: 0,
    starred: false,
    usageCount: 0,
    lastUsedAt: 0,
    score: diagnosticIndex,
    path: `Diagnostic ${diagnosticIndex}`
  })
}
const saturatedRows = menu.rankSearchRows([
  { itemId: 'live-result', matchPriority: 110, starred: false, usageCount: 0, lastUsedAt: 0, score: -1, path: 'Live result' },
  { itemId: 'ordinary-result', matchPriority: 0, starred: false, usageCount: 0, lastUsedAt: 0, score: 0, path: 'Ordinary result' }
], saturatedDiagnostics, true, 3)
assert(saturatedRows.length === 3, 'saturated diagnostics still respect the result cap')
assert(saturatedRows[0].itemId === 'live-result', 'saturated diagnostics preserve the highest-ranked actionable result')
assert(saturatedRows.slice(1).every(row => row.itemId.indexOf('diagnostic-') === 0), 'remaining saturated slots are reserved for diagnostics')

const assembledRanking = menu.rankSearchRows([
  { itemId: 'starred-favorite', matchPriority: 30, starred: true, usageCount: 0, lastUsedAt: 0, score: 10, path: 'Starred favorite' },
  { itemId: 'partial-extension', matchPriority: 20, starred: false, usageCount: 0, lastUsedAt: 0, score: -3, path: 'Partial extension' },
  { itemId: 'exact-app', matchPriority: 90, starred: false, usageCount: 0, lastUsedAt: 0, score: 0, path: 'Exact app' },
  { itemId: 'exact-extension', matchPriority: 95, starred: false, usageCount: 0, lastUsedAt: 0, score: -3, path: 'Exact extension' },
  { itemId: 'live-result', matchPriority: 110, starred: false, usageCount: 0, lastUsedAt: 0, score: -1, path: 'Live result' }
], [], true, 100)
assert(assembledRanking.map(row => row.itemId).join(',') === 'starred-favorite,live-result,exact-extension,exact-app,partial-extension', 'assembled rows rank starred matches before extension and app priority tiers')

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
