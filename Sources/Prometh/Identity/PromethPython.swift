import Foundation

/// All shipped workers share the server's relocatable CPython distribution.
enum PromethPython {
    static var bundled: URL? { bundled(frameworksURL: Bundle.main.privateFrameworksURL) }

    static func bundled(frameworksURL: URL?) -> URL? {
        guard let python = frameworksURL?.appendingPathComponent(
            "NativServerKit.framework/Resources/mlx-vlm-server/python/bin/python3"
        ), FileManager.default.isExecutableFile(atPath: python.path) else { return nil }
        return python
    }

    static func interpreter(override: String) -> URL? {
        if let path = ProcessInfo.processInfo.environment[override],
           FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return bundled
    }

    static func reader() -> URL? { interpreter(override: "PROMETH_READER_PYTHON") }
    static func composio() -> URL? { interpreter(override: "PROMETH_COMPOSIO_PYTHON") }
    static func searxng() -> URL? { interpreter(override: "PROMETH_SEARXNG_PYTHON") }

    static func environment(runtime: String? = nil, inheriting environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var result = environment
        result.removeValue(forKey: "PYTHONHOME")
        result.removeValue(forKey: "PYTHONPATH")
        result["PYTHONNOUSERSITE"] = "1"
        result["PYTHONDONTWRITEBYTECODE"] = "1"
        result["PYTHONUNBUFFERED"] = "1"
        // Runtime features must not discover developer-installed executables.
        result["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        if let runtime, let packages = PromethRuntimeLocator.url(relative: "\(runtime)/site-packages") {
            result["PYTHONPATH"] = packages.path
        }
        return result
    }
}
