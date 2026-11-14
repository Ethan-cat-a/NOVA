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
    @Published var isHovered = false
    @Published var isDragging = false
}

private struct EdgeHandleView: View {
    @ObservedObject var state: EdgeHandleViewState
    let onOpen: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onDragChanged: (CGFloat, Bool) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                NovaAvatarView(size: 34, isActive: state.isHovered || state.isDragging)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open NOVA Copilot")

            VStack(alignment: .leading, spacing: 2) {
                Text("NOVA COPILOT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.55)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Ready when you are")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(width: state.isHovered ? 82 : 0, alignment: .leading)
            .opacity(state.isHovered ? 1 : 0)
            .clipped()

            Spacer(minLength: 0)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.58))
                .frame(width: state.isHovered ? 14 : 0, height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            let began = !state.isDragging
                            state.isDragging = true
                            onDragChanged(value.translation.height, began)
                        }
                        .onEnded { _ in
                            state.isDragging = false
                            onDragEnded()
                        }
                )
                .help("Drag to reposition NOVA")
        }
        .padding(.horizontal, 10)
        .frame(width: 176, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.035, green: 0.09, blue: 0.22).opacity(0.98),
                            Color(red: 0.025, green: 0.045, blue: 0.13).opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.cyan.opacity(state.isHovered ? 0.9 : 0.58))
                .frame(width: 2, height: state.isHovered ? 30 : 22)
                .padding(.leading, 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(state.isHovered ? 0.3 : 0.18), lineWidth: 1)
        )
        .shadow(
            color: Color.cyan.opacity(state.isHovered ? 0.4 : 0.18),
            radius: state.isHovered ? 18 : 10,
            x: -6,
            y: 0
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onHover { isHovered in
            guard state.isHovered != isHovered else { return }
            state.isHovered = isHovered
            onHoverChanged(isHovered)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: state.isHovered)
        .help("Open NOVA Copilot · drag the grip to reposition")
    }
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
    private let edgeHandleViewState = EdgeHandleViewState()
    private var edgeHandleScreen: NSScreen?
    private var edgeHandleDragStartY: CGFloat = 0

    private let edgeHandlePositionKey = "NOVAEdgeHandleVerticalPosition"
    private let edgeHandleCollapsedPeek: CGFloat = 48

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restoreEdgeHandle(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restoreEdgeHandle(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Put the launcher on the primary display and retry after the first app event turn,
        // when macOS has finished restoring the screen list and spaces.
        showEdgeHandle(on: primaryScreen(), animated: true)
        DispatchQueue.main.async { [weak self] in
            self?.restoreEdgeHandle(nil)
        }
    }

    @objc private func restoreEdgeHandle(_ notification: Notification?) {
        guard !panel.isVisible else { return }
        showEdgeHandle(on: primaryScreen(), animated: false)
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
        let startOrigin = NSPoint(x: visibleFrame.maxX + 34, y: targetOrigin.y)
        let overshootOrigin = NSPoint(x: targetOrigin.x - 10, y: targetOrigin.y)

        edgeHandleViewState.isHovered = false
        edgeHandleViewState.isDragging = false
        edgeHandlePanel.orderOut(nil)
        panel.alphaValue = 0
        panel.setFrameOrigin(startOrigin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        isPanelAnimating = true

        // Slide in with a small spring overshoot, then settle into place.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.9, 0.22, 1.04)
            panel.animator().setFrameOrigin(overshootOrigin)
            panel.animator().alphaValue = 1
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
        let exitX = (screen?.visibleFrame.maxX ?? panel.frame.maxX) + 34
        let exitOrigin = NSPoint(x: exitX, y: panel.frame.origin.y)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.38, 0.0, 0.82, 0.58)
            panel.animator().setFrameOrigin(exitOrigin)
            panel.animator().alphaValue = 0.84
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.isPanelAnimating = false
            self.showEdgeHandle(on: screen, animated: true)
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
        let showLauncherItem = NSMenuItem(
            title: "Show NOVA Side Launcher",
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
        guard !panel.isVisible else {
            hidePanel()
            return
        }
        showEdgeHandle(on: primaryScreen(), animated: true)
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

    private func createEdgeHandle() {
        let size = NSSize(width: 184, height: 64)
        edgeHandlePanel = EdgeHandlePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        edgeHandlePanel.isOpaque = false
        edgeHandlePanel.backgroundColor = .clear
        edgeHandlePanel.hasShadow = false
        edgeHandlePanel.isFloatingPanel = true
        edgeHandlePanel.hidesOnDeactivate = false
        edgeHandlePanel.becomesKeyOnlyIfNeeded = true
        edgeHandlePanel.worksWhenModal = true
        edgeHandlePanel.level = .floating
        edgeHandlePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        edgeHandlePanel.isMovableByWindowBackground = false
        edgeHandlePanel.contentView = NSHostingView(rootView: EdgeHandleView(
            state: edgeHandleViewState,
            onOpen: { [weak self] in self?.showPanel() },
            onHoverChanged: { [weak self] hovered in self?.setEdgeHandleHovered(hovered) },
            onDragChanged: { [weak self] translation, began in
                self?.updateEdgeHandleDrag(translationY: translation, began: began)
            },
            onDragEnded: { [weak self] in self?.finishEdgeHandleDrag() }
        ))
        positionEdgeHandle()
    }

    private func positionEdgeHandle(on preferredScreen: NSScreen? = nil) {
        guard let screen = preferredScreen ?? screenUnderPointer() else { return }
        edgeHandleScreen = screen
        edgeHandlePanel.setFrameOrigin(edgeHandleOrigin(on: screen, visibleWidth: edgeHandleCollapsedPeek))
    }

    private func showEdgeHandle(on preferredScreen: NSScreen? = nil, animated: Bool = true) {
        guard let screen = preferredScreen ?? screenUnderPointer() else { return }
        edgeHandleScreen = screen
        edgeHandleViewState.isHovered = false
        edgeHandleViewState.isDragging = false
        let target = edgeHandleOrigin(on: screen, visibleWidth: edgeHandleCollapsedPeek)
        guard animated else {
            edgeHandlePanel.setFrameOrigin(target)
            edgeHandlePanel.alphaValue = 1
            edgeHandlePanel.orderFrontRegardless()
            return
        }

        edgeHandlePanel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.maxX + 12,
            y: target.y
        ))
        edgeHandlePanel.alphaValue = 0
        edgeHandlePanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.36
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.92, 0.22, 1.02)
            edgeHandlePanel.animator().setFrameOrigin(target)
            edgeHandlePanel.animator().alphaValue = 1
        })
    }

    private func edgeHandleOrigin(on screen: NSScreen, visibleWidth: CGFloat) -> NSPoint {
        let visibleFrame = screen.visibleFrame
        let frame = edgeHandlePanel.frame
        let minimumY = visibleFrame.minY + 10
        let maximumY = max(minimumY, visibleFrame.maxY - frame.height - 10)
        let savedPosition = UserDefaults.standard.object(forKey: edgeHandlePositionKey) as? Double ?? 0.5
        let normalizedPosition = min(max(savedPosition, 0), 1)
        let y = minimumY + (maximumY - minimumY) * normalizedPosition
        return NSPoint(x: visibleFrame.maxX - visibleWidth, y: y)
    }

    private func setEdgeHandleHovered(_ hovered: Bool) {
        guard edgeHandlePanel.isVisible,
              let screen = edgeHandleScreen ?? screenUnderPointer() else { return }
        let visibleWidth = hovered ? edgeHandlePanel.frame.width : edgeHandleCollapsedPeek
        let target = edgeHandleOrigin(on: screen, visibleWidth: visibleWidth)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hovered ? 0.28 : 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.24, 1.0)
            edgeHandlePanel.animator().setFrameOrigin(target)
        }
    }

    private func updateEdgeHandleDrag(translationY: CGFloat, began: Bool) {
        guard let screen = edgeHandleScreen ?? screenUnderPointer() else { return }
        if began {
            edgeHandleDragStartY = edgeHandlePanel.frame.origin.y
        }

        let visibleFrame = screen.visibleFrame
        let minimumY = visibleFrame.minY + 10
        let maximumY = max(minimumY, visibleFrame.maxY - edgeHandlePanel.frame.height - 10)
        let y = min(max(edgeHandleDragStartY - translationY, minimumY), maximumY)
        let visibleWidth = edgeHandleViewState.isHovered
            ? edgeHandlePanel.frame.width
            : edgeHandleCollapsedPeek
        edgeHandlePanel.setFrameOrigin(NSPoint(x: visibleFrame.maxX - visibleWidth, y: y))
    }

    private func finishEdgeHandleDrag() {
        guard let screen = edgeHandleScreen else { return }
        let visibleFrame = screen.visibleFrame
        let minimumY = visibleFrame.minY + 10
        let maximumY = max(minimumY, visibleFrame.maxY - edgeHandlePanel.frame.height - 10)
        let range = maximumY - minimumY
        let position = range > 0 ? (edgeHandlePanel.frame.origin.y - minimumY) / range : 0.5
        UserDefaults.standard.set(Double(position), forKey: edgeHandlePositionKey)
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
