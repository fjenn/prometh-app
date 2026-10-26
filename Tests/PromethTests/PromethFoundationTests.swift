import XCTest

final class PromethFoundationTests: XCTestCase {
    func testIdentityNames() {
        XCTAssertEqual(PromethIdentity.productName, "Prometh")
        XCTAssertEqual(PromethIdentity.bundleIdentifier, "studio.prometh.Prometh")
        XCTAssertEqual(PromethIdentity.supportDirectoryName, "Prometh")
    }

    func testSupportOverrideReplacesTheRealFolder() {
        let directory = URL(fileURLWithPath: "/tmp/prometh-support-test", isDirectory: true)
        let previous = ProcessInfo.processInfo.environment["PROMETH_SUPPORT_DIR"]
        setenv("PROMETH_SUPPORT_DIR", directory.path, 1)
        defer {
            if let previous {
                setenv("PROMETH_SUPPORT_DIR", previous, 1)
            } else {
                unsetenv("PROMETH_SUPPORT_DIR")
            }
        }
        XCTAssertEqual(
            PromethIdentity.appendingSupportDirectory(to: URL(fileURLWithPath: "/unused")).path,
            directory.path
        )
    }

    func testFlagDefaultsAndLaunchOverrides() {
        let defaults = UserDefaults(suiteName: "PromethFoundationTests.\(UUID().uuidString)")!
        XCTAssertTrue(PromethFlags.isOn(.promethShell, defaults: defaults, arguments: []))
        XCTAssertFalse(PromethFlags.isOn(.menuBarExtra, defaults: defaults, arguments: []))
        XCTAssertFalse(PromethFlags.isOn(.sparkleUpdater, defaults: defaults, arguments: []))
        XCTAssertFalse(PromethFlags.isOn(.routines, defaults: defaults, arguments: []))
        XCTAssertTrue(PromethFlags.isOn(.images, defaults: defaults, arguments: []))

        XCTAssertFalse(
            PromethFlags.isOn(.promethShell, defaults: defaults, arguments: ["--prometh-flags=none"])
        )
        XCTAssertTrue(
            PromethFlags.isOn(.sparkleUpdater, defaults: defaults, arguments: ["--prometh-flags=all"])
        )
        XCTAssertTrue(
            PromethFlags.isOn(.menuBarExtra, defaults: defaults, arguments: ["--prometh-flags=menuBarExtra"])
        )
        XCTAssertTrue(
            PromethFlags.isOn(.promethShell, defaults: defaults, arguments: ["--prometh-flags=menuBarExtra"])
        )

        defaults.set(false, forKey: "prometh.flags.promethShell")
        XCTAssertFalse(PromethFlags.isOn(.promethShell, defaults: defaults, arguments: []))
        XCTAssertFalse(
            PromethFlags.isOn(.images, defaults: defaults, arguments: ["--prometh-flags=none"])
        )
    }

    func testDesignTokensMatchTheSpec() {
        XCTAssertEqual(PromethDesign.promethInk, 0x292B35)
        XCTAssertEqual(PromethDesign.sky, 0x83CFF0)
        XCTAssertEqual(PromethDesign.lavender, 0xB8ACE4)
        XCTAssertEqual(PromethDesign.coral, 0xF28779)
        XCTAssertEqual(PromethDesign.butter, 0xF5CE65)
        XCTAssertEqual(PromethDesign.sage, 0xA9CDB4)
        XCTAssertEqual(PromethDesign.readingSurfaceLight, 0xFAF9F6)
        XCTAssertEqual(PromethDesign.readingSurfaceDark, 0x20232B)
        XCTAssertEqual(PromethDesign.sidebarLight, 0xF4F3F1)
        XCTAssertEqual(PromethDesign.sidebarDarkTop, 0x29313C)
        XCTAssertEqual(PromethDesign.sidebarDarkMid, 0x302D3B)
        XCTAssertEqual(PromethDesign.sidebarDarkBottom, 0x2B2E32)
        XCTAssertEqual(PromethDesign.settingsLight, 0xF8F7F4)
        XCTAssertEqual(PromethDesign.settingsDark, 0x22252B)
        XCTAssertEqual(PromethDesign.appTintLight, 0x646491)
        XCTAssertEqual(PromethDesign.evilBorderStart, 0xE06B62)
        XCTAssertEqual(PromethDesign.evilBorderMid, 0xD4788C)
        XCTAssertEqual(PromethDesign.evilBorderEnd, 0xA67BB8)
        XCTAssertEqual(PromethDesign.evilReveal, 0x4A090C)
        XCTAssertEqual(PromethDesign.destructiveFill, 0x9B292A)
        XCTAssertEqual(PromethDesign.chatProgress, 0x3AA0D8)
        XCTAssertEqual(PromethDesign.voiceProgress, 0x6E5CC0)
        XCTAssertEqual(PromethDesign.imagesProgress, 0xD7A63A)
        XCTAssertEqual(PromethDesign.videoProgress, 0xE36B5C)
        XCTAssertEqual(PromethDesign.voiceBarHeights, [7, 13, 9, 15, 8])
        XCTAssertEqual(PromethDesign.composerRadius, 28)
        XCTAssertEqual(PromethDesign.windowMinWidth, 960)
        XCTAssertEqual(PromethDesign.windowMinHeight, 650)
        XCTAssertEqual(Capability.chat.gigabytes, 5.18)
        XCTAssertEqual(Capability.images.gigabytes, 4.62)
        var selected: Set<Capability> = [.chat]
        let before = selected.reduce(0) { $0 + $1.gigabytes }
        selected.insert(.images)
        XCTAssertEqual(selected.reduce(0) { $0 + $1.gigabytes } - before, 4.62, accuracy: 0.001)
    }

    func testPromethUICopyHasNoRepositoryIdentifiers() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Prometh/UI")
        let repo = #/[A-Za-z][A-Za-z0-9-]*\/[A-Za-z0-9._-]+/#
        let literal = #/"(?:[^"\\]|\\.)*"/#
        var matches: [String] = []
        let files = try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.components(separatedBy: "\n") {
                guard line.contains("Text(") || line.contains("Label(") else { continue }
                if line.contains("DisclosureGroup(\"Details\")") { continue }
                for item in line.matches(of: literal) {
                    let quoted = String(item.0)
                    guard let found = quoted.firstMatch(of: repo) else { continue }
                    matches.append("\(file.lastPathComponent): \(found.0)")
                }
            }
        }
        XCTAssertEqual(matches, [])
    }
}
