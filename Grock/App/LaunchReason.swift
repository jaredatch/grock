import AppKit
import Carbon

/// Whether this process should present the overlay at launch.
///
/// Default is show: Dock, Spotlight, Finder, and `open` are a request to use
/// the app. Stay quiet only when we can tell this is a login-item or hidden start.
enum LaunchReason {
    /// `'lgit'` — `keyAELaunchedAsLogInItem` in AERegistry.
    static let loginItemKeyword: AEKeyword = 0x6c676974

    static func shouldShowMainWindow(
        appleEvent: NSAppleEventDescriptor?,
        isHidden: Bool
    ) -> Bool {
        if indicatesLoginItem(appleEvent) { return false }
        if isHidden { return false }
        return true
    }

    static func indicatesLoginItem(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event else { return false }
        if event.paramDescriptor(forKeyword: loginItemKeyword) != nil {
            return true
        }
        if event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == OSType(loginItemKeyword) {
            return true
        }
        return false
    }

    /// `GURL` / `kAEGetURL` direct object, when this process was launched by a URL.
    static func url(from event: NSAppleEventDescriptor?) -> URL? {
        guard let event else { return nil }
        guard event.eventClass == AEEventClass(kInternetEventClass),
              event.eventID == AEEventID(kAEGetURL)
        else { return nil }
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string)
        else { return nil }
        return url
    }

    /// `odoc` / `kAEOpenDocuments` file list, when Finder or `open -a` handed us files.
    static func fileURLs(from event: NSAppleEventDescriptor?) -> [URL] {
        guard let event else { return [] }
        guard event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenDocuments)
        else { return [] }
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else { return [] }
        if direct.numberOfItems > 0 {
            var urls: [URL] = []
            for index in 1...direct.numberOfItems {
                if let item = direct.atIndex(index), let url = fileURL(from: item) {
                    urls.append(url)
                }
            }
            return urls
        }
        if let url = fileURL(from: direct) {
            return [url]
        }
        return []
    }

    private static func fileURL(from descriptor: NSAppleEventDescriptor) -> URL? {
        if let url = descriptor.fileURLValue { return url }
        if let string = descriptor.stringValue, !string.isEmpty {
            if string.hasPrefix("/") { return URL(fileURLWithPath: string) }
            if let url = URL(string: string), url.isFileURL { return url }
        }
        return nil
    }
}
