import AppKit
import SwiftUI

extension View {
    /// Closes a sheet when you click the window behind it, like a popover. Only for sheets
    /// that show things; sheets you type into keep Done and Cancel, so nothing typed is lost.
    func closesOnClickOutside(_ close: @escaping () -> Void) -> some View {
        background(OutsideClickCatcher(close: close))
    }
}

private struct OutsideClickCatcher: NSViewRepresentable {
    let close: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.view = view
        coordinator.close = close
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak coordinator] event in
            let outside = MainActor.assumeIsolated { () -> Bool in
                // A click on the window this sheet hangs from, away from the sheet itself, while
                // nothing sits on top of the sheet.
                guard let coordinator, let sheet = coordinator.view?.window, let parent = sheet.sheetParent,
                      event.window === parent, sheet.attachedSheet == nil,
                      !sheet.frame.contains(parent.convertPoint(toScreen: event.locationInWindow)) else { return false }
                coordinator.close?()
                Self.swallowNextMouseUp()
                return true
            }
            return outside ? nil : event
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.close = close
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    /// The press closed the sheet, so its release shouldn't click whatever was underneath.
    @MainActor private static func swallowNextMouseUp() {
        let once = Coordinator()
        once.monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [once] _ in
            MainActor.assumeIsolated {
                if let monitor = once.monitor { NSEvent.removeMonitor(monitor) }
                once.monitor = nil
            }
            return nil
        }
    }

    @MainActor final class Coordinator {
        weak var view: NSView?
        var close: (() -> Void)?
        var monitor: Any?
    }
}
