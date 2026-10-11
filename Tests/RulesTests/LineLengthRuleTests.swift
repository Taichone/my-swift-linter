@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct LineLengthRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "line-length"))
    }

    @Test("allows code lines up to 100 characters", arguments: [89, 90, 99, 100])
    func withinLimit(length: Int) {
        #expect(rule.lint(source: codeLine(length: length)).isEmpty)
    }

    @Test("reports one error per long line", arguments: [101, 120, 200])
    func exceedsLimit(length: Int) {
        let diagnostics = rule.lint(source: codeLine(length: length))
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .error)
        #expect(diagnostics.first?.column == 101)
        #expect(diagnostics.first?.message.contains("\(length) characters") == true)
    }

    @Test("counts indentation and trailing spaces")
    func whitespace() {
        let source = "    " + codeLine(length: 97) + "\n" + codeLine(length: 100) + " "
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 2)
        #expect(diagnostics.map(\.line) == [1, 2])
    }

    @Test("includes standalone comments and multiline literal contents")
    func commentsAndLiterals() {
        let source = "// " + String(repeating: "a", count: 98)
            + "\nlet text = \"\"\"\n" + String(repeating: "b", count: 101) + "\n\"\"\""
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 2)
        #expect(diagnostics.map(\.line) == [1, 3])
        #expect(diagnostics.allSatisfy { $0.column == 101 })
    }

    @Test("counts Unicode characters rather than bytes or scalars", arguments: [
        "あ", "👩‍💻", "e\u{301}",
    ])
    func unicode(character: String) {
        let valid = "// " + String(repeating: character, count: 97)
        #expect(rule.lint(source: valid).isEmpty)
        let diagnostics = rule.lint(source: valid + character)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.contains("101 characters") == true)
    }

    @Test("handles LF, CRLF and CR without counting line endings", arguments: ["\n", "\r\n", "\r"])
    func lineEndings(newline: String) {
        let source = "// あ" + newline + codeLine(length: 100) + newline
            + codeLine(length: 101) + newline
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.line == 3)
        #expect(diagnostics.first?.column == 101)
    }

    @Test("empty files and short blank lines are valid", arguments: ["", "\n\n", " \n\t\n"])
    func emptyLines(source: String) {
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("severity can be configured")
    func severity() {
        let diagnostics = rule.lint(source: codeLine(length: 101), argsYAML: "severity: warning")
        #expect(diagnostics.first?.severity == .warning)
    }

    @Test("does not automatically wrap source")
    func noAutomaticFix() {
        let (diagnostics, fixed) = rule.lintAndFix(source: codeLine(length: 101))
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.isFixable == false)
        #expect(fixed == nil)
    }

    private func codeLine(length: Int) -> String {
        let prefix = "let value = \""
        return prefix + String(repeating: "a", count: length - prefix.count - 1) + "\""
    }
}
