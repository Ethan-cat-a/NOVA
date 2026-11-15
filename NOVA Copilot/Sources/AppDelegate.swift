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

struct NovaAvatarView: View {
    let size: CGFloat
    var isActive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.08, green: 0.27, blue: 0.58),
                            Color(red: 0.015, green: 0.045, blue: 0.14)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.95
                    )
                )

            Image("MenuBarIcon")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(size * 0.16)
                .shadow(color: Color.cyan.opacity(0.72), radius: size * 0.12)

            HStack(spacing: size * 0.11) {
                avatarEye
                avatarEye
            }
            .offset(y: size * 0.16)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.72), Color.cyan.opacity(0.24), Color.white.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.8, size * 0.035)
                )

            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: size * 0.075, height: size * 0.075)
                .shadow(color: Color.cyan.opacity(0.9), radius: size * 0.09)
                .offset(x: size * 0.27, y: -size * 0.25)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: max(0.6, size * 0.025)))
        .shadow(
            color: Color.cyan.opacity(isActive && isBreathing ? 0.48 : 0.16),
            radius: isActive && isBreathing ? size * 0.34 : size * 0.14
        )
        .scaleEffect(isActive && isBreathing ? 1.045 : 1)
        .onAppear { updateBreathing(isActive) }
        .onChange(of: isActive) { updateBreathing($0) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("NOVA AI avatar")
    }

    private var avatarEye: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: max(2, size * 0.1), height: max(3.5, size * 0.18))
            .overlay(Capsule().stroke(Color.blue.opacity(0.65), lineWidth: max(0.45, size * 0.018)))
            .shadow(color: Color.cyan.opacity(0.85), radius: max(0.8, size * 0.04))
    }

    private func updateBreathing(_ active: Bool) {
        guard active, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.18)) { isBreathing = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
    }
}

@MainActor
private final class EdgeHandleViewState: ObservableObject {
    @Published var isDragging = false
    @Published var isDrawerOpen = false
}

private struct DrawerGripView: View {
    @ObservedObject var state: EdgeHandleViewState
    let onToggle: () -> Void
    let onDragChanged: (Bool) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.black.opacity(0.14)))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.42))
                        .frame(width: 1, height: 22)
                }
                .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.14), radius: 5, x: -2, y: 0)
                .frame(width: 20, height: 92)

            VStack(spacing: 10) {
                Image(systemName: state.isDrawerOpen ? "chevron.right" : "chevron.left")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .accessibilityHidden(true)

                VStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.66))
                            .frame(width: 7, height: 1.5)
                    }
                }
                .accessibilityHidden(true)

                Circle()
                    .fill(Color.cyan.opacity(0.78))
                    .frame(width: 3, height: 3)
                    .shadow(color: Color.cyan.opacity(0.7), radius: 3)
            }
            .frame(width: 20, height: 92)
        }
        .frame(width: 28, height: 108, alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in
                    let began = !state.isDragging
                    state.isDragging = true
                    onDragChanged(began)
                }
                .onEnded { _ in
                    onDragEnded()
                    state.isDragging = false
                }
        )
        .help(state.isDrawerOpen ? "Push right to tuck NOVA away" : "Pull left to open NOVA")
        .accessibilityLabel(state.isDrawerOpen ? "Close NOVA Copilot drawer" : "Open NOVA Copilot drawer")
        .accessibilityAddTraits(.isButton)
    }
}

private struct DrawerPanelContent: View {
    @ObservedObject var state: EdgeHandleViewState
    let assistant: AssistantView
    let onToggle: () -> Void
    let onDragChanged: (Bool) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            DrawerGripView(
                state: state,
                onToggle: onToggle,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded
            )
        .frame(width: 28, height: 108, alignment: .trailing)

            Group {
                if state.isDrawerOpen {
                    assistant
                } else {
                    Color.clear
                }
            }
            .frame(width: 425, height: 690)
        }
        .frame(width: 453, height: 690, alignment: .leading)
        .background(Color.clear)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private let chatModel = NovaChatModel()
    private let panelState = PanelState()
    private let updateStatus = UpdaterStatus()
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var updaterController: SPUStandardUpdaterController!
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var isPanelAnimating = false
    private var preferencesWindow: NSWindow?
    private let edgeHandleViewState = EdgeHandleViewState()
    private var edgeHandleScreen: NSScreen?
    private var drawerDragStartOrigin = NSPoint.zero
    private var drawerDragStartPointer = NSPoint.zero

    private let edgeHandlePositionKey = "NOVAEdgeHandleVerticalPosition"
    private let drawerGripWidth: CGFloat = 28
    private let drawerWidth: CGFloat = 453
    private let drawerHeight: CGFloat = 690

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
        registerGlobalHotKey()

        panelState.onPinChanged = { [weak self] pinned in
            guard let self else { return }
            self.panel.level = pinned || !self.edgeHandleViewState.isDrawerOpen ? .floating : .normal
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restoreDrawer(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restoreDrawer(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        positionDrawer(on: primaryScreen() ?? screenUnderPointer(), open: false)
        panel.orderFrontRegardless()
    }

    @objc private func restoreDrawer(_ notification: Notification?) {
        guard !edgeHandleViewState.isDragging,
              let screen = screenContainingPanel() ?? primaryScreen() else { return }
        positionDrawer(on: screen, open: edgeHandleViewState.isDrawerOpen)
        panel.orderFrontRegardless()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await NovaAccountStore.shared.handleGoogleOAuthCallback(url) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !edgeHandleViewState.isDrawerOpen { setDrawerOpen(true, animated: true) }
        return true
    }

    func togglePanel() {
        guard !isPanelAnimating else { return }
        setDrawerOpen(!edgeHandleViewState.isDrawerOpen, animated: true)
    }

    private func showPanel() {
        setDrawerOpen(true, animated: true)
    }

    private func hidePanel() {
        setDrawerOpen(false, animated: true)
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
        let showItem = NSMenuItem(title: "Open NOVA Drawer", action: #selector(showPanelFromMenu), keyEquivalent: "")
        showItem.target = self
        windowMenu.addItem(showItem)
        let showLauncherItem = NSMenuItem(
            title: "Show NOVA Drawer Handle",
            action: #selector(showEdgeLauncherFromMenu),
            keyEquivalent: ""
        )
        showLauncherItem.target = self
        windowMenu.addItem(showLauncherItem)

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showPanelFromMenu() { showPanel() }

    @objc private func showEdgeLauncherFromMenu() {
        guard let screen = primaryScreen() ?? screenUnderPointer() else { return }
        edgeHandleViewState.isDrawerOpen = false
        panel.level = .floating
        positionDrawer(on: screen, open: false)
        panel.orderFrontRegardless()
    }

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
            let menuBarImage = makeMenuBarAvatarImage()
            button.image = menuBarImage
            button.title = "NOVA"
            button.imagePosition = .imageLeading
            button.toolTip = "Open NOVA Copilot · ⌘⇧Space"
            button.target = self
            button.action = #selector(menuBarButtonPressed)
        }
    }

    private func makeMenuBarAvatarImage() -> NSImage? {
        guard let orbitalMark = NSImage(named: NSImage.Name("MenuBarIcon")) else { return nil }
        let imageSize = NSSize(width: 18, height: 18)
        let avatar = NSImage(size: imageSize, flipped: false) { bounds in
            orbitalMark.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: false,
                hints: nil
            )

            let eyeSize = NSSize(width: 1.9, height: 2.8)
            let eyeSpacing: CGFloat = 2.3
            let eyeY = bounds.midY - 2.8
            let eyeOrigins = [
                bounds.midX - eyeSpacing / 2 - eyeSize.width,
                bounds.midX + eyeSpacing / 2
            ]
            for x in eyeOrigins {
                let eye = NSBezierPath(ovalIn: NSRect(origin: NSPoint(x: x, y: eyeY), size: eyeSize))
                NSColor.white.setFill()
                eye.fill()
                NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.2, alpha: 0.78).setStroke()
                eye.lineWidth = 0.45
                eye.stroke()
            }
            return true
        }
        avatar.isTemplate = false
        return avatar
    }

    @objc private func menuBarButtonPressed() {
        togglePanel()
    }

    private func setDrawerOpen(_ open: Bool, animated: Bool) {
        guard !isPanelAnimating, let screen = screenContainingPanel() ?? screenUnderPointer() ?? primaryScreen() else { return }
        edgeHandleScreen = screen
        if open {
            edgeHandleViewState.isDrawerOpen = true
            panel.level = panelState.isPinned ? .floating : .normal
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
        let target = drawerOrigin(on: screen, open: open, y: panel.frame.origin.y)
        guard animated else {
            edgeHandleViewState.isDrawerOpen = open
            panel.level = (panelState.isPinned || !open) ? .floating : .normal
            panel.setFrameOrigin(target)
            panel.orderFrontRegardless()
            return
        }

        isPanelAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = open ? 0.32 : 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.88, 0.22, 1.0)
            panel.animator().setFrameOrigin(target)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.edgeHandleViewState.isDrawerOpen = open
                self.panel.level = (self.panelState.isPinned || !open) ? .floating : .normal
                self.panel.orderFrontRegardless()
                if open {
                    NSApp.activate(ignoringOtherApps: true)
                    self.panel.makeKeyAndOrderFront(nil)
                }
                self.isPanelAnimating = false
            }
        }
    }

    private func updateDrawerDrag(began: Bool) {
        guard let screen = screenContainingPanel() ?? edgeHandleScreen ?? screenUnderPointer() else { return }
        if began {
            drawerDragStartOrigin = panel.frame.origin
            drawerDragStartPointer = NSEvent.mouseLocation
            if !edgeHandleViewState.isDrawerOpen {
                edgeHandleViewState.isDrawerOpen = true
                panel.level = .floating
            }
        }
        let visible = screen.visibleFrame
        let closedX = visible.maxX - drawerGripWidth
        let openX = visible.maxX - drawerWidth
        let pointer = NSEvent.mouseLocation
        let deltaX = pointer.x - drawerDragStartPointer.x
        let deltaY = pointer.y - drawerDragStartPointer.y
        let x = min(max(drawerDragStartOrigin.x + deltaX, openX), closedX)
        let minimumY = visible.minY + 12
        let maximumY = max(minimumY, visible.maxY - drawerHeight - 12)
        let y = min(max(drawerDragStartOrigin.y + deltaY, minimumY), maximumY)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    private func finishDrawerDrag() {
        guard let screen = screenContainingPanel() ?? edgeHandleScreen ?? screenUnderPointer() else { return }
        let visible = screen.visibleFrame
        let openX = visible.maxX - drawerWidth
        let closedX = visible.maxX - drawerGripWidth
        let midpointX = openX + (closedX - openX) / 2
        // At halfway, choose open so a partial pull does not make the drawer disappear.
        let shouldOpen = panel.frame.origin.x <= midpointX
        let minimumY = visible.minY + 12
        let maximumY = max(minimumY, visible.maxY - drawerHeight - 12)
        let y = min(max(panel.frame.origin.y, minimumY), maximumY)
        let range = max(1, maximumY - minimumY)
        UserDefaults.standard.set(Double((y - minimumY) / range), forKey: edgeHandlePositionKey)
        let target = drawerOrigin(on: screen, open: shouldOpen, y: y)
        isPanelAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.24, 1.0)
            panel.animator().setFrameOrigin(target)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.edgeHandleViewState.isDrawerOpen = shouldOpen
                self.panel.level = (self.panelState.isPinned || !shouldOpen) ? .floating : .normal
                if shouldOpen {
                    NSApp.activate(ignoringOtherApps: true)
                    self.panel.makeKeyAndOrderFront(nil)
                }
                self.panel.orderFrontRegardless()
                self.isPanelAnimating = false
            }
        }
    }

    private func createPanel() {
        let rect = NSRect(x: 0, y: 0, width: drawerWidth, height: drawerHeight)
        panel = FloatingPanel(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "NOVA Copilot"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.setFrameAutosaveName("NOVACopilotDrawerPanel")
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.onEscape = { [weak self] in self?.hidePanel() }
        let assistant = AssistantView(
            model: chatModel,
            panelState: panelState,
            onHide: { [weak self] in self?.hidePanel() },
            onQuit: { NSApp.terminate(nil) },
            onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
            onShowPreferences: { [weak self] in self?.showPreferencesWindow() },
            updateStatus: updateStatus
        )
        panel.contentView = NSHostingView(rootView: DrawerPanelContent(
            state: edgeHandleViewState,
            assistant: assistant,
            onToggle: { [weak self] in self?.togglePanel() },
            onDragChanged: { [weak self] began in self?.updateDrawerDrag(began: began) },
            onDragEnded: { [weak self] in self?.finishDrawerDrag() }
        ))
        panel.setFrameOrigin(NSPoint(x: 0, y: 0))
    }

    private func positionDrawer(on screen: NSScreen?, open: Bool) {
        guard let screen else { return }
        edgeHandleScreen = screen
        panel.setFrameOrigin(drawerOrigin(on: screen, open: open, y: nil))
    }

    private func drawerOrigin(on screen: NSScreen, open: Bool, y requestedY: CGFloat?) -> NSPoint {
        let visible = screen.visibleFrame
        let minimumY = visible.minY + 12
        let maximumY = max(minimumY, visible.maxY - drawerHeight - 12)
        let normalized = min(max(UserDefaults.standard.object(forKey: edgeHandlePositionKey) as? Double ?? 0.5, 0), 1)
        let y = min(max(requestedY ?? (minimumY + (maximumY - minimumY) * normalized), minimumY), maximumY)
        let x = open ? visible.maxX - drawerWidth : visible.maxX - drawerGripWidth
        return NSPoint(x: x, y: y)
    }

    private func primaryScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func screenContainingPanel() -> NSScreen? {
        let gripCenter = NSPoint(x: panel.frame.minX + drawerGripWidth / 2, y: panel.frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(gripCenter) })
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
