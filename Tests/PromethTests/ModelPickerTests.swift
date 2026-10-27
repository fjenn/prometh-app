import XCTest

final class ModelPickerTests: XCTestCase {
    func testSafeBestFitAtEverySupportedMemorySize() throws {
        let catalog = try ModelCatalogLoader.bundled()
        for (ram, expected) in [(8,"safe-qwen2b"),(16,"safe-qwen9b"),(24,"safe-qwen9b"),(36,"safe-qwen9b"),(64,"safe-qwen9b"),(128,"safe-qwen9b")] {
            let choice = PromethModelPicker.choose(.safe, catalog: catalog, memoryGB: ram, freeBytes: .max)
            XCTAssertEqual(choice.model?.id, expected, "\(ram) GB")
            XCTAssertTrue(choice.reason.contains("\(ram) GB Mac"))
        }
    }

    func testEveryFamilyAtEveryMemorySizeRespectsBudgetOrSafeFallback() throws {
        let catalog = try ModelCatalogLoader.bundled()
        for ram in [8,16,24,36,64,128] {
            for family in PromethModelFamily.allCases {
                let choice = PromethModelPicker.choose(family, catalog: catalog, memoryGB: ram, freeBytes: .max)
                if let model = choice.model {
                    if family != .safe { XCTAssertLessThanOrEqual(model.workingMemoryGB * 1.08, choice.budgetGB) }
                    XCTAssertFalse(model.revision.isEmpty)
                    XCTAssertEqual(model.files.reduce(Int64(0)) { $0 + $1.size }, model.downloadBytes)
                    XCTAssertTrue(model.files.allSatisfy { !$0.hash.isEmpty && $0.url.contains(model.revision) })
                } else { XCTAssertFalse(choice.reason.isEmpty) }
            }
        }
    }

    func testResidentsMarginAndSmallestFallback() throws {
        let catalog = try ModelCatalogLoader.bundled()
        XCTAssertEqual(PromethModelPicker.choose(.safe, catalog: catalog, memoryGB:16, freeBytes:.max, residentGB:4).model?.id,"safe-qwen4b")
        XCTAssertEqual(PromethModelPicker.choose(.safe, catalog: catalog, memoryGB:1, freeBytes:.max).model?.id,"safe-llama1b")
        XCTAssertNil(PromethModelPicker.choose(.evil, catalog: catalog, memoryGB:8, freeBytes:.max, residentGB:1).model)
    }

    func testDiskPressureAndManualOverride() throws {
        let catalog = try ModelCatalogLoader.bundled()
        XCTAssertNil(PromethModelPicker.choose(.safe, catalog:catalog, memoryGB:128, freeBytes:1_000_000_000).model)
        let chosen = PromethModelPicker.choose(.safe, catalog:catalog, memoryGB:128, freeBytes:.max, override:"safe-qwen2b")
        XCTAssertEqual(chosen.model?.id,"safe-qwen2b")
        XCTAssertTrue(chosen.reason.hasPrefix("Manual choice"))
        XCTAssertEqual(PromethModelPicker.choose(.safe, catalog:catalog, memoryGB:128, freeBytes:.max, override:"safe").model?.id,"safe")
    }

    func testAutomaticPickDropsLegacyGemmaDefault() throws {
        let catalog = try ModelCatalogLoader.bundled()
        let gemma = try XCTUnwrap(catalog.model(id: "safe"))
        XCTAssertTrue(gemma.repo.contains("gemma"))
        let pick = PromethModelPicker.choose(.safe, catalog: catalog, memoryGB: 128, freeBytes: .max)
        XCTAssertEqual(pick.model?.id, "safe-qwen9b")
        XCTAssertNotEqual(pick.model?.repo, gemma.repo)
        // Gemma remains a manual option only.
        XCTAssertTrue(PromethModelPicker.options(.safe, catalog: catalog).contains { $0.id == "safe" })
    }

    func testMediaBestFitAcrossRAMTiers() throws {
        // Budgets: RAM*0.75-1 with residentGB=0 (chat unloads before media).
        // Measured workingMemoryGB: images=6.0, video=6.0, video-5b=27.0, images-9b=14, video-14b=28.
        // 8 GB budget 5.0 → neither photo nor video (6*1.08=6.48 > 5.0).
        let catalog = try ModelCatalogLoader.bundled()
        let expectedImages: [(Int, String?)] = [
            (8, nil),
            (16, "images"),
            (24, "images-9b"),
            (36, "images-9b"),
            (48, "images-9b"),
            (64, "images-9b"),
            (128, "images-9b"),
        ]
        let expectedVideo: [(Int, String?)] = [
            (8, nil),
            (16, "video"),
            (24, "video"),
            (36, "video"),
            (48, "video-14b"),
            (64, "video-14b"),
            (128, "video-14b"),
        ]
        for (ram, expected) in expectedImages {
            let choice = PromethModelPicker.choose(.images, catalog: catalog, memoryGB: ram, freeBytes: .max)
            XCTAssertEqual(choice.model?.id, expected, "images @ \(ram) GB")
        }
        for (ram, expected) in expectedVideo {
            let choice = PromethModelPicker.choose(.video, catalog: catalog, memoryGB: ram, freeBytes: .max)
            XCTAssertEqual(choice.model?.id, expected, "video @ \(ram) GB")
        }
        // Mid 5B fits the 48 GB budget but loses to 14B in best-first; confirm it is enabled and options-listed.
        XCTAssertTrue(PromethModelPicker.options(.video, catalog: catalog).contains { $0.id == "video-5b" })
        let mid = try XCTUnwrap(catalog.model(id: "video-5b"))
        XCTAssertTrue(mid.enabled)
        XCTAssertEqual(mid.workingMemoryGB, 27.0, accuracy: 0.01)
        // 8 GB eligibility gate: measured peaks * 1.08 must be ≤ 5.0 — neither media family qualifies.
        XCTAssertNil(PromethModelPicker.choose(.images, catalog: catalog, memoryGB: 8, freeBytes: .max).model)
        XCTAssertNil(PromethModelPicker.choose(.video, catalog: catalog, memoryGB: 8, freeBytes: .max).model)
    }
}
