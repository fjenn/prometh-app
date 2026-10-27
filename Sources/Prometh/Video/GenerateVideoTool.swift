import Foundation
import NativServerKit

enum PromethGenerateVideoTool {
    static let toolName = "generate_video"
    nonisolated(unsafe) static var run: ((String) async throws -> String)?

    static var definition: MLXChatToolDefinition {
        MLXChatToolDefinition(function: MLXChatFunctionDefinition(
            name: toolName,
            description: "Create one short silent video from a description. The app chooses the model. Do not ask for a model identifier. To trim an existing clip afterward, use trim_video.",
            parameters: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "prompt": .object([
                        "type": .string("string"),
                        "description": .string("What the clip should show.")
                    ])
                ]),
                "required": .array([.string("prompt")])
            ])
        ))
    }

    static func outcome(for arguments: String) async throws -> String {
        guard let run else {
            return #"{"ok":false,"error":"Video is not ready yet."}"#
        }
        return try await run(arguments)
    }
}

enum PromethTrimVideoTool {
    static let toolName = "trim_video"
    nonisolated(unsafe) static var run: ((String) async throws -> String)?

    static var definition: MLXChatToolDefinition {
        MLXChatToolDefinition(function: MLXChatFunctionDefinition(
            name: toolName,
            description: "Trim the most recent video clip in this chat to a time range and keep the original as Version 1. Use when the user asks to trim, cut, or shorten a clip. Do not mention file paths or identifiers.",
            parameters: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "start": .object([
                        "type": .string("number"),
                        "description": .string("In-point in seconds (inclusive).")
                    ]),
                    "end": .object([
                        "type": .string("number"),
                        "description": .string("Out-point in seconds (exclusive of leftover tail).")
                    ]),
                    "keep_original": .object([
                        "type": .string("boolean"),
                        "description": .string("When true (default), keep the original clip and create a new version.")
                    ])
                ]),
                "required": .array([.string("start"), .string("end")])
            ])
        ))
    }

    static func outcome(for arguments: String) async throws -> String {
        guard let run else {
            return #"{"ok":false,"error":"Video trim is not ready yet. Open Preview → Edit video."}"#
        }
        return try await run(arguments)
    }
}
