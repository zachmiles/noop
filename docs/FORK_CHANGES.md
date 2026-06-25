# Fork Changes

This is the running log for Zach-specific changes in this fork. Keep it updated
whenever local behavior diverges from `NoopApp/noop` or an upstream sync requires
a decision.

## How To Add Entries

Add newest entries first. Each entry should include:

- date
- commit or working-tree status
- files touched
- reason for the local change
- upstream sync watchpoints
- validation performed

Template:

```md
## YYYY-MM-DD - Short title

- Status:
- Files:
- Reason:
- Watch during upstream syncs:
- Validation:
- Notes:
```

## 2026-06-25 - Charge naming and dashboard fallbacks

- Status: committed in this fork as
  `fd04a8c Rename Recovery to Charge and add fallbacks`.
- Files:
  - `Packages/StrandAnalytics/Sources/StrandAnalytics/RangeReport.swift`
  - `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/RangeReportTests.swift`
  - `Strand/App/AppModel.swift`
  - `Strand/Data/Repository.swift`
  - `Strand/Resources/Localizable.xcstrings`
  - `Strand/Screens/DataSourcesView.swift`
  - `Strand/Screens/MetricExplorerView.swift`
  - `Strand/Screens/TodayView.swift`
  - `Strand/Screens/TrendsView.swift`
  - `StrandiOS/App/AppToastCoordinator.swift`
  - `StrandiOS/Health/HealthKitBridge.swift`
- Reason: make Charge the user-facing name for the recovery score and add
  fallback handling so dashboard surfaces stay informative when direct Charge
  data is sparse or still calibrating.
- Watch during upstream syncs: upstream may still use Recovery labels in Trends,
  metric exploration, data-source summaries, HealthKit write copy, or toast
  strings. Preserve the internal `recovery` metric key for data compatibility,
  but keep public copy aligned to Charge / Effort / Rest.
- Validation: documentation review only for this entry; no build or test was
  rerun as part of this documentation update.
- Notes: this is a user-facing naming change, not a schema rename.

## 2026-06-25 - App-wide iOS island toast

- Status: committed in this fork as
  `98bc0b2 Add app-wide dynamic island toast`.
- Files:
  - `Strand/App/AppToastCenter.swift`
  - `Strand/Screens/IntelligenceView.swift`
  - `Strand/Screens/SleepView.swift`
  - `Strand/Screens/TodayView.swift`
  - `StrandiOS/App/AppIslandToast.swift`
  - `StrandiOS/App/AppToastCoordinator.swift`
  - `StrandiOS/App/StrandiOSApp.swift`
- Reason: replace scattered inline status banners with a shared toast center and
  iOS overlay that presents sync/success/warning/info states near the Dynamic
  Island or status bar.
- Watch during upstream syncs: upstream edits to iOS root app setup, screen-level
  banners, status-bar behavior, or notification affordances may overlap. Keep
  the shared toast center as the single status surface unless upstream provides a
  better app-wide equivalent.
- Validation: documentation review only for this entry; no build or test was
  rerun as part of this documentation update.
- Notes: the overlay is iOS-only while the toast model remains shared app state.

## 2026-06-25 - Adaptive labels and compact controls

- Status: committed in this fork as
  `5668c8b Make UI labels truncatable and adaptive`.
- Files:
  - `Packages/StrandDesign/Sources/StrandDesign/Components.swift`
  - `Strand/Resources/Localizable.xcstrings`
  - `Strand/Screens/AppleHealthView.swift`
  - `Strand/Screens/TrendsReportView.swift`
  - `Strand/Screens/TrendsView.swift`
  - `Strand/Screens/XiaomiBandView.swift`
- Reason: keep labels, captions, segmented controls, and report controls usable
  at smaller widths by allowing truncation/scaling and switching compact layouts
  with `ViewThatFits`.
- Watch during upstream syncs: upstream localization or screen layout changes
  can reintroduce wrapping/overflow. Review compact-width UI after conflicts in
  these files instead of accepting text/layout changes blindly.
- Validation: documentation review only for this entry; no build or test was
  rerun as part of this documentation update.
- Notes: this commit also refreshed Health-related localization keys.

## 2026-06-25 - Dashboard responsiveness and cache hardening

- Status: committed in this fork as
  `2404a10 Improve dashboard responsiveness`.
- Files:
  - `Packages/StrandDesign/Sources/StrandDesign/NoopMotion.swift`
  - `Packages/StrandImport/Sources/StrandImport/AppleHealthImporter.swift`
  - `Packages/WhoopStore/Sources/WhoopStore/JournalWorkoutAppleCache.swift`
  - `Packages/WhoopStore/Sources/WhoopStore/MetricSeriesStore.swift`
  - `Packages/WhoopStore/Sources/WhoopStore/MetricsCache.swift`
  - `Packages/WhoopStore/Tests/WhoopStoreTests/MetricSeriesStoreTests.swift`
  - `Packages/WhoopStore/Tests/WhoopStoreTests/MetricsCacheTests.swift`
  - `Strand/App/AppModel.swift`
  - `Strand/App/RootView.swift`
  - `Strand/BLE/SourceCoordinator.swift`
  - `Strand/Data/Repository.swift`
  - `Strand/Screens/AppleHealthView.swift`
  - `Strand/Screens/InsightsHubView.swift`
  - `Strand/Screens/InsightsView.swift`
  - `Strand/Screens/ScreenScaffold.swift`
  - `Strand/Screens/TodayView.swift`
  - `Strand/Screens/WorkoutsView.swift`
  - `StrandTests/WorkoutRowIdentityTests.swift`
  - `StrandiOS/App/StrandiOSApp.swift`
  - `StrandiOS/Health/HealthKitBridge.swift`
  - `Tools/Backfill/Sources/backfill/main.swift`
- Reason: improve dashboard and insights behavior under constrained layouts,
  harden metric/workout cache reads, and add regression coverage for metric
  series and workout-row identity.
- Watch during upstream syncs: upstream changes in repository caching, Today,
  Insights, Apple Health, BLE coordination, or shared screen scaffolding should
  be checked against the fork's responsiveness and cache behavior before merging.
- Validation: documentation review only for this entry; no build or test was
  rerun as part of this documentation update.
- Notes: treat the UI and persistence parts as related; the responsive surfaces
  depend on stable, deduplicated metric/workout data.

## 2026-06-24 - Localization catalog refresh

- Status: committed in this fork as `20df37b Update localization catalog`.
- Files:
  - `Strand/Resources/Localizable.xcstrings`
- Reason: refresh the string catalog after the Apple Health profile and dashboard
  changes.
- Watch during upstream syncs: this file is high-conflict with upstream
  localization work. Resolve structurally and preserve keys added for Health
  profile ownership, adaptive UI labels, Charge naming, and iOS toast copy.
- Validation: documentation review only for this entry; no build or test was
  rerun as part of this documentation update.
- Notes: this supersedes the earlier same-day catalog refresh where keys overlap.

## 2026-06-24 - Apple Health-owned profile measurements

- Status: committed in this fork as
  `c1d9e0e Read profile measurements from Apple Health`.
- Files:
  - `Packages/StrandImport/Sources/StrandImport/AppleHealthImporter.swift`
  - `Packages/StrandImport/Sources/StrandImport/ImportModels.swift`
  - `Packages/StrandImport/Tests/StrandImportTests/AppleHealthImporterTests.swift`
  - `Strand/App/AppModel.swift`
  - `Strand/Data/AppleHealthImport.swift`
  - `Strand/Data/Profile.swift`
  - `Strand/Onboarding/OnboardingWizard.swift`
  - `Strand/Screens/SettingsView.swift`
  - `Strand/Screens/TodayView.swift`
  - `StrandiOS/App/StrandiOSApp.swift`
  - `StrandiOS/Health/HealthKitBridge.swift`
- Reason: let Apple Health and Apple Health exports populate trusted profile
  fields such as age, sex, weight, and height, with Health-owned flags for body
  measurements that should continue to refresh from the source of truth.
- Watch during upstream syncs: upstream edits to Apple Health import models,
  HealthKit bridging, onboarding/profile copy, Settings, or Today must preserve
  the Health-backed profile flow unless Zach explicitly returns to manual-only
  profile entry.
- Validation: documentation review only for this entry; no build or test was
  rerun as part of this documentation update.
- Notes: height and weight remain locally editable only until real Health values
  arrive; after that the UI should make Health ownership clear.

## 2026-06-24 - Merge upstream v7.1/v7.2 into fork

- Status: committed on sync branch `sync/upstream-2026-06-24`.
- Files:
  - `project.yml`
  - `Packages/WhoopStore/Sources/WhoopStore/PairedDevice.swift`
  - `Strand/BLE/SourceCoordinator.swift`
  - `StrandiOS/App/StrandiOSApp.swift`
  - upstream v7.1/v7.2 release, analytics, import, UI, Apple Watch, Android,
    release-script, and localization updates
- Reason: bring this fork up to `upstream/main` at `dbc6a9d` while preserving
  Zach-specific bundle/signing configuration, Apple Foundation Models providers,
  Apple Health import/projection behavior, RENPHO scale support, and iOS UI
  polish.
- Watch during upstream syncs: conflict decisions kept both fork-local
  `.renphoScale` support and upstream `.liveAppleWatch` support; kept both the
  RENPHO Apple Health write notification and upstream WatchSession activation;
  changed upstream's new Watch bundle identifiers to the fork namespace
  (`com.zachmiles.noop.watch`, `com.zachmiles.noop.watch.complications`) and
  matched `WKCompanionAppBundleIdentifier` to `com.zachmiles.noop`.
- Validation: regenerated `Strand.xcodeproj` with `xcodegen generate`; `flowdeck
  build` passed for the saved `NOOPiOS` configuration on `Zach’s iPhone Air`.
  `flowdeck test` was attempted but is blocked because scheme `NOOPiOS` is not
  configured for the test-without-building action.
- Notes: upstream range merged is `119bd8f..dbc6a9d`; the merge also added a
  watchOS-safe palette fallback in `StrandDesign` so the new Watch target can
  compile with the fork's native surface tokens.

## 2026-06-24 - Current upstream sync snapshot

- Status: documentation snapshot after `git fetch origin --prune` and
  `git fetch upstream --prune`.
- Files:
  - `docs/FORK_CHANGES.md`
- Reason: record the current fork stack before merging newer upstream work.
- Watch during upstream syncs: `origin/main` is at `845076b`; `upstream/main`
  is at `dbc6a9d`; the merge base is `119bd8f`. Upstream now has six commits
  beyond this fork (`f1a615f`, `b6f5887`, `4135f05`, `ea3d38d`, `d28ad64`,
  `dbc6a9d`), including v7.1 and v7.2 release work.
- Validation: refreshed both remotes and compared `upstream/main..HEAD` and
  `HEAD..upstream/main`; no build or app test was run for this documentation
  update.
- Notes: expect overlap with upstream in `project.yml`, localization,
  Apple Health/import paths, BLE/source coordination, Today/Sleep/Trends UI,
  release scripts, AltStore metadata, and the new upstream Apple Watch targets.

## 2026-06-24 - Native iOS card and tab polish

- Status: committed in this fork as
  `845076b Polish native iOS card and tab chrome`.
- Files:
  - `Packages/StrandDesign/Sources/StrandDesign/Components.swift`
  - `Packages/StrandDesign/Sources/StrandDesign/Palette.swift`
  - `Packages/StrandDesign/Sources/StrandDesign/StrandCard.swift`
  - `Strand/Screens/ScreenScaffold.swift`
  - `Strand/Screens/SleepView.swift`
  - `Strand/Screens/TodayView.swift`
  - `StrandiOS/App/RootTabView.swift`
- Reason: refine native iOS card styling, shared palette usage, screen chrome,
  and root tab behavior for the fork's iOS experience.
- Watch during upstream syncs: upstream v7.1 also changes Today, Sleep, and
  shared design surfaces; upstream v7.2 changes shared design package files for
  Apple Watch support. Review UI diffs rather than auto-accepting either side.
- Validation: not rerun as part of this documentation pass.
- Notes: preserve the iOS chrome decisions unless upstream provides a better
  equivalent that Zach explicitly wants.

## 2026-06-24 - Passive RENPHO scale ingestion

- Status: committed in this fork as
  `60426ba Add passive RENPHO scale ingestion`.
- Files:
  - `Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift`
  - `Packages/WhoopStore/Tests/WhoopStoreTests/DeviceRegistryStoreTests.swift`
  - `Strand/App/AppModel.swift`
  - `Strand/BLE/RenphoScaleSource.swift`
  - `Strand/BLE/SourceCoordinator.swift`
  - `Strand/Data/DeviceRegistry.swift`
  - `Strand/Data/Repository.swift`
  - `Strand/Data/Units.swift`
  - `Strand/Resources/Localizable.xcstrings`
  - `Strand/Screens/AddDeviceWizard.swift`
  - `Strand/Screens/AppleHealthView.swift`
  - `Strand/Screens/DevicesView.swift`
  - `Strand/Screens/TodayView.swift`
  - `StrandiOS/App/StrandiOSApp.swift`
  - `StrandiOS/Health/HealthKitBridge.swift`
- Reason: continue RENPHO integration by storing discovered scale devices and
  passively ingesting weight/body-composition readings into the app data model.
- Watch during upstream syncs: upstream v7.1/v7.2 touch BLE coordination,
  device registry assumptions, HealthKit bridging, Today UI, localization, and
  `project.yml`; preserve RENPHO data paths when reconciling those files.
- Validation: not rerun as part of this documentation pass.
- Notes: this builds on the earlier explicit RENPHO BLE source commit.

## 2026-06-24 - Apple Health import progress and caching

- Status: committed in this fork as
  `9ecd78f Improve Apple Health import progress and caching`.
- Files:
  - `Packages/StrandImport/Sources/StrandImport/AppleHealthAggregator.swift`
  - `Packages/StrandImport/Sources/StrandImport/AppleHealthImporter.swift`
  - `Packages/StrandImport/Sources/StrandImport/ImportCoordinator.swift`
  - `Packages/StrandImport/Sources/StrandImport/ImportModels.swift`
  - `Packages/StrandImport/Tests/StrandImportTests/AppleHealthAggregatorTests.swift`
  - `Strand/App/AppModel.swift`
  - `Strand/Data/AppleHealthImport.swift`
  - `Strand/Resources/Localizable.xcstrings`
  - `Strand/Screens/DataSourcesView.swift`
- Reason: make Apple Health imports more transparent and efficient by improving
  progress reporting, caching, import aggregation, and the data-source surface.
- Watch during upstream syncs: upstream v7.1 changes import package code,
  localization, BLE/backfill behavior, and UI surfaces that may intersect with
  this work.
- Validation: not rerun as part of this documentation pass.
- Notes: keep the progress/caching behavior distinct from upstream CSV/import
  fixes when resolving conflicts.

## 2026-06-24 - RENPHO scale BLE source

- Status: committed in this fork as `bb1853d Add RENPHO scale BLE source`.
- Files:
  - `Packages/WhoopStore/Sources/WhoopStore/PairedDevice.swift`
  - `Strand/App/AppModel.swift`
  - `Strand/BLE/RenphoScaleSource.swift`
  - `Strand/BLE/SourceCoordinator.swift`
  - `Strand/Data/MetricCatalog.swift`
  - `Strand/Data/Repository.swift`
  - `Strand/Screens/AddDeviceWizard.swift`
  - `Strand/Screens/DevicesView.swift`
  - `Strand/Screens/MetricExplorerView.swift`
  - `Strand/Screens/TodayView.swift`
- Reason: add RENPHO scale discovery/reading as a new BLE source with matching
  device setup and metric presentation.
- Watch during upstream syncs: upstream v7.1/v7.2 change BLE coordination,
  paired-device modeling, Today UI, and project settings; keep RENPHO behavior
  unless Zach chooses to replace it.
- Validation: not rerun as part of this documentation pass.
- Notes: treat this as a fork-local hardware integration.

## 2026-06-24 - Apple Health projection and comparisons

- Status: committed in this fork as
  `87674c3 Integrate Apple Health projection and comparisons`.
- Files:
  - `Strand/App/AppModel.swift`
  - `Strand/Data/AppleHealthImport.swift`
  - `Strand/Data/Repository.swift`
  - `Strand/Screens/TodayView.swift`
- Reason: surface Apple Health-derived projections and comparisons in the app
  model, repository, and Today experience.
- Watch during upstream syncs: upstream v7.1 changes Today UI and related health
  feature surfaces; preserve fork-specific Apple Health comparison behavior when
  merging.
- Validation: not rerun as part of this documentation pass.
- Notes: this is a user-facing Today/dashboard behavior change, not just import
  plumbing.

## 2026-06-24 - Localization regeneration

- Status: committed in this fork as `5d8d498 Update Localizable.xcstrings`.
- Files:
  - `Strand/Resources/Localizable.xcstrings`
- Reason: regenerate/update the string catalog after subsequent fork changes.
- Watch during upstream syncs: upstream v7.1 also adds many localization entries;
  catalog conflicts should be resolved structurally and reviewed for lost keys.
- Validation: not rerun as part of this documentation pass.
- Notes: this supersedes or extends the earlier `75aef62` localization update.

## 2026-06-24 - Apple Foundation Models coach providers

- Status: committed in this fork as
  `79f5e27 Add Apple Foundation Models coach providers`.
- Files:
  - `Strand/AI/AICoach.swift`
  - `Strand/AI/AIProvider.swift`
  - `Strand/AI/Providers/AppleFoundationModels.swift`
  - `Strand/Resources/Strand.entitlements`
  - `Strand/Screens/CoachView.swift`
  - `StrandiOS/Resources/NOOP.entitlements`
  - `project.yml`
- Reason: add Apple Foundation Models as selectable coach providers, including
  entitlement and project configuration updates.
- Watch during upstream syncs: upstream edits to AI providers, entitlements,
  `CoachView`, or `project.yml` may need manual reconciliation. Also preserve
  availability gating if the upstream SDK target differs.
- Validation: previously build/run checked with FlowDeck during the feature
  work; not rerun as part of this documentation pass.
- Notes: this is fork-local AI provider behavior and should stay gated to
  supported Apple SDK/runtime combinations.

## 2026-06-24 - Fork maintenance workflow

- Status: committed in this fork as
  `10839d7 Document fork maintenance workflow`.
- Files:
  - `AGENTS.md`
  - `docs/FORK_MAINTENANCE.md`
  - `docs/FORK_CHANGES.md`
  - `README.md`
- Reason: establish a repeatable process for checking and merging upstream NOOP
  changes while preserving Zach-specific customizations.
- Watch during upstream syncs: documentation-only unless upstream later adds its
  own fork-maintenance guidance or `AGENTS.md`.
- Validation: documentation review only.
- Notes: future upstream syncs should update this log before the sync is treated
  as complete.

## 2026-06-24 - Localization updates

- Status: committed in this fork as
  `75aef62 Add/update translations in Localizable.xcstrings`.
- Files:
  - `Strand/Resources/Localizable.xcstrings`
- Reason: local localization fix/update.
- Watch during upstream syncs: upstream localization changes may overlap with
  this file; upstream v7.1 already changes the catalog, so review merge
  conflicts carefully instead of accepting either side wholesale.
- Validation: not rerun as part of this documentation pass.
- Notes: preserve this local localization work unless Zach explicitly replaces it
  with upstream strings. Later fork commit `5d8d498` further regenerated the
  string catalog.

## 2026-06-24 - Local bundle identifier and team configuration

- Status: committed in this fork as
  `fd8dcac Update bundle identifiers and team in project config`.
- Files:
  - `project.yml`
- Reason: local fork configuration for Zach's build/signing identity.
- Watch during upstream syncs: upstream edits to `project.yml`, especially bundle
  identifiers, signing/team settings, entitlements, target settings, or product
  names. Upstream v7.1/v7.2 now changes this file, so expect manual review.
- Validation: not rerun as part of this documentation pass.
- Notes: preserve this local configuration unless Zach explicitly asks to revert
  to upstream identifiers/signing.
