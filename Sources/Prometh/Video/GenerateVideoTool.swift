import Foundation
import NativServerKit

enum PromethGenerateVideoTool {
    static let toolName = "generate_video"
    static var run: ((String) async throws -> String)?

    static var definition: MLXChatToolDefinition {
        MLXChatToolDefinition(function: MLXChatFunctionDefinition(
            name: toolName,
            description: "Create one short silent video from a description. The app chooses the model. Do not ask for a model identifier.",
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
