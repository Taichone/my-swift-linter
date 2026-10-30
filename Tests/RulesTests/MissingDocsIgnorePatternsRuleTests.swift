@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct MissingDocsIgnorePatternsRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "missing-docs"))
    }

    // MARK: - Full match: kinds + modifiers + names

    @Test("no error for static var/let matching all three fields")
    func ignorePatternFullMatch() async {
        let argsYAML = """
        ignore_patterns:
          - kinds: [var, let]
            modifiers: [static]
            names: [liveValue, previewValue, testValue]
        """
        let sources = [
            "public static var liveValue: Int = 0",
            "public static let liveValue: Int = 0",
            "public static var previewValue: Int = 0",
            "public static var testValue: Int = 0",
        ]
        for source in sources {
            let diagnostics = rule.lint(source: source, argsYAML: argsYAML)
            #expect(diagnostics.isEmpty, "Expected no violation for: \(source)")
        }
    }

    // MARK: - Modifier mismatch

    @Test("error fires when modifier does not match ignore_pattern")
    func ignorePatternModifierMismatch() async {
        // non-static var liveValue should still fire
        let source = "public var liveValue: Int = 0"
        let argsYAML = """
        ignore_patterns:
          - kinds: [var]
            modifiers: [static]
            names: [liveValue]
        """
        let diagnostics = rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }

    // MARK: - Name mismatch

    @Test("error fires when name does not match ignore_pattern")
    func ignorePatternNameMismatch() async {
        let source = "public static var someOther: Int = 0"
        let argsYAML = """
        ignore_patterns:
          - kinds: [var]
            modifiers: [static]
            names: [liveValue]
        """
        let diagnostics = rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }

    // MARK: - Kind mismatch

    @Test("error fires when kind does not match ignore_pattern")
    func ignorePatternKindMismatch() async {
        let source = "public static func liveValue() {}"
        let argsYAML = """
        ignore_patterns:
          - kinds: [var]
            modifiers: [static]
            names: [liveValue]
        """
        let diagnostics = rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }

    // MARK: - Wildcard fields

    @Test("ignore_pattern with only names matches any kind and modifier")
    func ignorePatternNamesOnly() async {
        let source = "public func liveValue() {}"
        let argsYAML = "ignore_patterns:\n  - names: [liveValue]\n"
        let diagnostics = rule.lint(source: source, argsYAML: argsYAML)
        #expect(diagnostics.isEmpty)
    }

    @Test("ignore_pattern with only kinds matches any name and modifier")
    func ignorePatternKindsOnly() async {
        let source = "public var anything: Int = 0"
        let argsYAML = "ignore_patterns:\n  - kinds: [var]\n"
        let diagnostics = rule.lint(source: source, argsYAML: argsYAML)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Empty list

    @Test("empty ignore_patterns does not suppress violations")
    func emptyIgnorePatterns() async {
        let source = "public func foo() {}"
        let argsYAML = "ignore_patterns: []\n"
        let diagnostics = rule.lint(source: source, argsYAML: argsYAML)
        #expect(!diagnostics.isEmpty)
    }

    @Test("name_pattern matches declaration names using regular expressions")
    func regularExpressionNamePattern() {
        let argsYAML = """
        ignore_patterns:
          - kinds: [struct]
            name_pattern: "Reducer$"
        """
        let matching = rule.lint(source: "public struct HomeReducer {}", argsYAML: argsYAML)
        let nonmatching = rule.lint(source: "public struct ReducerFactory {}", argsYAML: argsYAML)
        let wrongKind = rule.lint(source: "public func makeReducer() {}", argsYAML: argsYAML)
        #expect(matching.isEmpty)
        #expect(nonmatching.count == 1)
        #expect(wrongKind.count == 1)
    }

    @Test("exact names and name_pattern are alternatives subject to kind and modifier filters")
    func exactAndRegularExpressionNames() {
        let argsYAML = """
        ignore_patterns:
          - kinds: [var]
            modifiers: [static]
            names: [shared]
            name_pattern: "^preview"
        """
        let source = """
        public static var shared: Int = 0
        public static var previewValue: Int = 0
        public static var other: Int = 0
        public var previewInstance: Int = 0
        public static func previewFunction() {}
        """
        let diagnostics = rule.lint(source: source, argsYAML: argsYAML)
        #expect(diagnostics.count == 3)
    }

    @Test("invalid name_pattern never suppresses unrelated declarations")
    func invalidRegularExpressionFailsSafe() {
        let argsYAML = """
        ignore_patterns:
          - names: [shared]
            name_pattern: "["
        """
        let matchingName = rule.lint(source: "public var shared: Int = 0", argsYAML: argsYAML)
        let otherName = rule.lint(source: "public var other: Int = 0", argsYAML: argsYAML)
        #expect(matchingName.isEmpty)
        #expect(otherName.count == 1)

        let patternOnly = "ignore_patterns:\n  - name_pattern: '['\n"
        let invalidOnly = rule.lint(source: "public var shared: Int = 0", argsYAML: patternOnly)
        #expect(invalidOnly.count == 1)
    }
}
