import Foundation

struct AIToolDescriptor: Equatable {
    let name: String
    let description: String
    let requiresConfirmation: Bool
}

struct AIToolRegistry {
    let tools: [AIToolDescriptor]

    static let live = AIToolRegistry(
        tools: configuredTools(accessMode: .standard)
    )

    static func configured(accessMode: AIAgentAccessMode) -> AIToolRegistry {
        AIToolRegistry(
            tools: configuredTools(accessMode: accessMode)
        )
    }

    func tool(named name: String) -> AIToolDescriptor? {
        tools.first(where: { $0.name == name })
    }

    private static func configuredTools(accessMode: AIAgentAccessMode) -> [AIToolDescriptor] {
        let confirm = accessMode.requiresConfirmationForSideEffects

        var tools: [AIToolDescriptor] = [
            .init(name: "clipboard_read_latest", description: "Read the latest clipboard entry", requiresConfirmation: false),
            .init(name: "clipboard_list_history", description: "List clipboard history entries", requiresConfirmation: false),
            .init(name: "json_validate", description: "Validate JSON", requiresConfirmation: false),
            .init(name: "json_format", description: "Format JSON", requiresConfirmation: false),
            .init(name: "json_minify", description: "Minify JSON", requiresConfirmation: false),
            .init(name: "url_encode", description: "Encode URL text", requiresConfirmation: false),
            .init(name: "url_decode", description: "Decode URL text", requiresConfirmation: false),
            .init(name: "base64_encode", description: "Encode Base64", requiresConfirmation: false),
            .init(name: "base64_decode", description: "Decode Base64", requiresConfirmation: false),
            .init(name: "timestamp_to_date", description: "Convert timestamp to date", requiresConfirmation: false),
            .init(name: "date_to_timestamp", description: "Convert date to timestamp", requiresConfirmation: false),
            .init(name: "regex_find", description: "Find regex matches", requiresConfirmation: false),
            .init(name: "regex_replace_preview", description: "Preview regex replacement", requiresConfirmation: false),
            .init(name: "search_files", description: "Search files", requiresConfirmation: false),
            .init(name: "search_apps", description: "Search apps", requiresConfirmation: false),
            .init(name: "search_system_settings", description: "Search system settings", requiresConfirmation: false),
            .init(name: "open_file", description: "Open a file", requiresConfirmation: confirm),
            .init(name: "open_app", description: "Open an app", requiresConfirmation: confirm),
            .init(name: "open_system_setting", description: "Open a system setting", requiresConfirmation: confirm),
            .init(name: "paste_clipboard_entry", description: "Paste clipboard content to another app", requiresConfirmation: confirm)
        ]

        if accessMode.includesFullAccessTools {
            tools.append(contentsOf: [
                .init(name: "list_directory", description: "List files and directories at a path", requiresConfirmation: false),
                .init(name: "read_file", description: "Read a text file from disk", requiresConfirmation: false),
                .init(name: "write_file", description: "Write text content to a file on disk", requiresConfirmation: confirm),
                .init(name: "run_shell_command", description: "Run a shell command locally", requiresConfirmation: confirm),
                .init(name: "open_url", description: "Open a URL in the default browser", requiresConfirmation: confirm)
            ])
        }

        return tools
    }
}
