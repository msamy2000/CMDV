import Foundation
import AppKit
import ApplicationServices

public enum CursorPositionHelper {
    /// Returns the preferred screen anchor point (in Cocoa global screen coordinates, origin at bottom-left of primary screen)
    /// by checking the Accessibility focused text caret first, then falling back to the current mouse cursor location.
    public static func currentCaretOrMouseScreenPoint() -> NSPoint {
        if let caretPoint = focusedCaretScreenPoint() {
            return caretPoint
        }
        return NSEvent.mouseLocation
    }

    /// Queries the system-wide Accessibility element for the active text selection bounds and converts from Quartz top-left
    /// screen coordinates to AppKit bottom-left screen coordinates.
    private static func focusedCaretScreenPoint() -> NSPoint? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusErr == .success, let focusedElement = focusedElementRef else {
            return nil
        }

        let axElement = focusedElement as! AXUIElement

        var selectedRangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeRef
        )
        guard rangeErr == .success, let selectedRange = selectedRangeRef else {
            return nil
        }

        var boundsRef: CFTypeRef?
        let boundsErr = AXUIElementCopyParameterizedAttributeValue(
            axElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange,
            &boundsRef
        )
        guard boundsErr == .success,
              let boundsValue = boundsRef,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        var caretRect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &caretRect) else {
            return nil
        }

        // Ignore bogus zero coordinates returned by some non-standard web/electron views
        if caretRect.origin.x == 0 && caretRect.origin.y == 0 && caretRect.width == 0 && caretRect.height == 0 {
            return nil
        }

        // Convert Quartz (top-left of primary screen) to Cocoa (bottom-left of primary screen)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 1080
        let cocoaY = primaryScreenHeight - (caretRect.origin.y + caretRect.size.height)
        return NSPoint(x: caretRect.origin.x, y: cocoaY)
    }

    /// Computes a clamped window frame so the popup never overflows off-screen.
    public static func clampedWindowOrigin(
        anchor: NSPoint,
        windowSize: NSSize,
        preferBelow: Bool = true
    ) -> NSPoint {
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let visibleFrame = targetScreen?.visibleFrame else {
            return NSPoint(x: anchor.x, y: anchor.y - windowSize.height)
        }

        let margin: CGFloat = 10
        var x = anchor.x
        var y = preferBelow ? (anchor.y - windowSize.height - 6) : (anchor.y - windowSize.height / 2)

        // If placing below goes under the bottom edge of visible screen, flip above anchor or clamp
        if y < visibleFrame.minY + margin {
            let flippedY = anchor.y + 18
            if flippedY + windowSize.height <= visibleFrame.maxY - margin {
                y = flippedY
            } else {
                y = max(visibleFrame.minY + margin, min(y, visibleFrame.maxY - windowSize.height - margin))
            }
        }

        if y + windowSize.height > visibleFrame.maxY - margin {
            y = visibleFrame.maxY - windowSize.height - margin
        }

        if x + windowSize.width > visibleFrame.maxX - margin {
            x = visibleFrame.maxX - windowSize.width - margin
        }
        if x < visibleFrame.minX + margin {
            x = visibleFrame.minX + margin
        }

        return NSPoint(x: round(x), y: round(y))
    }
}
