import Foundation
import SwiftUI
import StrandDesign

struct AppToast: Identifiable, Equatable {
    enum DisplayMode: Equatable {
        case sticky
        case timed(TimeInterval)
    }

    enum Tone: Equatable {
        case syncing
        case success
        case warning
        case info

        var tint: Color {
            switch self {
            case .syncing: StrandPalette.metricCyan
            case .success: StrandPalette.accent
            case .warning: StrandPalette.statusWarning
            case .info: StrandPalette.textSecondary
            }
        }
    }

    let id = UUID()
    var key: String
    var symbol: String
    var title: String
    var message: String
    var tone: Tone
    var showsProgress: Bool = false
    var displayMode: DisplayMode = .timed(3.5)
}

@MainActor
final class AppToastCenter: ObservableObject {
    @Published private(set) var current: AppToast?
    @Published private(set) var isPresented = false
    @Published private(set) var hidesStatusBar = false

    private var dismissTask: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?
    private var queue: [AppToast] = []
    private var currentShownAt: Date?
    private let minimumVisibleDuration: TimeInterval = 1.15
    private let collapseDuration: TimeInterval = 0.32
    private let maximumQueuedToasts = 4

    func show(_ toast: AppToast) {
        clearTask?.cancel()

        if current?.key == toast.key {
            updateCurrent(toast)
            return
        }

        if let index = queue.firstIndex(where: { $0.key == toast.key }) {
            queue[index] = toast
            return
        }

        guard current != nil else {
            present(toast)
            return
        }

        enqueue(toast)
    }

    func dismiss() {
        guard current != nil else { return }
        finishCurrent()
    }

    private func present(_ toast: AppToast) {
        dismissTask?.cancel()
        current = toast
        currentShownAt = Date()
        withAnimation(.bouncy(duration: 0.32, extraBounce: 0.04)) {
            isPresented = true
            hidesStatusBar = true
        }
        scheduleDismissIfNeeded(for: toast)
    }

    private func updateCurrent(_ toast: AppToast) {
        dismissTask?.cancel()
        current = toast
        currentShownAt = Date()
        if !isPresented {
            withAnimation(.bouncy(duration: 0.32, extraBounce: 0.04)) {
                isPresented = true
                hidesStatusBar = true
            }
        }
        scheduleDismissIfNeeded(for: toast)
    }

    private func enqueue(_ toast: AppToast) {
        queue.append(toast)
        if queue.count > maximumQueuedToasts {
            queue.removeFirst(queue.count - maximumQueuedToasts)
        }
    }

    private func scheduleDismissIfNeeded(for toast: AppToast) {
        guard case .timed(let delay) = toast.displayMode else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run { self?.finishCurrent() }
        }
    }

    private func finishCurrent() {
        dismissTask?.cancel()
        let elapsed = currentShownAt.map { Date().timeIntervalSince($0) } ?? minimumVisibleDuration
        let remaining = max(0, minimumVisibleDuration - elapsed)

        if remaining > 0 {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                await MainActor.run { self?.collapseCurrent() }
            }
        } else {
            collapseCurrent()
        }
    }

    private func collapseCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.easeInOut(duration: 0.22)) {
            isPresented = false
            hidesStatusBar = false
        }

        let collapseDuration = self.collapseDuration
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(collapseDuration * 1_000_000_000))
            await MainActor.run { self?.showNextAfterCollapse() }
        }
    }

    private func showNextAfterCollapse() {
        current = nil
        currentShownAt = nil
        guard !queue.isEmpty else { return }
        let next = queue.removeLast()
        queue.removeAll()
        present(next)
    }
}
