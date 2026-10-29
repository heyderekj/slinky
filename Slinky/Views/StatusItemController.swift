import AppKit
import Observation
import SwiftUI

/// The menu bar item on macOS 27 and later: an AppKit status item that hands its panel to the system's
/// expanded-interface sessions, so it works like the menus beside it: Control-F8 and the arrow keys reach it,
/// and sliding across the menu bar from another menu opens it. Before 27, `MenuBarExtra` in SlinkyApp draws it.
@available(macOS 27, *)
@MainActor
final class StatusItemController: NSObject, NSStatusItemExpandedInterfaceDelegate, NSWindowDelegate {
    static let shared = StatusItemController()

    private var item: NSStatusItem?
    private var panel: NSPanel?

    /// Follows Settings › General › Show in menu bar.
    func start(model: AppModel, prefs: Preferences) {
        update(show: prefs.showInMenuBar, model: model)
        withObservationTracking { _ = prefs.showInMenuBar } onChange: {
            Task { @MainActor in StatusItemController.shared.start(model: model, prefs: prefs) }
        }
    }

    private func update(show: Bool, model: AppModel) {
        if show, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = MenuBarIcon.image
            item.button?.setAccessibilityLabel("Slinky")
            item.expandedInterfaceDelegate = self
            self.item = item
            let host = NSHostingController(rootView: MenuBarStack().symbolVariant(.fill).environment(model))
            host.sizingOptions = .preferredContentSize
            let panel = NSPanel(contentViewController: host)
            panel.styleMask = [.nonactivatingPanel, .fullSizeContentView, .borderless]
            panel.level = .popUpMenu
            panel.isFloatingPanel = true
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            host.view.wantsLayer = true
            host.view.layer?.cornerRadius = 12
            host.view.layer?.masksToBounds = true
            let effect = NSVisualEffectView()
            effect.material = .menu
            effect.state = .active
            effect.blendingMode = .behindWindow
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 12
            effect.layer?.masksToBounds = true
            effect.addSubview(host.view)
            host.view.frame = effect.bounds
            host.view.autoresizingMask = [.width, .height]
            panel.contentView = effect
            panel.setContentSize(host.view.fittingSize)
            self.panel = panel
        } else if !show, let item {
            item.expandedInterfaceSession?.cancel()
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            panel?.orderOut(nil)
            panel = nil
        }
    }

    // MARK: NSStatusItemExpandedInterfaceDelegate

    nonisolated func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        MainActor.assumeIsolated { show() }
    }

    nonisolated func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        MainActor.assumeIsolated { panel?.orderOut(nil) }
    }

    private func show() {
        guard let panel, let button = item?.button, let window = button.window else { return }
        if let host = (panel.contentView?.subviews.first) { panel.setContentSize(host.fittingSize) }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 4)
        if let screen = window.screen?.visibleFrame { origin.x = min(origin.x, screen.maxX - size.width - 8) }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
    }

    // A click somewhere else, or a row that opened a window: the session ends the way a menu's would.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { item?.expandedInterfaceSession?.cancel() }
    }
}
