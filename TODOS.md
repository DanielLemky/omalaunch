# TODO

## Calculation engine

- [x] Remove the temporary hand-written JavaScript expression parser before committing the calculator feature.
- [x] Use `qalc` from Arch's `libqalculate` package as the calculation engine.
- [x] Run calculations asynchronously so typing never blocks the shell UI.
- [x] Debounce requests and discard stale results when the query changes.
- [x] Support arithmetic, currencies, units, percentages, constants, and conversions through the same provider.
- [x] Display the result as the first launcher row.
- [x] Copy the result to the clipboard when the result row is activated.
- [x] Refresh exchange rates on demand for currency queries, recalculate after a successful refresh, and enforce a persistent 15-minute cooldown.
- [ ] Evaluate `dateutils` or another mature engine for date parsing and date arithmetic instead of implementing date semantics in JavaScript.

## Dependency management

- [ ] Treat `libqalculate` as a required dependency for calculator features.
- [ ] Add a dependency registry/check rather than scattering executable checks throughout QML.
- [ ] Check required dependencies when the plugin is opened for the first time.
- [ ] If dependencies are missing, show an in-launcher prompt that names the missing packages and explains why they are needed.
- [ ] Offer an explicit **Install dependencies** action from that prompt.
- [ ] Require user confirmation before installation; never install packages silently.
- [ ] Run installation in a visible terminal so authentication, package output, failures, and cancellation remain visible.
- [ ] Install packages through Omarchy's supported command, for example:
  ```sh
  omarchy pkg add libqalculate
  ```
- [ ] Include a **Not now** action that leaves the rest of the launcher usable.
- [ ] Recheck dependencies after installation and whenever the shell/plugin restarts.
- [ ] Handle missing dependencies at runtime without crashing or disabling unrelated launcher features.
- [ ] Show actionable installation instructions if a calculation is attempted while `qalc` is unavailable.
- [ ] Do not rely on plugin installation hooks: the current Omarchy plugin manifest and `omarchy plugin add` flow do not install system packages.

## Tests and CI

- [ ] Keep unit tests for request lifecycle, result parsing, ranking, and stale-result handling independent of the external process.
- [x] Add `qalc` integration tests for arithmetic, units, and representative currency queries.
- [x] Make integration tests fail clearly when `qalc` is missing; do not silently skip a required feature.
- [x] Install `libqalculate` explicitly in CI before running integration tests.
- [ ] Test missing-dependency, declined-installation, successful-installation, failed-installation, and cancelled-installation flows.
- [ ] Test that ordinary launcher searches never trigger calculator results.

## Marketplace packaging

- [x] Choose the permanent public plugin ID `omalaunch`.
- [x] Remove the development-only `omarchy.clonedFrom` field before publishing.
- [x] Add a public `README.md` with requirements, installation, usage, dependency setup, currency-rate behavior, configuration, and removal instructions.
- [x] Add a license.
- [x] Document every external dependency and privilege boundary as required by the Omarchy Plugins publishing guide.
- [x] Explain that plugins run unsandboxed and that dependency installation is always explicit.
- [ ] Add CI that runs plugin validation, JavaScript unit tests, QML linting, and `qalc` integration tests.
- [ ] Add an optional marketplace preview image after the launcher design stabilizes.
- [ ] Test clean installation, first-open setup, disable/enable, update, shell restart, and removal from a fresh user environment.
