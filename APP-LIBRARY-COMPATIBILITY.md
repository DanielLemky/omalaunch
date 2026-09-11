# Temporary app-library fallback

Tracking issues: [#68](https://github.com/DanielLemky/omalaunch/issues/68) and [#75](https://github.com/DanielLemky/omalaunch/issues/75).

Upstream correction: [Omarchy PR #11075](https://github.com/omacom/omarchy/pull/11075).

`LauncherAppLibrary.qml` is a temporary compatibility component. It uses the host's shared library when available and loads an independent installed app service when no shared library is available and the installed service path is valid. The fallback remains available if the host destroys the injected shell API while the menu stays loaded. A shared library takes priority and releases the fallback. Menu destruction also releases the fallback. No version check or configuration switch is required.

## Removal condition

Remove the fallback when Omalaunch's minimum supported Omarchy version includes the upstream correction, or an equivalent verified fix. An upstream merge alone is not sufficient while affected Omarchy versions remain supported. Record the first fixed release and the minimum supported version when those are known; do not guess a version now.

Before removal, test the minimum supported host and a current host. Confirm that each supplies the shared app library and that Apps, search, launch, reopening, and plugin rescan work without the fallback.

## Removal checklist

1. In `Menu.qml`, remove the `sharedAppLibrary` property and the `LauncherAppLibrary` instance. Restore the direct binding:

   ```qml
   readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
   ```

2. Delete `LauncherAppLibrary.qml`.
3. Delete only the fallback-specific tests and fixtures:
   - `tests/app-library-fallback-contract-test.js`
   - `tests/app-library-fallback-integration-test.sh`
   - `tests/app-library-fallback-harness.qml`
   - `tests/app-library-fallback-fixture.qml`
   - `tests/app-library-fallback-state.js`
4. Remove the two fallback test steps from `.github/workflows/test.yml`.
5. Remove the application-library compatibility subsection from `README.md` and delete this note.
6. Run the permanent reconciliation tests, the remaining test suite, and the host checks above.

## Keep after removal

- The timer-based `onAppLibraryChanged` reconciliation and `appRowsMergeDebounce` in `Menu.qml`. They prevent delayed work from running after menu destruction, regardless of the selected library.
- All `tests/app-library-reconciliation-*` files and their CI steps. These tests depend on `Menu.qml`, not on the fallback component or its fixtures.
- The separate icon-refresh compatibility fix and its tests, once integrated. Raw and proxy app-library APIs differ even without this workaround.

The runtime fallback code and its tests can therefore be deleted without deleting the permanent reload protection.
