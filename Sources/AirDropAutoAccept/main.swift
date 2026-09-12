import AppKit
import ApplicationServices
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.konaito.airdrop-auto-accept", category: "monitor")

/// A small personal background utility that accepts AirDrop notifications from
/// one configured sender. It deliberately uses the macOS Accessibility API:
/// macOS does not expose AirDrop's incoming-request protocol to third-party
/// apps.
@MainActor
final class AirDropController {
    private let senderName: String
    private let interval: TimeInterval = 0.35
    private let maxNodesPerTree = 1_500
    private var timer: Timer?
    private var lastActionAt = Date.distantPast
    private var lastObservedSignature = ""
    private var pendingDownloadsChoiceUntil: Date?
    private var recentDownloads = Set<String>()

    var isEnabled = true
    var onStatusChange: ((String) -> Void)?

    init(senderName: String? = nil) {
        self.senderName = senderName
            ?? UserDefaults.standard.string(forKey: "SenderName")
            ?? "Pixel 10 Pro Fold"
        recentDownloads = currentDownloadNames()
    }

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scan()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        logger.notice("monitor started for sender=\(self.senderName, privacy: .public)")
        publish("監視中: \(senderName)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func scanNow() {
        scan()
    }

    private func scan() {
        guard isEnabled else { return }
        guard accessibilityTrusted else {
            logger.error("accessibility permission is not granted")
            publish("アクセシビリティ権限が必要")
            return
        }

        if let pendingUntil = pendingDownloadsChoiceUntil {
            if chooseAcceptIfVisible() {
                publish("受け入れを確定しました")
                return
            }
            if chooseDownloadsIfVisible() {
                pendingDownloadsChoiceUntil = nil
                publish("保存先をDownloadsに指定しました")
                return
            }
            if Date() < pendingUntil {
                reportNewDownloads()
                return
            }
            // Some file types accept immediately without showing a location
            // menu. In that case the default macOS AirDrop destination applies.
            pendingDownloadsChoiceUntil = nil
            publish("受け入れ操作を完了しました（標準保存先）")
        }

        let candidates = candidateApplications()
        for application in candidates {
            let axApplication = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = attribute(axApplication, kAXWindowsAttribute) as? [AXUIElement] else {
                continue
            }

            for window in windows {
                let nodes = flatten(window)
                let hasAirDrop = nodes.contains { text(of: $0).localizedCaseInsensitiveContains("AirDrop") }
                let hasSender = nodes.contains { text(of: $0).localizedCaseInsensitiveContains(senderName) }
                guard hasAirDrop, hasSender else {
                    continue
                }

                let signature = nodes
                    .map { text(of: $0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "|")
                let acceptButtons = nodes.filter { node in
                    let role = attribute(node, kAXRoleAttribute) as? String
                    let supportedRoles = [kAXButtonRole, kAXMenuButtonRole, kAXPopUpButtonRole]
                    guard let role, supportedRoles.contains(role) else { return false }
                    return isAcceptControl(node)
                }

                guard let acceptButton = acceptButtons.first else {
                    logger.warning("matched AirDrop request but no accept control: app=\(application.localizedName ?? "unknown", privacy: .public) nodes=\(nodes.count)")
                    continue
                }
                guard Date().timeIntervalSince(lastActionAt) > 1.5 else { return }
                guard signature != lastObservedSignature || Date().timeIntervalSince(lastActionAt) > 5 else {
                    continue
                }

                lastObservedSignature = signature
                lastActionAt = Date()
                let result = AXUIElementPerformAction(acceptButton, kAXPressAction as CFString)
                if result == .success {
                    logger.notice("accepted AirDrop request in app=\(application.localizedName ?? "unknown", privacy: .public)")
                    pendingDownloadsChoiceUntil = Date().addingTimeInterval(4)
                    publish("受け入れメニューを開きました")
                } else {
                    logger.error("accept action failed: result=\(result.rawValue, privacy: .public) app=\(application.localizedName ?? "unknown", privacy: .public)")
                    publish("受け入れ操作に失敗: \(result.rawValue)")
                }
                return
            }
        }

        reportNewDownloads()
    }

    private func candidateApplications() -> [NSRunningApplication] {
        let preferredBundleIDs: Set<String> = [
            "com.apple.finder",
            "com.apple.notificationcenterui",
            "com.apple.UserNotificationCenter",
            "com.apple.systemuiserver",
            "com.apple.controlcenter"
        ]
        let preferredNameFragments = [
            "Finder",
            "Notification Center",
            "通知センター",
            "UserNotificationCenter",
            "SystemUIServer",
            "Control Center",
            "コントロールセンター"
        ]

        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.processIdentifier > 0
        }
        let preferred = running.filter { app in
            if let bundleID = app.bundleIdentifier, preferredBundleIDs.contains(bundleID) {
                return true
            }
            guard let name = app.localizedName else { return false }
            return preferredNameFragments.contains { name.localizedCaseInsensitiveContains($0) }
        }

        // Finder owns the request when its AirDrop window is open. Notification
        // Center/SystemUIServer owns the banner in the normal desktop case.
        // Include the active app as a fallback for macOS UI changes.
        var result = preferred
        if let active = NSWorkspace.shared.frontmostApplication,
           active.processIdentifier > 0,
           !result.contains(where: { $0.processIdentifier == active.processIdentifier }) {
            result.append(active)
        }
        return result
    }

    private func flatten(_ root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var stack = [root]

        while let element = stack.popLast(), result.count < maxNodesPerTree {
            result.append(element)
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                stack.append(contentsOf: children)
            }
        }
        return result
    }

    private func isAcceptControl(_ element: AXUIElement) -> Bool {
        let labels = [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXValueAttribute
        ].compactMap { attribute(element, $0) as? String }
        let acceptedLabels = ["受け入れる", "Accept", "Accept…", "Accept..."]
        return labels.contains { label in
            let normalized = label.replacingOccurrences(of: " ", with: "")
            return acceptedLabels.contains {
                normalized.localizedCaseInsensitiveCompare($0) == .orderedSame
            }
        }
    }

    private func chooseDownloadsIfVisible() -> Bool {
        // The popup can be rendered by a different system UI process than the
        // notification that opened it (notably on newer macOS releases).
        // Search all relevant candidates while the short-lived pending window
        // is active, rather than assuming the original owner remains the same.
        let candidates = candidateApplications()
        for application in candidates {
            let axApplication = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = attribute(axApplication, kAXWindowsAttribute) as? [AXUIElement] else {
                continue
            }
            for window in windows {
                let nodes = flatten(window)
                for node in nodes {
                    let role = attribute(node, kAXRoleAttribute) as? String
                    guard role == kAXMenuItemRole else { continue }
                    let label = text(of: node)
                    guard isDownloadsMenuItem(label) else { continue }
                    if AXUIElementPerformAction(node, kAXPressAction as CFString) == .success {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func chooseAcceptIfVisible() -> Bool {
        let candidates = candidateApplications()
        for application in candidates {
            let axApplication = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = attribute(axApplication, kAXWindowsAttribute) as? [AXUIElement] else {
                continue
            }
            for window in windows {
                let nodes = flatten(window)
                for node in nodes {
                    let role = attribute(node, kAXRoleAttribute) as? String
                    guard role == kAXMenuItemRole else { continue }
                    let label = text(of: node)
                    guard isAcceptMenuItem(label) else { continue }
                    if AXUIElementPerformAction(node, kAXPressAction as CFString) == .success {
                        let appName = application.localizedName ?? "unknown"
                        logger.notice("selected Accept menu item in app=\(appName, privacy: .public)")
                        return true
                    }
                }
            }
        }
        return false
    }

    private func isAcceptMenuItem(_ label: String) -> Bool {
        let normalized = label.replacingOccurrences(of: " ", with: "")
        let acceptedLabels = ["受け入れる", "Accept", "Accept…", "Accept..."]
        return acceptedLabels.contains {
            normalized.localizedCaseInsensitiveCompare($0) == .orderedSame
        }
    }

    private func isDownloadsMenuItem(_ label: String) -> Bool {
        let normalized = label.replacingOccurrences(of: " ", with: "")
        let lowercased = normalized.lowercased()
        if normalized.localizedCaseInsensitiveContains("ダウンロード") && normalized.contains("保存") {
            return true
        }
        if lowercased.contains("save") && lowercased.contains("download") {
            return true
        }
        return lowercased == "downloads" || lowercased == "download"
    }

    private func text(of element: AXUIElement) -> String {
        var pieces: [String] = []
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXRoleDescriptionAttribute] {
            if let value = attribute(element, key) as? String, !value.isEmpty {
                pieces.append(value)
            }
        }
        return pieces.joined(separator: " ")
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func currentDownloadNames() -> Set<String> {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return Set(names)
    }

    private func reportNewDownloads() {
        let current = currentDownloadNames()
        let newNames = current.subtracting(recentDownloads)
        if !newNames.isEmpty {
            publish("Downloadsに保存: \(newNames.sorted().joined(separator: ", "))")
        }
        recentDownloads = current
    }

    private func publish(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChange?(message)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AirDropController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // This is a background-only agent. Keep it out of both the menu bar
        // and the Dock; launchd owns its lifetime after installation.
        NSApp.setActivationPolicy(.prohibited)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

if CommandLine.arguments.contains("--status") {
    print(AXIsProcessTrusted() ? "accessibility=granted" : "accessibility=not-granted")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
