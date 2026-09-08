import AppKit
import ApplicationServices
import ExtendCopyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pasteboard = NSPasteboard.general
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var clipboardViewer: ClipboardViewerWindowController?
    private var previousClipboard: String?
    private var captureTimer: Timer?
    private var captureStartedAt = Date.distantPast
    private var changeCountBeforeCopy = 0
    private var clipboardBeforeCopy = ""
    private var isCapturing = false

    private var isFeatureEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: "featureEnabled") != nil else { return true }
            return UserDefaults.standard.bool(forKey: "featureEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "featureEnabled") }
    }

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
        if isFeatureEnabled { registerHotKey() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureTimer?.invalidate()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusAppearance()
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "ExtendCopy", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "启用追加复制", action: #selector(toggleFeature), keyEquivalent: "")
        enabled.target = self
        enabled.state = isFeatureEnabled ? .on : .off
        menu.addItem(enabled)

        menu.addItem(.separator())

        let append = NSMenuItem(title: "追加复制", action: #selector(appendCopy), keyEquivalent: "")
        append.target = self
        append.keyEquivalentModifierMask = [.command, .shift]
        append.keyEquivalent = "c"
        append.isEnabled = isFeatureEnabled
        menu.addItem(append)

        let undo = NSMenuItem(title: "撤销上一次追加", action: #selector(undoLastAppend), keyEquivalent: "z")
        undo.target = self
        undo.keyEquivalentModifierMask = [.command]
        undo.isEnabled = previousClipboard != nil
        menu.addItem(undo)

        let viewClipboard = NSMenuItem(title: "查看剪贴板…", action: #selector(viewClipboard), keyEquivalent: "")
        viewClipboard.target = self
        menu.addItem(viewClipboard)

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
        guard hotKey == nil else { return }
        let hotKey = GlobalHotKey { [weak self] in
            Task { @MainActor in self?.startAppendCopy() }
        }
        do {
            try hotKey.register()
            self.hotKey = hotKey
        } catch {
            self.hotKey = nil
            isFeatureEnabled = false
            updateStatusAppearance()
            rebuildMenu()
            showAlert(title: "快捷键注册失败", message: error.localizedDescription)
        }
    }

    @objc private func toggleFeature() {
        isFeatureEnabled.toggle()
        if isFeatureEnabled {
            registerHotKey()
        } else {
            captureTimer?.invalidate()
            captureTimer = nil
            isCapturing = false
            hotKey = nil
        }
        updateStatusAppearance()
        rebuildMenu()
    }

    @objc private func appendCopy() {
        startAppendCopy()
    }

    private func startAppendCopy() {
        guard isFeatureEnabled else { return }
        guard !isCapturing else { return }
        guard requestAccessibilityIfNeeded() else { return }

        clipboardBeforeCopy = pasteboard.string(forType: .string) ?? ""
        isCapturing = true

        // The Carbon hot-key callback can arrive while Command and Shift are
        // still physically held. Posting Command-C at that instant is treated
        // as Command-Shift-C by many apps, so wait for the original shortcut
        // to be released before synthesizing the normal Copy command.
        waitForShortcutRelease(deadline: Date().addingTimeInterval(1.5))
    }

    private func waitForShortcutRelease(deadline: Date) {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let shortcutIsStillDown = flags.contains(.maskCommand) || flags.contains(.maskShift)
        if shortcutIsStillDown, Date() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.waitForShortcutRelease(deadline: deadline)
            }
            return
        }

        sendCopyKeystroke()
    }

    private func sendCopyKeystroke() {
        changeCountBeforeCopy = pasteboard.changeCount
        captureStartedAt = Date()

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
            if let selection = pasteboard.string(forType: .string), !selection.isEmpty {
                previousClipboard = clipboardBeforeCopy
                let combined = AppendEngine.combine(
                    previous: clipboardBeforeCopy,
                    selection: selection,
                    separator: separator
                )
                pasteboard.clearContents()
                pasteboard.setString(combined, forType: .string)
                finishCapture(success: true)
                return
            }

            // Some apps publish pasteboard representations in more than one
            // pass. Keep polling briefly instead of failing on the first
            // change-count update before the string representation is ready.
        }

        if Date().timeIntervalSince(captureStartedAt) > 2.0 {
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
            self?.updateStatusAppearance()
        }
    }

    private func updateStatusAppearance() {
        let symbolName = isFeatureEnabled ? "doc.on.clipboard" : "pause.circle"
        let description = isFeatureEnabled ? "ExtendCopy 已启用" : "ExtendCopy 已关闭"
        statusItem?.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        statusItem?.button?.toolTip = isFeatureEnabled
            ? "ExtendCopy：⌘⇧C 追加复制"
            : "ExtendCopy：追加复制已关闭"
    }

    @objc private func undoLastAppend() {
        guard let previousClipboard else { return }
        pasteboard.clearContents()
        pasteboard.setString(previousClipboard, forType: .string)
        self.previousClipboard = nil
        rebuildMenu()
        flashStatus(success: true)
    }

    @objc private func viewClipboard() {
        if clipboardViewer == nil {
            clipboardViewer = ClipboardViewerWindowController(pasteboard: pasteboard)
        }
        clipboardViewer?.present()
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
