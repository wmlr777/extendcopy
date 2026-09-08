import Carbon
import Foundation

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            instance.action()
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else { throw HotKeyError.installFailed(installStatus) }

        let identifier = EventHotKeyID(signature: fourCharacterCode("EXCP"), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_C),
            UInt32(cmdKey | shiftKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else { throw HotKeyError.registrationFailed(registerStatus) }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}

enum HotKeyError: LocalizedError {
    case installFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installFailed(let status): "无法安装快捷键监听（错误 \(status)）"
        case .registrationFailed(let status): "⌘⇧C 已被其他应用占用（错误 \(status)）"
        }
    }
}
