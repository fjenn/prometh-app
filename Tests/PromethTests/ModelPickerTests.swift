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
}
