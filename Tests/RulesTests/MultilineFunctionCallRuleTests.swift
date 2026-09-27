@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct MultilineFunctionCallRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "multiline-function-call"))
    }

    @Test("accepts vertically formatted call")
    func verticalCall() {
        let source = """
        let summary = EventSummary(
            event: event,
            displayedTitle: title,
            settings: settings,
            now: now
        )
        """
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("rejects hanging indentation and fixes it")
    func hangingIndent() {
        let source = """
        let summary = EventSummary(event: event,
                                   displayedTitle: title,
                                   settings: settings)
        """
        let (diagnostics, fixed) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].isFixable)
        #expect(fixed == """
        let summary = EventSummary(
            event: event,
            displayedTitle: title,
            settings: settings
        )
        """)
        if let fixed { #expect(rule.lint(source: fixed).isEmpty) }
    }

    @Test("rejects arguments sharing a line")
    func sharedLine() {
        let source = """
        foo(
            first: 1, second: 2
        )
        """
        let (diagnostics, fixed) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(fixed == """
        foo(
            first: 1,
            second: 2
        )
        """)
    }

    @Test("rejects misaligned arguments and closing parenthesis")
    func misaligned() {
        let source = """
        func example() {
            foo(
              first: 1,
                second: 2
              )
        }
        """
        let (diagnostics, fixed) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(fixed == """
        func example() {
            foo(
                first: 1,
                second: 2
            )
        }
        """)
    }

    @Test("single-line calls stay valid")
    func singleLine() {
        #expect(rule.lint(source: "let x = foo(first: 1, second: 2)").isEmpty)
    }

    @Test("nested multiline calls are visited independently")
    func nested() {
        let source = """
        outer(
            value: inner(first: 1,
                         second: 2)
        )
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
    }

    @Test("comments receive a diagnostic without an unsafe fix")
    func comment() {
        let source = """
        foo(first: 1, // explanation
            second: 2)
        """
        let (diagnostics, fixed) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(!diagnostics[0].isFixable)
        #expect(fixed == nil)
    }

    @Test("single multiline argument uses vertical parentheses")
    func multilineArgument() {
        let source = """
        foo(value: a +
            b)
        """
        #expect(rule.lint(source: source).count == 1)
    }

    @Test("fix preserves tab indentation")
    func tabIndentation() {
        let source = "\tfoo(first: 1,\n\t    second: 2)"
        let (_, fixed) = rule.lintAndFix(source: source)
        #expect(fixed == "\tfoo(\n\t\tfirst: 1,\n\t\tsecond: 2\n\t)")
        if let fixed { #expect(rule.lint(source: fixed).isEmpty) }
    }

    @Test("extra spaces after an opening parenthesis are rejected")
    func spaceBeforeNewline() {
        let source = "foo(  \n    first: 1\n)"
        let (diagnostics, fixed) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(fixed == "foo(\n    first: 1\n)")
    }

    @Test("multiline empty call keeps its closing parenthesis on its own line")
    func emptyCall() {
        let source = "foo(\n    )"
        let (diagnostics, fixed) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 1)
        #expect(fixed == "foo(\n)")
    }
}
