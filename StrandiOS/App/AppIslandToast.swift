#if os(iOS)
import Combine
import SwiftUI
import UIKit
import StrandDesign

extension View {
    func appIslandToast(center: AppToastCenter) -> some View {
        modifier(AppIslandToastWindowModifier(center: center))
    }
}

private struct AppIslandToastWindowModifier: ViewModifier {
    @ObservedObject var center: AppToastCenter
    @State private var overlayWindow: AppIslandToastWindow?

    func body(content: Content) -> some View {
        content
            .background(AppWindowReader { mainWindow in
                installOverlayWindow(from: mainWindow)
            })
    }

    private func installOverlayWindow(from mainWindow: UIWindow) {
        guard overlayWindow == nil, let scene = mainWindow.windowScene else { return }

        if let existing = scene.windows.first(where: { $0.tag == AppIslandToastWindow.tag }) as? AppIslandToastWindow {
            existing.toastCenter = center
            existing.rootViewController = AppIslandToastHostingController(
                rootView: AppIslandToastOverlay(center: center),
                center: center
            )
            overlayWindow = existing
            return
        }

        let window = AppIslandToastWindow(windowScene: scene)
        window.toastCenter = center
        window.tag = AppIslandToastWindow.tag
        window.backgroundColor = .clear
        window.windowLevel = .statusBar + 1
        window.isHidden = false
        window.rootViewController = AppIslandToastHostingController(
            rootView: AppIslandToastOverlay(center: center),
            center: center
        )
        overlayWindow = window
    }
}

private struct AppWindowReader: UIViewRepresentable {
    var onResolve: (UIWindow) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class AppIslandToastWindow: UIWindow {
    static let tag = 2409
    weak var toastCenter: AppToastCenter?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event),
              let root = rootViewController?.view else {
            return nil
        }
        return hit == root ? nil : hit
    }
}

private final class AppIslandToastHostingController: UIHostingController<AppIslandToastOverlay> {
    private weak var center: AppToastCenter?
    private var cancellable: AnyCancellable?

    init(rootView: AppIslandToastOverlay, center: AppToastCenter) {
        self.center = center
        super.init(rootView: rootView)
        view.backgroundColor = .clear
        view.isOpaque = false
        cancellable = center.$hidesStatusBar.sink { [weak self] _ in
            self?.setNeedsStatusBarAppearanceUpdate()
        }
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        nil
    }

    override var prefersStatusBarHidden: Bool {
        center?.hidesStatusBar ?? false
    }
}

private struct AppIslandToastOverlay: View {
    @ObservedObject var center: AppToastCenter

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let size = proxy.size
            let hasIsland = safeTop >= 59
            ZStack(alignment: .top) {
                if let toast = center.current {
                    AppIslandToastCard(
                        toast: toast,
                        isExpanded: center.isPresented,
                        hasIsland: hasIsland,
                        availableWidth: size.width,
                        safeTop: safeTop
                    ) {
                        center.dismiss()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
        }
    }
}

private struct AppIslandToastCard: View {
    let toast: AppToast
    let isExpanded: Bool
    let hasIsland: Bool
    let availableWidth: CGFloat
    let safeTop: CGFloat
    let dismiss: () -> Void

    private var outerInset: CGFloat { 14 }
    private var collapsedWidth: CGFloat { 124 }
    private var collapsedHeight: CGFloat { 37 }
    private var expandedWidth: CGFloat { max(280, availableWidth - (outerInset * 2)) }
    private var expandedHeight: CGFloat { hasIsland ? 108 : 72 }
    private var islandTopOffset: CGFloat {
        hasIsland ? outerInset : safeTop + outerInset
    }
    private var verticalOffset: CGFloat {
        hasIsland ? islandTopOffset : (isExpanded ? islandTopOffset : -90)
    }
    private var scaleX: CGFloat { isExpanded ? 1 : collapsedWidth / expandedWidth }
    private var scaleY: CGFloat { isExpanded ? 1 : collapsedHeight / expandedHeight }
    private var cornerRadius: CGFloat {
        guard isExpanded else { return collapsedHeight / 2 }
        return expandedHeight <= 90 ? expandedHeight / 2 : min(expandedHeight * 0.42, 44)
    }

    var body: some View {
        toastBackground
            .overlay {
                AppIslandToastContent(toast: toast, hasIsland: hasIsland, isExpanded: isExpanded)
                    .frame(width: expandedWidth, height: expandedHeight)
                    .scaleEffect(x: scaleX, y: scaleY)
            }
            .frame(
                width: isExpanded ? expandedWidth : collapsedWidth,
                height: isExpanded ? expandedHeight : collapsedHeight
            )
            .offset(y: verticalOffset)
            .opacity(hasIsland ? 1 : (isExpanded ? 1 : 0))
            .shadow(color: .black.opacity(isExpanded ? 0.28 : 0), radius: 18, x: 0, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height < -12 {
                        dismiss()
                    }
                }
            )
            .animation(.bouncy(duration: 0.32, extraBounce: 0.02), value: isExpanded)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var toastBackground: some View {
        if #available(iOS 26.0, *) {
            ConcentricRectangle(corners: .concentric(minimum: .fixed(cornerRadius)), isUniform: true)
                .fill(.black)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black)
        }
    }
}

private struct AppIslandToastContent: View {
    let toast: AppToast
    let hasIsland: Bool
    let isExpanded: Bool

    var body: some View {
        Group {
            HStack(spacing: 12) {
                AppIslandToastIcon(
                    symbol: toast.symbol,
                    tint: toast.tone.tint,
                    showsProgress: toast.showsProgress
                )

                AppIslandToastText(title: toast.title, message: toast.message)
            }
            .padding(.leading, hasIsland ? 18 : 14)
            .padding(.trailing, 18)
            .padding(.top, hasIsland ? 52 : 0)
            .padding(.bottom, hasIsland ? 18 : 0)
        }
        .compositingGroup()
        .blur(radius: isExpanded ? 0 : 4)
        .opacity(isExpanded ? 1 : 0)
    }
}

private struct AppIslandToastIcon: View {
    let symbol: String
    let tint: Color
    let showsProgress: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 24, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.16), in: Circle())
            .overlay {
                if showsProgress {
                    Circle()
                        .trim(from: 0.12, to: 0.92)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .phaseAnimator([0, 360]) { view, phase in
                            view.rotationEffect(.degrees(phase))
                        } animation: { _ in
                            .linear(duration: 1.05).repeatForever(autoreverses: false)
                        }
                }
            }
            .accessibilityHidden(true)
    }
}

private struct AppIslandToastText: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
