import AppKit
import ApplicationServices
import ExtendCopyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pasteboard = NSPasteboard.general
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var previousClipboard: String?
    private var captureTimer: Timer?
    private var captureStartedAt = Date.distantPast
    private var changeCountBeforeCopy = 0
    private var clipboardBeforeCopy = ""
    private var isCapturing = false

    private var separator: CopySeparator {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "separator"),
                  let value = CopySeparator(rawValue: raw) else { return .newline }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "separator") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        registerHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureTimer?.invalidate()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ExtendCopy")
            button.toolTip = "ExtendCopy：⌘⇧C 追加复制"
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "ExtendCopy", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let append = NSMenuItem(title: "追加复制", action: #selector(appendCopy), keyEquivalent: "")
        append.target = self
        append.keyEquivalentModifierMask = [.command, .shift]
        append.keyEquivalent = "c"
        menu.addItem(append)

        let undo = NSMenuItem(title: "撤销上一次追加", action: #selector(undoLastAppend), keyEquivalent: "z")
        undo.target = self
        undo.keyEquivalentModifierMask = [.command]
        undo.isEnabled = previousClipboard != nil
        menu.addItem(undo)

        let clear = NSMenuItem(title: "清空剪贴板", action: #selector(clearClipboard), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        let separatorItem = NSMenuItem(title: "拼接分隔符", action: nil, keyEquivalent: "")
        let separatorMenu = NSMenu()
        for choice in CopySeparator.allCases {
            let item = SeparatorMenuItem(title: choice.displayName, separator: choice)
            item.target = self
            item.action = #selector(selectSeparator(_:))
            item.state = choice == separator ? .on : .off
            separatorMenu.addItem(item)
        }
        separatorItem.submenu = separatorMenu
        menu.addItem(separatorItem)

        let permission = NSMenuItem(title: "检查辅助功能权限…", action: #selector(checkPermission), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 ExtendCopy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func registerHotKey() {
        let hotKey = GlobalHotKey { [weak self] in
            Task { @MainActor in self?.startAppendCopy() }
        }
        do {
            try hotKey.register()
            self.hotKey = hotKey
        } catch {
            showAlert(title: "快捷键注册失败", message: error.localizedDescription)
        }
    }

    @objc private func appendCopy() {
        startAppendCopy()
    }

    private func startAppendCopy() {
        guard !isCapturing else { return }
        guard requestAccessibilityIfNeeded() else { return }

        clipboardBeforeCopy = pasteboard.string(forType: .string) ?? ""
        changeCountBeforeCopy = pasteboard.changeCount
        captureStartedAt = Date()
        isCapturing = true

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            finishCapture(success: false, message: "无法模拟复制操作")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollClipboard() }
        }
    }

    private func pollClipboard() {
        if pasteboard.changeCount != changeCountBeforeCopy {
            guard let selection = pasteboard.string(forType: .string), !selection.isEmpty else {
                finishCapture(success: false, message: "当前内容不是可追加的文字")
                return
            }
            previousClipboard = clipboardBeforeCopy
            let combined = AppendEngine.combine(
                previous: clipboardBeforeCopy,
                selection: selection,
                separator: separator
            )
            pasteboard.clearContents()
            pasteboard.setString(combined, forType: .string)
            finishCapture(success: true)
        } else if Date().timeIntervalSince(captureStartedAt) > 1.2 {
            finishCapture(success: false, message: "没有检测到选中的文字")
        }
    }

    private func finishCapture(success: Bool, message: String? = nil) {
        captureTimer?.invalidate()
        captureTimer = nil
        isCapturing = false
        rebuildMenu()
        flashStatus(success: success)
        if let message { showAlert(title: "追加复制失败", message: message) }
    }

    private func flashStatus(success: Bool) {
        statusItem.button?.image = NSImage(
            systemSymbolName: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
            accessibilityDescription: success ? "追加成功" : "追加失败"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.statusItem.button?.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "ExtendCopy"
            )
        }
    }

    @objc private func undoLastAppend() {
        guard let previousClipboard else { return }
        pasteboard.clearContents()
        pasteboard.setString(previousClipboard, forType: .string)
        self.previousClipboard = nil
        rebuildMenu()
        flashStatus(success: true)
    }

    @objc private func clearClipboard() {
        previousClipboard = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        rebuildMenu()
    }

    @objc private func selectSeparator(_ sender: SeparatorMenuItem) {
        separator = sender.separator
        rebuildMenu()
    }

    @objc private func checkPermission() {
        if AXIsProcessTrusted() {
            showAlert(title: "辅助功能权限已开启", message: "你可以使用 ⌘⇧C 追加复制。")
        } else {
            _ = requestAccessibilityIfNeeded()
        }
    }

    private func requestAccessibilityIfNeeded() -> Bool {
        guard !AXIsProcessTrusted() else { return true }
        // Using the documented key value avoids Swift 6 treating the imported
        // global CFString variable as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        showAlert(
            title: "需要辅助功能权限",
            message: "请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 ExtendCopy，然后再按 ⌘⇧C。"
        )
        return false
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private final class SeparatorMenuItem: NSMenuItem {
    let separator: CopySeparator

    init(title: String, separator: CopySeparator) {
        self.separator = separator
        super.init(title: title, action: nil, keyEquivalent: "")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
