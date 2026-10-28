import Foundation
import XCTest

final class PromethPythonTests: XCTestCase {
    func testInterpreterIsRelativeToFrameworksAndRequiresExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let python = root.appendingPathComponent("NativServerKit.framework/Resources/mlx-vlm-server/python/bin/python3")
        XCTAssertNil(PromethPython.bundled(frameworksURL: nil))
        XCTAssertNil(PromethPython.bundled(frameworksURL: root))
        try FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: python.path)
        XCTAssertNil(PromethPython.bundled(frameworksURL: root))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        XCTAssertEqual(PromethPython.bundled(frameworksURL: root), python)
    }

    func testWorkersIgnoreHostPythonAndPackagePaths() {
        let environment = PromethPython.environment(inheriting: ["PYTHONHOME": "/host/python", "PYTHONPATH": "/host/packages", "PATH": "/host/bin", "HOME": "/example/home"])
        XCTAssertNil(environment["PYTHONHOME"])
        XCTAssertNil(environment["PYTHONPATH"])
        XCTAssertEqual(environment["PYTHONNOUSERSITE"], "1")
        XCTAssertEqual(environment["PYTHONDONTWRITEBYTECODE"], "1")
        XCTAssertEqual(environment["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(environment["HOME"], "/example/home")
    }
}
