@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct TestFunctionNamingRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "test-function-naming"))
    }

    // MARK: - Violations

    @Test("error when @Test function name is backtick-quoted")
    func backtickQuotedTestFunction() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func `claudeHookOutput blocks when outOfSync`() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("error when @Test function has description but name is still backtick-quoted")
    func backtickQuotedWithDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("some description")
            func `claudeHookOutput blocks when outOfSync`() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("error when @Test function at file scope has backtick-quoted name")
    func backtickQuotedTopLevel() async {
        let source = """
        import Testing
        @Test
        func `something happens here`() {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("multiple backtick-quoted @Test functions each produce an error")
    func multipleViolations() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func `first case`() {}
            @Test
            func `second case`() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    // MARK: - No violations (must NOT fire)

    @Test("no error when @Test has lowerCamelCase name and description argument")
    func lowerCamelCaseWithDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test("claudeHookOutput blocks when outOfSync")
            func claudeHookOutputBlocksWhenOutOfSync() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @Test has lowerCamelCase name without description")
    func lowerCamelCaseNoDescription() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func claudeHookOutputBlocksWhenOutOfSync() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when backtick-quoted function has no @Test attribute")
    func backtickQuotedNonTestFunction() async {
        let source = """
        struct MyTests {
            func `some helper`() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when regular function uses backtick for Swift keyword escaping")
    func backtickKeywordEscaping() async {
        let source = """
        import Testing
        struct MyTests {
            @Test
            func `default`() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error on non-test function with lowerCamelCase name")
    func nonTestFunction() async {
        let source = """
        struct MyType {
            func computeValue() -> Int { 42 }
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Edge cases

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("@Test with only trait arguments and backtick name is still a violation")
    func backtickWithTraitOnly() async {
        let source = """
        import Testing
        struct MyTests {
            @Test(.serialized)
            func `does something important`() {}
        }
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("underscore and test-prefix names are flagged by default")
    func underscoreAndPrefixNames() {
        let source = """
        @Test func decode_returnsValue() {}
        @Test func testDecoding() {}
        @Test func TESTUppercase() {}
        @Test func testing() {}
        @Test func validateTestInput() {}
        func test_helper() {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 4)
        #expect(diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test("each naming pattern can be disabled independently")
    func independentChecks() {
        let source = """
        @Test func `spaced name`() {}
        @Test func name_with_underscores() {}
        @Test func testPrefix() {}
        """
        let cases = [
            ("check_spaces: false", 2),
            ("check_underscores: false", 2),
            ("check_test_prefix: false", 2),
            ("check_spaces: false\ncheck_underscores: false\ncheck_test_prefix: false", 0),
        ]
        for (args, expected) in cases {
            let diagnostics = rule.lint(source: source, argsYAML: args)
            #expect(diagnostics.count == expected)
        }
    }

    @Test("overlapping naming patterns produce one diagnostic and honor severity")
    func overlappingPatterns() {
        let source = "@Test func test_case() {}"
        let diagnostics = rule.lint(source: source, argsYAML: "severity: warning")
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .warning)

        let prefixOnly = rule.lint(
            source: source,
            argsYAML: "check_underscores: false\ncheck_test_prefix: true"
        )
        #expect(prefixOnly.count == 1)
        let neither = rule.lint(
            source: source,
            argsYAML: "check_underscores: false\ncheck_test_prefix: false"
        )
        #expect(neither.isEmpty)
    }
}
