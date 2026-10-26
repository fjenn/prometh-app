import XCTest

final class PromethCreditsTests: XCTestCase {
    func testCreditsNameTheUpstreamProject() {
        XCTAssertEqual(PromethCredits.lines.first, "Built on Nativ")
        XCTAssertTrue(PromethCredits.lines.contains { $0.contains(PromethCredits.upstreamSHA) })
        XCTAssertEqual(PromethCredits.lines.filter { $0.contains("Nativ") }.count, 2)
    }
}
