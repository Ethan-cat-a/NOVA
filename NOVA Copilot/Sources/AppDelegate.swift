import AppKit
import Carbon
import QuartzCore
import Sparkle
import SwiftUI

private func novaCopilotHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var pressedID = EventHotKeyID()
    let result = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedID
    )
    guard result == noErr, pressedID.signature == OSType(0x4E4F5641), pressedID.id == 1 else { return noErr }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { delegate.togglePanel() }
    return noErr
}

@MainActor
final class FloatingPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
private final class EdgeHandlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct EdgeHandleView: View {
    let onOpen: () -> Void
    @StateObject private var state = EdgeHandleViewState()

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Capsule()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: 2, height: 26)
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 36, height: 108)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.035, green: 0.06, blue: 0.14).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(
                color: Color.cyan.opacity(state.isHovered ? 0.42 : 0.22),
                radius: state.isHovered ? 18 : 10,
                x: -5,
                y: 0
            )
            .scaleEffect(state.isHovered ? 1.06 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state.isHovered)
        }
        .buttonStyle(.plain)
        .onHover { state.isHovered = $0 }
        .help("Open NOVA Copilot · ⌘⇧Space")
    }
}


@MainActor
private final class EdgeHandleViewState: ObservableObject {
    @Published var isHovered = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private let chatModel = NovaChatModel()
    private let panelState = PanelState()
    private let updateStatus = UpdaterStatus()
    private var panel: FloatingPanel!
    private var edgeHandlePanel: EdgeHandlePanel!
    private var statusItem: NSStatusItem!
    private var updaterController: SPUStandardUpdaterController!
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var isPanelAnimating = false
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        createPanel()
        createApplicationMenu()
        createMenuBarItem()
        createEdgeHandle()
        registerGlobalHotKey()

        panelState.onPinChanged = { [weak self] pinned in
            self?.panel.level = pinned ? .floating : .normal
        }

        // Leave the assistant tucked away, with both quick access points ready.
        edgeHandlePanel.orderFrontRegardless()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await NovaAccountStore.shared.handleGoogleOAuthCallback(url) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !panel.isVisible else { return true }
        showPanel()
        return false
    }

    func togglePanel() {
        guard !isPanelAnimating else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard !isPanelAnimating else { return }
        guard let screen = screenUnderPointer() else {
            edgeHandlePanel.orderOut(nil)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let visibleFrame = screen.visibleFrame
        let targetOrigin = panelTargetOrigin(on: screen)
        let startOrigin = NSPoint(x: visibleFrame.maxX + 22, y: targetOrigin.y)
        let overshootOrigin = NSPoint(x: targetOrigin.x - 14, y: targetOrigin.y)

        edgeHandlePanel.orderOut(nil)
        panel.setFrameOrigin(startOrigin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        isPanelAnimating = true

        // Slide in with a small spring overshoot, then settle into place.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.36
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.88, 0.24, 1.04)
            panel.animator().setFrameOrigin(overshootOrigin)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.13
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().setFrameOrigin(targetOrigin)
            }, completionHandler: { [weak self] in
                self?.isPanelAnimating = false
            })
        })
    }

    private func hidePanel() {
        guard panel.isVisible, !isPanelAnimating else { return }
        isPanelAnimating = true

        let screen = screenContainingPanel() ?? screenUnderPointer()
        let exitX = (screen?.visibleFrame.maxX ?? panel.frame.maxX) + 22
        let exitOrigin = NSPoint(x: exitX, y: panel.frame.origin.y)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 0.6)
            panel.animator().setFrameOrigin(exitOrigin)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.panel.orderOut(nil)
            self.isPanelAnimating = false
            self.showEdgeHandle(on: screen)
        })
    }

    private func createApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "NOVA Copilot")

        let aboutItem = NSMenuItem(
            title: "About NOVA Copilot",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let updatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        appMenu.addItem(updatesItem)
        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferencesWindow),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide NOVA Copilot",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let quitItem = NSMenuItem(
            title: "Quit NOVA Copilot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.title = "NOVA Copilot"
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: Selector(("cut:")), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: Selector(("copy:")), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: Selector(("paste:")), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a"))
        editMenuItem.title = "Edit"
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenu = NSMenu(title: "Window")
        let showItem = NSMenuItem(title: "Show NOVA Copilot", action: #selector(showPanelFromMenu), keyEquivalent: "")
        showItem.target = self
        windowMenu.addItem(showItem)

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showPanelFromMenu() { showPanel() }

    @objc private func checkForUpdates() {
        updateStatus.beginCheck()
        updaterController.checkForUpdates(nil)
    }

    @objc private func showPreferencesWindow() {
        if let preferencesWindow {
            NSApp.activate(ignoringOtherApps: true)
            preferencesWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 345),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "NOVA Copilot Preferences"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UpdaterPreferencesView(
            panelState: panelState,
            updateSettings: UpdaterPreferencesState(updater: updaterController.updater),
            onCheckForUpdates: { [weak self] in self?.checkForUpdates() }
        ))
        window.center()
        preferencesWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard updateStatus.isChecking else { return }
        updateStatus.foundUpdate(
            version: item.displayVersionString,
            description: item.itemDescription,
            format: item.itemDescriptionFormat
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let nsError = error as NSError
        let userInfo = nsError.userInfo
        let userInitiated = userInfo[SPUNoUpdateFoundUserInitiatedKey] as? Bool == true
        guard userInitiated else { return }

        let reason = (userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
        let latestVersionReasons = [
            Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue),
            Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue)
        ]
        if let reason, latestVersionReasons.contains(reason) {
            updateStatus.finishUpToDate()
        } else {
            updateStatus.finish("Couldn’t check for updates. Try again shortly.", isError: true)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        guard updateStatus.isChecking else { return }
        updateStatus.finishUpToDate()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard updateStatus.isChecking else { return }
        updateStatus.finish("Update check stopped. Try again.", isError: true)
    }

    private func createMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            let menuBarImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "NOVA Copilot")
            menuBarImage?.isTemplate = true
            menuBarImage?.size = NSSize(width: 16, height: 16)
            button.image = menuBarImage
            button.title = "NOVA"
            button.imagePosition = .imageLeading
            button.toolTip = "Open NOVA Copilot · ⌘⇧Space"
            button.target = self
            button.action = #selector(menuBarButtonPressed)
        }
    }

    @objc private func menuBarButtonPressed() {
        togglePanel()
    }

    private func createEdgeHandle() {
        let size = NSSize(width: 48, height: 124)
        edgeHandlePanel = EdgeHandlePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        edgeHandlePanel.isOpaque = false
        edgeHandlePanel.backgroundColor = .clear
        edgeHandlePanel.hasShadow = false
        edgeHandlePanel.level = .floating
        edgeHandlePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        edgeHandlePanel.isMovableByWindowBackground = false
        edgeHandlePanel.contentView = NSHostingView(rootView: EdgeHandleView(
            onOpen: { [weak self] in self?.showPanel() }
        ))
        positionEdgeHandle()
        edgeHandlePanel.orderFrontRegardless()
    }

    private func positionEdgeHandle(on preferredScreen: NSScreen? = nil) {
        guard let screen = preferredScreen ?? screenUnderPointer() else { return }
        let visibleFrame = screen.visibleFrame
        let frame = edgeHandlePanel.frame
        let visibleWidth: CGFloat = 34
        let x = visibleFrame.maxX - visibleWidth
        let y = visibleFrame.midY - frame.height / 2
        edgeHandlePanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func showEdgeHandle(on screen: NSScreen? = nil) {
        positionEdgeHandle(on: screen)
        edgeHandlePanel.orderFrontRegardless()
    }

    private func createPanel() {
        let rect = NSRect(x: 0, y: 0, width: 425, height: 690)
        panel = FloatingPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "NOVA Copilot"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = NSColor(calibratedWhite: 0.975, alpha: 1)
        panel.hasShadow = true
        panel.minSize = NSSize(width: 370, height: 500)
        panel.level = panelState.isPinned ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.setFrameAutosaveName("NOVACopilotFloatingPanel")
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.onEscape = { [weak self] in self?.hidePanel() }
        panel.contentView = NSHostingView(rootView: AssistantView(
            model: chatModel,
            panelState: panelState,
            onHide: { [weak self] in self?.hidePanel() },
            onQuit: { NSApp.terminate(nil) },
            onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
            onShowPreferences: { [weak self] in self?.showPreferencesWindow() },
            updateStatus: updateStatus
        ))
        placePanelAtRightEdgeIfNeeded()
    }

    private func placePanelAtRightEdgeIfNeeded() {
        if panel.setFrameUsingName("NOVACopilotFloatingPanel") { return }
        guard let screen = screenUnderPointer() else { panel.center(); return }
        let visible = screen.visibleFrame
        let frame = panel.frame
        let x = visible.maxX - frame.width - 16
        let y = max(visible.minY + 16, visible.maxY - frame.height - 16)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func panelTargetOrigin(on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let frame = panel.frame
        let x = max(visible.minX + 12, visible.maxX - frame.width - 12)
        let topAlignedY = visible.maxY - frame.height - 12
        let y = max(visible.minY + 12, topAlignedY)
        return NSPoint(x: x, y: y)
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func screenContainingPanel() -> NSScreen? {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
    }

    private func registerGlobalHotKey() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            novaCopilotHotKeyHandler,
            1,
            &type,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard installStatus == noErr else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F5641), id: 1)
        // Default shortcut: Command + Shift + Space.
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
    }
}

@MainActor
private final class UpdaterPreferencesState: ObservableObject {
    @Published var automaticChecks: Bool {
        didSet { updater.automaticallyChecksForUpdates = automaticChecks }
    }
    @Published var checkInterval: TimeInterval {
        didSet { updater.updateCheckInterval = checkInterval }
    }

    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        automaticChecks = updater.automaticallyChecksForUpdates
        checkInterval = updater.updateCheckInterval
    }
}

private struct UpdaterPreferencesView: View {
    @ObservedObject var panelState: PanelState
    @ObservedObject var updateSettings: UpdaterPreferencesState
    let onCheckForUpdates: () -> Void

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch NOVA at login", isOn: Binding(
                    get: { panelState.launchAtLogin },
                    set: { panelState.setLaunchAtLogin($0) }
                ))
                if let error = panelState.launchLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updateSettings.automaticChecks)
                Picker("Check frequency", selection: $updateSettings.checkInterval) {
                    Text("Daily").tag(TimeInterval(86_400))
                    Text("Weekly").tag(TimeInterval(604_800))
                }
                .disabled(!updateSettings.automaticChecks)
                HStack {
                    Text("You approve each update before it installs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Check Now", action: onCheckForUpdates)
                        .controlSize(.small)
                }
            }

            Section("Keyboard") {
                LabeledContent("Open or hide NOVA", value: "⌘⇧Space")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .frame(width: 390, height: 345)
    }
}
