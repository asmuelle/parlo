import Foundation
import ParloKit
import Testing

/// Source-level enforcement of AGENTS.md product invariants:
/// - #1 zero egress: learning-loop modules contain no networking symbols.
/// - #5/#10 honest framing: no banned marketing terms anywhere in app or
///   package sources ("conversation fluency partner", never a know-it-all).
@Suite("Product invariant source scans")
struct ProductInvariantScanTests {
    /// Repo root, derived from this file's location:
    /// <root>/Packages/ParloKit/Tests/ProductInvariantScanTests.swift
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let learningLoopModules = [
        "Packages/ParloKit/Sources",
        "Packages/ConversationEngine/Sources",
        "Packages/SpeechKit/Sources",
        "Packages/PronunciationBeta/Sources",
        "Packages/Persistence/Sources",
    ]

    static let egressSymbols = [
        "URLSession",
        "NWConnection",
        "import Network",
        "socket(",
        "CFSocket",
    ]

    /// Lowercased banned copy fragments (invariants #5 and #10).
    static let bannedCopyTerms = [
        "tutor",
        "speak parity",
        "speak-quality",
        "elsa",
    ]

    private func swiftFiles(under relativePath: String) throws -> [URL] {
        let dir = Self.repoRoot.appendingPathComponent(relativePath)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }

    private func violations(in dirs: [String], matching terms: [String], caseInsensitive: Bool) throws -> [String] {
        var found: [String] = []
        var scanned = 0
        for dir in dirs {
            for file in try swiftFiles(under: dir) {
                let raw = try String(contentsOf: file, encoding: .utf8)
                let content = caseInsensitive ? raw.lowercased() : raw
                scanned += 1
                for term in terms where content.contains(caseInsensitive ? term.lowercased() : term) {
                    found.append("\(file.lastPathComponent): \(term)")
                }
            }
        }
        #expect(scanned > 0, "Scan found no Swift files — repo-root derivation is broken")
        return found
    }

    @Test
    func `invariant #1 — learning-loop modules contain no networking symbols`() throws {
        let hits = try violations(
            in: Self.learningLoopModules,
            matching: Self.egressSymbols,
            caseInsensitive: false,
        )
        #expect(hits.isEmpty, "Egress symbols found: \(hits)")
    }

    @Test
    func `invariants #5 and #10 — no banned framing terms in any sources`() throws {
        let allSourceDirs = Self.learningLoopModules + [
            "Packages/Paywall/Sources",
            "Packages/DesignSystem/Sources",
            "App",
        ]
        let hits = try violations(
            in: allSourceDirs,
            matching: Self.bannedCopyTerms,
            caseInsensitive: true,
        )
        #expect(hits.isEmpty, "Banned copy terms found: \(hits)")
    }

    @Test
    func `invariant #7 — launch languages are exactly es, fr, de`() {
        let codes = Set(ParloKit.LearningLanguage.allCases.map(\.rawValue))
        #expect(codes == ["es", "fr", "de"])
    }
}
