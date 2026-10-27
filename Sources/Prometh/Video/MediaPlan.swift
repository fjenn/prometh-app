import Foundation

/// Prometh's image default. Nativ's `fallbackModelID` stays the 8-bit id.
enum PromethImageDefaults {
    static let modelID = "Runpod/FLUX.2-klein-4B-mflux-4bit"
    static let revision = "7ee1b3aa8178a1240050490072196a57da2bf2a9"
    static let nativFallback = "mlx-community/flux2-klein-4b-8bit"

    static func resolved(current: String?) -> String {
        if let current, !current.isEmpty, current != nativFallback {
            return current
        }
        return modelID
    }
}

enum PromethVideoPlan {
    static let fastVideoCommit = "8db2d71ef217e84bec7dbb6e4ab65c92b144df4f"
    static let width = 832
    static let height = 480
    static let seconds = 5.0

    static func trimDuration(start: Double, end: Double) -> Double? {
        guard start >= 0, end - start > 0.05 else { return nil }
        return end - start
    }
}

enum PromethVideoResult {
    static func artifact(from payload: String, prompt: String) -> PromethArtifact? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["ok"] as? Bool) == true,
              let plan = json["plan"] as? [String: Any],
              let output = plan["output"] as? String
        else { return nil }
        let seconds = plan["seconds"] as? Double ?? PromethVideoPlan.seconds
        let version = plan["version"] as? Int ?? 1
        let trimStart = plan["trim_start"] as? Double ?? 0
        let trimEnd = plan["trim_end"] as? Double ?? seconds
        return PromethArtifact(
            kind: "video",
            filename: URL(fileURLWithPath: output).lastPathComponent,
            prompt: prompt,
            version: version,
            trimStart: trimStart,
            trimEnd: trimEnd,
            duration: seconds
        )
    }
}
