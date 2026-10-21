/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import Cocoa

extension NSButton {
    var isChecked: Bool {
        get { state == .on }
        set { state = newValue ? .on : .off }
    }
}

enum Icons {
    static func image(for role: MenuBarItemRole, hidden: Bool = false) -> NSImage {
        let size = CGFloat(Settings.iconSize) * (role == .extraDivider ? 0.6 : 1)
        let symbol = role == .control ? (hidden ? "chevron.left" : "chevron.right") : "circle.fill"
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                symbolImage.draw(in: rect)
            } else {
                NSColor.labelColor.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
