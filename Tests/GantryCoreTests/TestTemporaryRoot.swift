import Foundation

/// Tests normally use the system temporary directory. The override exists so a
/// sandboxed test run can point all fixtures at a writable path without
/// changing what a normal `swift test` does.
enum GantryTestTempRoot {
    static var url: URL {
        if let override = ProcessInfo.processInfo.environment["Gantry_TEST_TMP"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }
}
