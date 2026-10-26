import Foundation

/// Which native tools the Prometh shell advertises. Hidden tools stay compiled.
enum PromethToolVisibility {
    static func allows(
        _ name: String,
        shellOn: Bool,
        terminalTools: Bool,
        fileWriteTools: Bool,
        chatWork: Bool,
        modelsBrowser: Bool,
        systemMonitorUI: Bool,
        developer: Bool
    ) -> Bool {
        guard shellOn else { return true }
        switch name {
        case "terminal":
            return terminalTools
        case "write_file", "patch":
            return fileWriteTools
        case "chat_work":
            return chatWork
        case "list_models", "switch_model":
            return modelsBrowser
        case "get_system_stats":
            return systemMonitorUI
        case "get_server_stats":
            return developer
        default:
            return true
        }
    }

    static func allowsCurrent(_ name: String) -> Bool {
        allows(
            name,
            shellOn: PromethFlags.promethShell && !PromethFlags.isRunningUnitTests,
            terminalTools: PromethFlags.terminalTools,
            fileWriteTools: PromethFlags.fileWriteTools,
            chatWork: PromethFlags.chatWork,
            modelsBrowser: PromethFlags.modelsBrowser,
            systemMonitorUI: PromethFlags.systemMonitorUI,
            developer: PromethFlags.developer
        )
    }
}
