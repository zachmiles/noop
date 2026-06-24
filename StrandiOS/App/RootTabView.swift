#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS navigation shell. macOS uses a `NavigationSplitView` sidebar (`RootView`); on iPhone the
/// natural analogue is a `TabView` with the most-used screens as tabs and everything else under a
/// "More" list. Every screen is the same `StrandDesign`-built view the macOS app uses.
struct RootTabView: View {
    @EnvironmentObject private var repo: Repository
    /// Cross-screen navigation requests (e.g. Live → "Manage devices"). Devices isn't a tab — it lives
    /// behind the More list — so a request presents it as a sheet, matching the quick-action screens.
    @EnvironmentObject private var router: NavRouter

    /// Which quick-action screen the centre FAB is presenting (nil = sheet closed).
    @State private var quickAction: QuickAction?
    /// Presents the Devices manager (pair / switch bands) when a screen asks the shell to open it.
    @State private var showDevices = false
    /// A routed v5 pillar screen (Insights hub / Lab Book / fused record / Rhythm) presented as a sheet
    /// when a hub row deep-links to it via NavRouter. nil = closed.
    @State private var routedPillar: NavRouter.Destination?
    /// Selected tab. Defaults to Today.
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            tab(TodayView(), "Today", "square.grid.2x2").tag(0)
            tab(TrendsView(), "Trends", "chart.line.uptrend.xyaxis").tag(1)
            tab(SleepView(), "Sleep", "bed.double").tag(2)
            moreTab.tag(3)
        }
        .tint(StrandPalette.accent)
        .task { await repo.refresh() }
        // Quick-action sheet presents with the calm easing (~0.42s) per the README sheet spec —
        // the easing is applied where `quickAction` is set (see `presentQuickAction`), keeping the
        // animation scoped to the sheet rather than the whole shell.
        .sheet(item: $quickAction) { action in
            quickActionDestination(action)
        }
        // Live's "Manage devices" affordance (and any future cross-screen link to Devices) routes here:
        // present the Devices manager in its own nav stack, the same way the quick-action screens do.
        .sheet(isPresented: $showDevices) {
            devicesScreen
        }
        // v5 pillar deep-links (Insights hub / Lab Book / fused record / Rhythm) present as a sheet in
        // their own nav stack — the same idiom the quick-action + Devices screens use on iPhone.
        .sheet(item: $routedPillar) { dest in
            pillarScreen(dest)
        }
        // Honour a router request: Devices keeps its dedicated sheet; the v5 pillars route through the
        // shared pillar sheet. Cleared so the same tap can fire again later.
        .onChange(of: router.requestedDestination) { _, dest in
            switch dest {
            case .devices:
                showDevices = true
                router.requestedDestination = nil
            case .insightsHub, .labBook, .fusedRecord, .rhythm:
                routedPillar = dest
                router.requestedDestination = nil
            case .trends:
                // Trends is a primary tab on iPhone (not a pillar sheet) — switch to it.
                selectedTab = 1
                router.requestedDestination = nil
            case nil:
                break
            }
        }
        // A screen's top-bar "+" routes here: open the quick-action sheet, then clear the flag.
        .onChange(of: router.quickActionsRequested) { _, req in
            if req {
                withAnimation(Self.sheetEase) { quickAction = .menu }
                router.quickActionsRequested = false
            }
        }
    }

    /// A routed v5 pillar screen wrapped in its own nav stack + Done button (mirrors `quickScreen`).
    @ViewBuilder
    private func pillarScreen(_ dest: NavRouter.Destination) -> some View {
        NavigationStack {
            Group {
                switch dest {
                case .insightsHub: InsightsHubView()
                case .labBook: LabBookView()
                case .fusedRecord: FusedRecordHost()
                case .rhythm: RhythmHost(onClose: { routedPillar = nil })
                case .devices: DevicesView()
                // .trends is never presented as a pillar sheet on iPhone (it's a primary tab — the
                // requestedDestination handler switches `selectedTab` instead), but the switch must stay
                // exhaustive. Fall back to Trends inside the sheet host if it ever arrives here.
                case .trends: TrendsView()
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { routedPillar = nil }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
    }

    /// Calm-easing curve (cubic-bezier(0.22,1,0.36,1)) at the README sheet-present duration.
    private static let sheetEase = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)

    // MARK: - Quick-action sheet

    /// Routes a chosen quick action to the existing screen, or shows the action menu itself.
    @ViewBuilder
    private func quickActionDestination(_ action: QuickAction) -> some View {
        switch action {
        case .menu:
            QuickActionSheet { picked in
                // Swap the menu for the chosen destination on the next runloop so the sheet
                // re-presents cleanly (avoids dismiss/re-present races). Calm easing on re-present.
                quickAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(Self.sheetEase) { quickAction = picked }
                }
            }
            .presentationDetents([.height(344)])
            .presentationDragIndicator(.hidden)
        case .live:
            quickScreen(LiveView())
        case .workout:
            quickScreen(WorkoutsView())
        case .journal:
            quickScreen(InsightsView())
        case .breathe:
            quickScreen(BreathingView())
        }
    }

    /// Wraps a routed quick-action screen in its own nav stack so it has a title bar + the
    /// shared surface background, matching how the More-tab links present these same views.
    private func quickScreen<V: View>(_ view: V) -> some View {
        NavigationStack {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { quickAction = nil }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    /// The Devices manager wrapped in its own nav stack + Done button (mirrors `quickScreen`, but
    /// dismisses the dedicated `showDevices` sheet rather than the quick-action item).
    private var devicesScreen: some View {
        NavigationStack {
            DevicesView()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDevices = false }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    private func tab<V: View>(_ view: V, _ title: LocalizedStringKey, _ icon: String) -> some View {
        // Each primary tab gets its OWN NavigationStack so the in-content NavigationLinks (e.g. the Today
        // dashboard card rows) both navigate AND render opaque. An ORPHANED NavigationLink (no
        // NavigationStack ancestor) renders its whole label in a disabled/translucent state — that was
        // washing the Today cards over the hero scene and dimming their text to grey (Aaron 2026-06-23).
        // The root view hides the system nav bar (each screen draws its own in-content header); pushed
        // detail screens get their own nav bar + back button.
        NavigationStack {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
        }
        .tabItem { Label(title, systemImage: icon) }
    }

    // The "More" tab is the app's catch-all index. Keep this as a real inset-grouped List so row press
    // highlighting, selected-row state during interactive back swipes, and section rhythm come from UIKit.
    private var moreTab: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("More")
                        .font(StrandFont.title1)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Everything else, one tap away")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NoopMetrics.screenPadding)
                .padding(.top, NoopMetrics.screenPadding)
                .padding(.bottom, NoopMetrics.gap)

                List {
                    Section("Insights") {
                        MoreRow("What Moves You", "wand.and.sparkles") { InsightsHubView() }
                        MoreRow("Intelligence", "brain.head.profile") { IntelligenceView() }
                        MoreRow("Coach", "sparkles") { CoachView() }
                        MoreRow("Insights", "lightbulb.fill") { InsightsView() }
                        MoreRow("Explore", "square.grid.2x2.fill") { MetricExplorerView() }
                        MoreRow("Compare", "rectangle.split.2x1.fill") { CompareView() }
                    }
                    Section("Body") {
                        MoreRow("Live", "waveform.path.ecg") { LiveView() }
                        MoreRow("Workouts", "figure.run") { WorkoutsView() }
                        MoreRow("Health", "heart.text.square.fill") { HealthView() }
                        MoreRow("Lab Book", "books.vertical.fill") { LabBookView() }
                        MoreRow("Stress", "bolt.heart.fill") { StressView() }
                        MoreRow("Breathe", "wind") { BreathingView() }
                        MoreRow("Intervals", "timer") { IntervalTimerView() }
                        // Experimental beat-to-beat regularity visualization — self-gates on its own consent.
                        MoreRow("Rhythm", "waveform.path") { RhythmHost() }
                    }
                    Section("Data") {
                        MoreRow("Your Data, Fused", "square.stack.3d.up.fill") { FusedRecordHost() }
                        MoreRow("Apple Health", "heart.fill") { AppleHealthView() }
                        MoreRow("Mi Band", "figure.walk.motion") { XiaomiBandView() }
                        MoreRow("Data Sources", "externaldrive.fill") { DataSourcesView() }
                        // #155: HealthKit-free Apple Health path for sideloaded installs (Siri Shortcut
                        // reads the opt-in Documents/noop_sync.txt drop file).
                        MoreRow("Shortcuts Export", "square.and.arrow.up.fill") { ShortcutExportSettingsView() }
                    }
                    Section("App") {
                        MoreRow("Automations", "wand.and.stars") { AutomationsView() }
                        MoreRow("Siri & Shortcuts", "mic.fill") { SiriShortcutsSettingsView() }
                        MoreRow("Settings", "gearshape.fill") { SettingsView() }
                        MoreRow("Support", "hands.clap.fill") { SupportView() }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
    }
}

/// One tappable destination row in the More index. It deliberately keeps the native List/NavigationLink
/// cell style so taps, selection, and interactive-pop highlights behave like a system Settings row.
private struct MoreRow<Destination: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder let destination: () -> Destination

    init(_ title: LocalizedStringKey, _ icon: String,
         @ViewBuilder _ destination: @escaping () -> Destination) {
        self.title = title; self.icon = icon; self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 26, alignment: .center)
                Text(title)
                    .font(.body)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(StrandPalette.surfaceRaised)
        .listRowSeparatorTint(StrandPalette.hairline)
    }
}

// MARK: - Quick actions (centre FAB)

/// The destinations the centre FAB can present. `.menu` is the action sheet itself; the rest
/// route to existing screens. `Identifiable` so it drives `.sheet(item:)`.
private enum QuickAction: Int, Identifiable {
    case menu, live, workout, journal, breathe
    var id: Int { rawValue }
}

/// The bottom sheet of quick actions presented by the centre FAB. Spec bottom sheet: surfaceOverlay
/// fill, gold hairline top edge, grab handle, three flat action rows that route to existing screens.
private struct QuickActionSheet: View {
    /// Called with the picked destination (the host swaps the menu for that screen).
    let onPick: (QuickAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Grab handle (36×4) in the slate hairline tone.
            Capsule()
                .fill(StrandPalette.hairlineStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("QUICK ACTIONS")
                .font(StrandFont.overline)
                .tracking(1.6)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                row("Live HR", icon: "waveform.path.ecg", tint: StrandPalette.metricRose) { onPick(.live) }
                row("Start workout", icon: "figure.run", tint: StrandPalette.effortColor) { onPick(.workout) }
                row("Log journal", icon: "square.and.pencil", tint: StrandPalette.accent) { onPick(.journal) }
                row("Breathe", icon: "wind", tint: StrandPalette.restColor) { onPick(.breathe) }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            StrandPalette.surfaceOverlay
                .overlay(alignment: .top) {
                    // Gold hairline top edge per the bottom-sheet spec.
                    Rectangle()
                        .fill(StrandPalette.gold.opacity(0.35))
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        )
    }

    /// One flat action row: hued line-icon tile + title, inset surface, hairline border.
    private func row(_ title: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(StrandPalette.surfaceInset))
                Text(title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(StrandPalette.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#endif
