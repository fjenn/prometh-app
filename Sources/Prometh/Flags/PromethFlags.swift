import Foundation

/// Visibility and wiring switches. Hidden Nativ features stay compiled.
///
/// Override order: `--prometh-flags=` wins, then `UserDefaults` key
/// `prometh.flags.<name>`, then the compiled default.
/// `none` forces every flag off. `all` forces every flag on.
/// A comma list forces those names on and leaves the rest to defaults.
enum PromethFlags {
    enum Name: String, CaseIterable {
        case promethShell
        case nativControlPanel
        case menuBarExtra
        case integrations
        case routines
        case chatWork
        case terminalTools
        case fileWriteTools
        case dashboard
        case developer
        case systemMonitorUI
        case modelsBrowser
        case wakeWord
        case meetingRecorder
        case artifactsLibrary
        case keyedSearchProviders
        case composio
        case legacyConnectorApprovalSheet
        case evilMode
        case video
        case voice
        case images
        case sparkleUpdater
    }

    private static let compiledDefaults: [Name: Bool] = [
        .promethShell: true,
        .nativControlPanel: false,
        .menuBarExtra: false,
        .integrations: false,
        .routines: false,
        .chatWork: false,
        .terminalTools: false,
        .fileWriteTools: false,
        .dashboard: false,
        .developer: false,
        .systemMonitorUI: false,
        .modelsBrowser: false,
        .wakeWord: false,
        .meetingRecorder: false,
        .artifactsLibrary: false,
        .keyedSearchProviders: true,
        .composio: false,
        .legacyConnectorApprovalSheet: false,
        .evilMode: true,
        .video: true,
        .voice: true,
        .images: true,
        .sparkleUpdater: false,
    ]

    static func isOn(
        _ name: Name,
        defaults: UserDefaults = .standard,
        arguments: [String] = CommandLine.arguments
    ) -> Bool {
        if let mode = launchMode(from: arguments) {
            switch mode {
            case .forcedOff:
                return false
            case .all:
                return true
            case .listed(let names) where names.contains(name.rawValue):
                return true
            case .listed:
                break
            }
        }
        let key = "prometh.flags.\(name.rawValue)"
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return compiledDefaults[name] ?? false
    }

    static var promethShell: Bool { isOn(.promethShell) }
    static var nativControlPanel: Bool { isOn(.nativControlPanel) }
    static var menuBarExtra: Bool { isOn(.menuBarExtra) }
    static var integrations: Bool { isOn(.integrations) }
    static var routines: Bool { isOn(.routines) }
    static var chatWork: Bool { isOn(.chatWork) }
    static var terminalTools: Bool { isOn(.terminalTools) }
    static var fileWriteTools: Bool { isOn(.fileWriteTools) }
    static var dashboard: Bool { isOn(.dashboard) }
    static var developer: Bool { isOn(.developer) }
    static var systemMonitorUI: Bool { isOn(.systemMonitorUI) }
    static var modelsBrowser: Bool { isOn(.modelsBrowser) }
    static var wakeWord: Bool { isOn(.wakeWord) }
    static var meetingRecorder: Bool { isOn(.meetingRecorder) }
    static var artifactsLibrary: Bool { isOn(.artifactsLibrary) }
    static var keyedSearchProviders: Bool { isOn(.keyedSearchProviders) }
    static var legacyConnectorApprovalSheet: Bool { isOn(.legacyConnectorApprovalSheet) }
    static var composio: Bool { isOn(.composio) }
    static var evilMode: Bool { isOn(.evilMode) }
    static var video: Bool { isOn(.video) }
    static var voice: Bool { isOn(.voice) }
    static var images: Bool { isOn(.images) }
    static var sparkleUpdater: Bool { isOn(.sparkleUpdater) }

    /// True inside `xcodebuild test`. The launched Prometh app does not set these.
    static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    private enum LaunchMode {
        case forcedOff
        case all
        case listed(Set<String>)
    }

    private static func launchMode(from arguments: [String]) -> LaunchMode? {
        let prefix = "--prometh-flags="
        guard let raw = arguments.first(where: { $0.hasPrefix(prefix) })?.dropFirst(prefix.count) else {
            return nil
        }
        let value = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "none":
            return .forcedOff
        case "all":
            return .all
        default:
            let names = value.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            return .listed(Set(names))
        }
    }
}
