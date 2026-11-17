import XCTest
import Foundation
import SwiftData

/// Shared by every app's DataSafetyTests (project.yml adds TestSupport/ to each unit-test target). The snapshots
/// are the same ones .github/scripts/data_guard.py checks before every TestFlight archive: these tests check the
/// built app itself (its store, its schema, the texts in its bundle), the script checks the sources.
enum DataGuardSupport {
    /// The repo: this file is <repo>/TestSupport/DataGuardSupport.swift (simulator tests can read the Mac's files).
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static func snapshotData(_ name: String) throws -> Data {
        let url = root.appending(path: ".github/data-guard/\(name)")
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip(".github/data-guard/\(name) is not readable from this test run")
        }
        return data
    }

    // MARK: Stored fields

    /// Every field recorded in models.json still exists in the app's schema (new fields are fine).
    static func assertNoStoredFieldRemoved(_ schema: Schema, file: StaticString = #filePath, line: UInt = #line) throws {
        let snapshot = try JSONDecoder().decode([String: [String: String]].self, from: snapshotData("models.json"))
        XCTAssertFalse(schema.entities.isEmpty, file: file, line: line)
        for entity in schema.entities {
            guard let saved = snapshot[entity.name] else {
                XCTFail("\(entity.name) is missing from .github/data-guard/models.json", file: file, line: line)
                continue
            }
            let now = Set(entity.attributes.map(\.name))
            for name in saved.keys.sorted() where !now.contains(name) {
                XCTFail("\(entity.name).\(name) was renamed or removed: every saved value of it would be lost",
                        file: file, line: line)
            }
        }
    }

    // MARK: A store laid out like LocalStore.url

    /// `<tmp>/<name>-<uuid>/Library/Application Support/default.store`: the same shape as LocalStore.url, in a
    /// folder of its own, so a test never touches the app's real store.
    static func temporaryStoreURL(_ name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        let dir = base.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "default.store")
    }

    static func removeTemporaryStore(_ store: URL) {
        let base = store.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard base.path(percentEncoded: false).hasPrefix(FileManager.default.temporaryDirectory.path(percentEncoded: false))
        else { return }
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: Entitlements

    /// The .entitlements file this app is signed with (xcodegen writes it from project.yml) holds exactly the
    /// App Groups, iCloud containers and other entitlements in .github/data-guard/entitlements.json.
    static func assertEntitlements(target: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard let all = try JSONSerialization.jsonObject(with: snapshotData("entitlements.json")) as? [String: Any],
              let entry = all[target] as? [String: Any],
              let path = entry["path"] as? String,
              let allowed = entry["properties"] as? [String: Any] else {
            XCTFail("\(target) is missing from .github/data-guard/entitlements.json", file: file, line: line)
            return
        }
        guard let data = try? Data(contentsOf: root.appending(path: path)) else {
            throw XCTSkip("\(path) isn't generated in this checkout (xcodegen writes it)")
        }
        let signed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        XCTAssertTrue(NSDictionary(dictionary: signed).isEqual(to: allowed),
                      "\(path) differs from the allowlist: \(signed) vs \(allowed). App Groups and iCloud containers "
                      + "decide where data lives; see .github/scripts/data_guard.py", file: file, line: line)
    }

    static func appGroups(target: String) throws -> [String] {
        guard let all = try JSONSerialization.jsonObject(with: snapshotData("entitlements.json")) as? [String: Any],
              let entry = all[target] as? [String: Any],
              let props = entry["properties"] as? [String: Any] else { return [] }
        return props["com.apple.security.application-groups"] as? [String] ?? []
    }

    // MARK: Permission texts

    /// What the phone shows in English for every permission prompt and the app's name: never empty and never the
    /// raw key (ITMS-90738). Reads the built app: Info.plist, overridden by en.lproj/InfoPlist.strings (which an
    /// InfoPlist.xcstrings catalog compiles to).
    static func assertEnglishInfoPlist(_ bundle: Bundle = .main, file: StaticString = #filePath, line: UInt = #line) {
        let info = bundle.infoDictionary ?? [:]
        var english: [String: Any] = [:]
        if let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: "en"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
            english = dict
        }
        let asked = info.keys.filter { $0.hasSuffix("UsageDescription") } + ["CFBundleDisplayName"]
        let keys = Set(asked).union(english.keys).sorted()
        XCTAssertFalse(keys.isEmpty, file: file, line: line)
        for key in keys {
            let shown = (english[key] as? String) ?? (info[key] as? String) ?? ""
            XCTAssertFalse(shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "\(key) has no English text", file: file, line: line)
            XCTAssertNotEqual(shown, key, "\(key) shows its raw key name in English (ITMS-90738)", file: file, line: line)
        }
    }

    // MARK: Deep links

    static var urlSchemes: [String] {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    }

    static var querySchemes: [String] {
        Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? []
    }
}
