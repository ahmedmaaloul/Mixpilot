import AppKit

/// Opens Mixpilot's windows from places without a SwiftUI environment (the app delegate).
enum AppWindows {
    /// Opens Settings: presses the app menu's Settings item (⌘,), which SwiftUI's `Settings` scene
    /// creates and handles. Menu bar apps never show that menu, but it exists.
    static func openSettings() {
        NSApp.activate()
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command })
        else { return }
        appMenu.performActionForItem(at: index)
    }

    /// The standard About window, with the acknowledgements the MIT license asks for.
    static func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: acknowledgements])
    }

    private static var acknowledgements: NSAttributedString {
        let title = String(localized: "Acknowledgements")
        let text = """
        \(title)

        KeyboardShortcuts
        Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software \
        and associated documentation files (the "Software"), to deal in the Software without restriction, \
        including without limitation the rights to use, copy, modify, merge, publish, distribute, \
        sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or \
        substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING \
        BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND \
        NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, \
        DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        attributed.addAttributes(
            [.font: NSFont.preferredFont(forTextStyle: .headline), .foregroundColor: NSColor.labelColor],
            range: NSRange(location: 0, length: (title as NSString).length)
        )
        return attributed
    }
}
