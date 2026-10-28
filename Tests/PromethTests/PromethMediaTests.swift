import XCTest

final class PromethMediaTests: XCTestCase {
    func testImageDefaultPrefersTheFourBitCatalogModel() throws {
        XCTAssertEqual(PromethImageDefaults.resolved(current: nil), PromethImageDefaults.modelID)
        XCTAssertEqual(
            PromethImageDefaults.resolved(current: PromethImageDefaults.nativFallback),
            PromethImageDefaults.modelID
        )
        XCTAssertEqual(PromethImageDefaults.resolved(current: "custom/model"), "custom/model")
        let catalog = try ModelCatalogLoader.bundled()
        let images = try XCTUnwrap(catalog.model(id: "images"))
        XCTAssertEqual(images.repo, PromethImageDefaults.modelID)
        XCTAssertEqual(images.revision, PromethImageDefaults.revision)
        XCTAssertEqual(images.name, "FLUX.2 Klein 4B · 4-bit")
        let zimage = try XCTUnwrap(catalog.model(id: "zimage"))
        XCTAssertFalse(zimage.enabled)
    }

    func testTrimFromOneToThreeIsTwoSeconds() {
        let duration = PromethVideoPlan.trimDuration(start: 1.0, end: 3.0)
        XCTAssertEqual(duration ?? -1, 2.0, accuracy: 0.1)
        XCTAssertNil(PromethVideoPlan.trimDuration(start: 3, end: 1))
    }

    func testVideoPayloadBecomesAnArtifactAndKeepsTheOriginal() {
        let payload = """
        {"ok":true,"plan":{"output":"/tmp/clip.mp4","poster":"/tmp/clip.png","seconds":5,"width":832,"height":480}}
        """
        let artifact = PromethVideoResult.artifact(from: payload, prompt: "waves at sunset")
        XCTAssertEqual(artifact?.filename, "clip.mp4")
        XCTAssertEqual(artifact?.version, 1)
        XCTAssertEqual(artifact?.duration ?? 0, 5, accuracy: 0.01)
        XCTAssertEqual(PromethVideoPlan.width, 832)
        XCTAssertEqual(PromethVideoPlan.height, 480)
        XCTAssertEqual(PromethVideoPlan.fastVideoCommit, "8db2d71ef217e84bec7dbb6e4ab65c92b144df4f")
    }

    func testTrimVideoPayloadBecomesVersionTwo() {
        let payload = """
        {"ok":true,"plan":{"output":"/tmp/clip-trimmed.mp4","poster":"/tmp/clip-trimmed.png","seconds":2,"width":832,"height":480,"version":2,"trim_start":1.0,"trim_end":3.0,"keep_original":true}}
        """
        let artifact = PromethVideoResult.artifact(from: payload, prompt: "trim")
        XCTAssertEqual(artifact?.filename, "clip-trimmed.mp4")
        XCTAssertEqual(artifact?.version, 2)
        XCTAssertEqual(artifact?.duration ?? 0, 2, accuracy: 0.01)
        XCTAssertEqual(artifact?.trimStart ?? -1, 1.0, accuracy: 0.01)
        XCTAssertEqual(artifact?.trimEnd ?? -1, 3.0, accuracy: 0.01)
    }

    func testVideoToolSanitizerHidesPaths() {
        let raw = """
        {"ok":true,"plan":{"output":"/tmp/ABC.mp4","poster":"/tmp/ABC.png","seconds":5,"trim_start":1.0,"trim_end":3.0}}
        """
        let scrubbed = PromethToolResultSanitizer.modelFacing(toolName: "trim_video", content: raw)
        XCTAssertFalse(scrubbed.contains("/tmp/"))
        XCTAssertFalse(scrubbed.contains("ABC.mp4"))
        XCTAssertTrue(scrubbed.contains("ok"))
    }
}

extension PromethMediaTests {
    func testRealVideoLogStagesAdvanceThroughDenoisingDecodeAndOutput() throws {
        var progress = PromethVideoProgress()
        XCTAssertEqual(progress.consume(#"{"event":"progress","fraction":0.1}"#), 0.1)
        for step in 1...3 {
            let log = try JSONSerialization.data(withJSONObject: ["event": "log", "line": "denoise step \(step)/3 complete"])
            XCTAssertEqual(try XCTUnwrap(progress.consume(String(decoding: log, as: UTF8.self))), 0.15 + 0.65 * Double(step) / 3, accuracy: 0.0001)
        }
        XCTAssertEqual(progress.consume("[Prometh] Wan VAE fp16: 256px tiles / 192px stride / 1 latent frame"), 0.85)
        XCTAssertEqual(progress.consume("Output written to: /tmp/clip.mp4"), 1)
        XCTAssertNil(progress.consume(#"{"ok":true,"event":"done","plan":{}}"#))
    }

    func testVideoProgressNeverRegressesAndIgnoresMalformedOrFailedStages() {
        var progress = PromethVideoProgress()
        XCTAssertNil(progress.consume("loading tensor weights"))
        for line in ["denoise step 0/3 complete", "denoise step 4/3 complete", "denoise step 1/0 complete", #"{"event":"progress","fraction":2}"#, #"{"event":"done","ok":false}"#] {
            XCTAssertNil(progress.consume(line), line)
        }
        XCTAssertEqual(progress.consume("denoise step 3/3 complete") ?? 0, 0.8, accuracy: 0.0001)
        XCTAssertNil(progress.consume("denoise step 1/3 complete"))
        XCTAssertNil(progress.consume(#"{"event":"progress","fraction":0.1}"#))
        XCTAssertEqual(progress.consume("[Prometh] TAEHV bf16: tile decode"), 0.85)
        XCTAssertNil(progress.consume("denoise step 3/3 complete"))
        XCTAssertEqual(progress.consume(#"{"event":"done","ok":true}"#), 1)
    }
}
