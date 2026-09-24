import AppKit
import Carbon
import CoreGraphics

enum HotkeyAction: String, CaseIterable {
    case summon
    case newChat
    case voiceChat
    case quickChat

    var carbonID: UInt32 {
        switch self {
        case .summon: return 1
        case .newChat: return 2
        case .voiceChat: return 3
        case .quickChat: return 4
        }
    }

    var defaultsKey: String {
        switch self {
        case .summon: return "hotkey.combo"
        case .newChat: return "hotkey.newChat"
        case .voiceChat: return "hotkey.voiceChat"
        case .quickChat: return "hotkey.quickChat"
        }
    }
}

enum HotkeyStatus: Equatable {
    case unset
    case registered
    case failed
}

/// First-launch / upgrade mapping for the four Carbon hotkeys.
/// Voice Chat stays unset until assigned (DEC-021).
enum HotkeyBindings {
    static let didMigrateKey = "hotkey.didMigrateDual"
    static let didMigrateQuickChatDefaultKey = "hotkey.didMigrateQuickChatDefault"

    struct Snapshot: Equatable {
        var summon: HotkeyManager.Combo?
        var newChat: HotkeyManager.Combo?
        var quickChat: HotkeyManager.Combo?
    }

    /// Fresh install: Quick Chat is ⌥Space; New Chat and summon are empty (DEC-045).
    /// Legacy summon-only installs keep that combo. Factory New Chat = ⌥Space with
    /// Quick Chat never assigned moves ⌥Space to Quick Chat. Custom bindings stay.
    static func migrate(
        savedSummon: Data?,
        savedNewChat: Data?,
        savedQuickChat: Data?,
        didMigrateDual: Bool,
        didMigrateQuickChatDefault: Bool
    ) -> Snapshot {
        let summon = decode(savedSummon)
        let newChat = decode(savedNewChat)
        let quickChat = decode(savedQuickChat)

        if didMigrateQuickChatDefault {
            return Snapshot(summon: summon, newChat: newChat, quickChat: quickChat)
        }

        if !didMigrateDual {
            if let summon {
                return Snapshot(summon: summon, newChat: nil, quickChat: nil)
            }
            return Snapshot(summon: nil, newChat: nil, quickChat: .optionSpace)
        }

        if newChat == .optionSpace && quickChat == nil {
            return Snapshot(summon: summon, newChat: nil, quickChat: .optionSpace)
        }

        return Snapshot(summon: summon, newChat: newChat, quickChat: quickChat)
    }

    static func decode(_ data: Data?) -> HotkeyManager.Combo? {
        guard let data, !data.isEmpty,
              let combo = try? JSONDecoder().decode(HotkeyManager.Combo.self, from: data)
        else { return nil }
        return combo
    }
}

/// Global hotkeys via Carbon `RegisterEventHotKey`.
///
/// CGEventTap looks right in-process but a sandboxed tap often never sees
/// keys from other apps, which is how the first build failed. Carbon registers with
/// the window server, consumes the combo, and does not need Accessibility.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    struct Combo: Equatable, Codable {
        /// Carbon / hardware key code (49 = Space).
        var keyCode: Int64
        /// CGEventFlags raw value (device-independent bits).
        var flags: UInt64

        static let optionSpace = Combo(
            keyCode: 49,
            flags: CGEventFlags.maskAlternate.rawValue
        )

        var displayString: String {
            var parts: [String] = []
            let f = CGEventFlags(rawValue: flags)
            if f.contains(.maskControl) { parts.append("⌃") }
            if f.contains(.maskAlternate) { parts.append("⌥") }
            if f.contains(.maskShift) { parts.append("⇧") }
            if f.contains(.maskCommand) { parts.append("⌘") }
            parts.append(Self.keyName(keyCode: keyCode))
            return parts.joined()
        }

        /// At least one of ⌘ / ⌥ / ⌃, and not a modifier-only press.
        var isValidShortcut: Bool {
            if Self.isModifierKeyCode(keyCode) { return false }
            let f = CGEventFlags(rawValue: flags)
            return f.contains(.maskCommand)
                || f.contains(.maskAlternate)
                || f.contains(.maskControl)
        }

        init(keyCode: Int64, flags: UInt64) {
            self.keyCode = keyCode
            self.flags = flags
        }

        init(nsEvent event: NSEvent) {
            var flags: UInt64 = 0
            if event.modifierFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
            if event.modifierFlags.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
            if event.modifierFlags.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
            if event.modifierFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
            self.init(keyCode: Int64(event.keyCode), flags: flags)
        }

        var carbonModifiers: UInt32 {
            let f = CGEventFlags(rawValue: flags)
            var mods: UInt32 = 0
            if f.contains(.maskCommand) { mods |= UInt32(cmdKey) }
            if f.contains(.maskShift) { mods |= UInt32(shiftKey) }
            if f.contains(.maskAlternate) { mods |= UInt32(optionKey) }
            if f.contains(.maskControl) { mods |= UInt32(controlKey) }
            return mods
        }

        static func isModifierKeyCode(_ keyCode: Int64) -> Bool {
            switch keyCode {
            case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: return true
            default: return false
            }
        }

        static func keyName(keyCode: Int64) -> String {
            switch keyCode {
            case 0: return "A"
            case 1: return "S"
            case 2: return "D"
            case 3: return "F"
            case 4: return "H"
            case 5: return "G"
            case 6: return "Z"
            case 7: return "X"
            case 8: return "C"
            case 9: return "V"
            case 11: return "B"
            case 12: return "Q"
            case 13: return "W"
            case 14: return "E"
            case 15: return "R"
            case 16: return "Y"
            case 17: return "T"
            case 18: return "1"
            case 19: return "2"
            case 20: return "3"
            case 21: return "4"
            case 22: return "6"
            case 23: return "5"
            case 24: return "="
            case 25: return "9"
            case 26: return "7"
            case 27: return "-"
            case 28: return "8"
            case 29: return "0"
            case 30: return "]"
            case 31: return "O"
            case 32: return "U"
            case 33: return "["
            case 34: return "I"
            case 35: return "P"
            case 36: return "Return"
            case 37: return "L"
            case 38: return "J"
            case 39: return "'"
            case 40: return "K"
            case 41: return ";"
            case 42: return "\\"
            case 43: return ","
            case 44: return "/"
            case 45: return "N"
            case 46: return "M"
            case 47: return "."
            case 48: return "Tab"
            case 49: return "Space"
            case 50: return "`"
            case 51: return "Delete"
            case 53: return "Esc"
            case 96: return "F5"
            case 97: return "F6"
            case 98: return "F7"
            case 99: return "F3"
            case 100: return "F8"
            case 101: return "F9"
            case 103: return "F11"
            case 109: return "F10"
            case 111: return "F12"
            case 118: return "F4"
            case 120: return "F2"
            case 122: return "F1"
            case 123: return "←"
            case 124: return "→"
            case 125: return "↓"
            case 126: return "↑"
            default: return "Key(\(keyCode))"
            }
        }
    }

    static let comboDefaultsKey = HotkeyAction.summon.defaultsKey
    static let didChangeNotification = Notification.Name("com.jaredatch.Grock.hotkeyDidChange")

    private var summonCombo: Combo?
    private var newChatCombo: Combo?
    private var voiceChatCombo: Combo?
    private var quickChatCombo: Combo?
    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var registeredActions: Set<HotkeyAction> = []
    private var lastErrors: [HotkeyAction: OSStatus] = [:]
    private var handlerRef: EventHandlerRef?

    private init() {
        let defaults = UserDefaults.standard
        let didMigrateDual = defaults.bool(forKey: HotkeyBindings.didMigrateKey)
        let didMigrateQuickChatDefault = defaults.bool(
            forKey: HotkeyBindings.didMigrateQuickChatDefaultKey
        )
        let snapshot = HotkeyBindings.migrate(
            savedSummon: defaults.data(forKey: HotkeyAction.summon.defaultsKey),
            savedNewChat: defaults.data(forKey: HotkeyAction.newChat.defaultsKey),
            savedQuickChat: defaults.data(forKey: HotkeyAction.quickChat.defaultsKey),
            didMigrateDual: didMigrateDual,
            didMigrateQuickChatDefault: didMigrateQuickChatDefault
        )
        summonCombo = snapshot.summon
        newChatCombo = snapshot.newChat
        voiceChatCombo = HotkeyBindings.decode(defaults.data(forKey: HotkeyAction.voiceChat.defaultsKey))
        quickChatCombo = snapshot.quickChat
        if !didMigrateDual || !didMigrateQuickChatDefault {
            persist(snapshot.summon, for: .summon)
            persist(snapshot.newChat, for: .newChat)
            persist(snapshot.quickChat, for: .quickChat)
            defaults.set(true, forKey: HotkeyBindings.didMigrateKey)
            defaults.set(true, forKey: HotkeyBindings.didMigrateQuickChatDefaultKey)
        }
    }

    func combo(for action: HotkeyAction) -> Combo? {
        switch action {
        case .summon: return summonCombo
        case .newChat: return newChatCombo
        case .voiceChat: return voiceChatCombo
        case .quickChat: return quickChatCombo
        }
    }

    func status(for action: HotkeyAction) -> HotkeyStatus {
        guard combo(for: action) != nil else { return .unset }
        return registeredActions.contains(action) ? .registered : .failed
    }

    var isRecording: Bool {
        get {
            hotkeySharedState.lock.lock()
            defer { hotkeySharedState.lock.unlock() }
            return hotkeySharedState.ignoreTriggers
        }
        set {
            hotkeySharedState.lock.lock()
            hotkeySharedState.ignoreTriggers = newValue
            hotkeySharedState.lock.unlock()
        }
    }

    /// Returns false if `combo` is already used by another action.
    @discardableResult
    func setCombo(_ combo: Combo?, for action: HotkeyAction) -> Bool {
        if let combo {
            for other in HotkeyAction.allCases where other != action {
                if self.combo(for: other) == combo { return false }
            }
        }
        store(combo, for: action)
        persist(combo, for: action)
        register(action)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        return true
    }

    func start(
        onSummon: @escaping () -> Void,
        onNewChat: @escaping () -> Void,
        onVoiceChat: @escaping () -> Void,
        onQuickChat: @escaping () -> Void
    ) {
        hotkeySharedState.lock.lock()
        hotkeySharedState.onSummon = onSummon
        hotkeySharedState.onNewChat = onNewChat
        hotkeySharedState.onVoiceChat = onVoiceChat
        hotkeySharedState.onQuickChat = onQuickChat
        hotkeySharedState.lock.unlock()
        installHandlerIfNeeded()
        registerAll()
    }

    func stop() {
        for action in HotkeyAction.allCases {
            unregister(action)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        hotkeySharedState.lock.lock()
        hotkeySharedState.onSummon = nil
        hotkeySharedState.onNewChat = nil
        hotkeySharedState.onVoiceChat = nil
        hotkeySharedState.onQuickChat = nil
        hotkeySharedState.lock.unlock()
    }

    func retryInstallIfNeeded() {
        installHandlerIfNeeded()
        registerAll()
    }

    private func store(_ combo: Combo?, for action: HotkeyAction) {
        switch action {
        case .summon: summonCombo = combo
        case .newChat: newChatCombo = combo
        case .voiceChat: voiceChatCombo = combo
        case .quickChat: quickChatCombo = combo
        }
    }

    private func persist(_ combo: Combo?, for action: HotkeyAction) {
        if let combo, let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: action.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var ref: EventHandlerRef?
        let err = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                HotkeyManager.handleCarbonEvent(event)
                return noErr
            },
            1,
            &spec,
            nil,
            &ref
        )
        if err != noErr {
            NSLog("[Grock] InstallEventHandler failed: \(err)")
            return
        }
        handlerRef = ref
    }

    private func registerAll() {
        for action in HotkeyAction.allCases {
            register(action)
        }
    }

    private func register(_ action: HotkeyAction) {
        unregister(action)
        guard let combo = combo(for: action) else {
            lastErrors[action] = noErr
            return
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: grockHotKeySignature, id: action.carbonID)
        let err = RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.carbonModifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        lastErrors[action] = err
        if err != noErr {
            NSLog("[Grock] RegisterEventHotKey failed (\(err)) for \(action.rawValue) \(combo.displayString)")
            return
        }
        hotKeyRefs[action] = ref
        registeredActions.insert(action)
        NSLog("[Grock] Global hotkey registered: \(action.rawValue) \(combo.displayString)")
    }

    private func unregister(_ action: HotkeyAction) {
        if let hotKeyRef = hotKeyRefs[action] {
            UnregisterEventHotKey(hotKeyRef)
            hotKeyRefs[action] = nil
        }
        registeredActions.remove(action)
    }

    nonisolated private static func handleCarbonEvent(_ event: EventRef?) {
        guard let event else { return }
        var hotKeyID = EventHotKeyID()
        let err = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard err == noErr, hotKeyID.signature == grockHotKeySignature else { return }

        hotkeySharedState.lock.lock()
        let ignore = hotkeySharedState.ignoreTriggers
        let onSummon = hotkeySharedState.onSummon
        let onNewChat = hotkeySharedState.onNewChat
        let onVoiceChat = hotkeySharedState.onVoiceChat
        let onQuickChat = hotkeySharedState.onQuickChat
        hotkeySharedState.lock.unlock()
        guard !ignore else { return }

        DispatchQueue.main.async {
            switch hotKeyID.id {
            case HotkeyAction.summon.carbonID:
                onSummon?()
            case HotkeyAction.newChat.carbonID:
                onNewChat?()
            case HotkeyAction.voiceChat.carbonID:
                onVoiceChat?()
            case HotkeyAction.quickChat.carbonID:
                onQuickChat?()
            default:
                break
            }
        }
    }
}

/// Lock-protected; the Carbon callback is not on the main actor.
private final class HotkeySharedState: @unchecked Sendable {
    let lock = NSLock()
    var onSummon: (() -> Void)?
    var onNewChat: (() -> Void)?
    var onVoiceChat: (() -> Void)?
    var onQuickChat: (() -> Void)?
    var ignoreTriggers = false
}

private let hotkeySharedState = HotkeySharedState()
private let grockHotKeySignature = OSType(0x4752434B) // 'GRCK'
