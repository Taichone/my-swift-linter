@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct IndentationRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "indentation"))
    }

    @Test("accepts four-space indentation in nested blocks")
    func nestedBlocks() {
        let source = """
        struct Example {
            func run() {
                if ready {
                    execute()
                }
            }
        }
        """
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("fixes two-space indentation using syntax depth")
    func twoSpaces() {
        let source = """
        struct Example {
          func run() {
            execute()
          }
        }
        """
        let (diagnostics, fixed) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 3)
        #expect(diagnostics.allSatisfy { $0.isFixable })
        #expect(fixed == """
        struct Example {
            func run() {
                execute()
            }
        }
        """)
        if let fixed { #expect(rule.lint(source: fixed).isEmpty) }
    }

    @Test("eight spaces at one level is a violation")
    func excessiveIndentation() {
        let (diagnostics, fixed) = rule.lintAndFix(source: "func run() {\n        execute()\n}")
        #expect(diagnostics.count == 1)
        #expect(fixed == "func run() {\n    execute()\n}")
    }

    @Test("fixes tabs and mixed indentation")
    func tabs() {
        let source = "struct Example {\n\tfunc run() {\n\t  execute()\n\t}\n}"
        let (diagnostics, fixed) = rule.lintAndFix(source: source)
        #expect(diagnostics.count == 3)
        #expect(fixed == "struct Example {\n    func run() {\n        execute()\n    }\n}")
    }

    @Test("checks multiline calls, parameters, arrays and closing delimiters")
    func lists() {
        let source = """
        func run(
          value: Int
          ) {
          consume(
            values: [
              value,
              2
              ]
            )
        }
        """
        let (diagnostics, fixed) = rule.lintAndFix(source: source)
        #expect(!diagnostics.isEmpty)
        #expect(fixed == """
        func run(
            value: Int
        ) {
            consume(
                values: [
                    value,
                    2
                ]
            )
        }
        """)
        if let fixed { #expect(rule.lint(source: fixed).isEmpty) }
    }

    @Test("an inline argument list does not add depth to its closure")
    func inlineClosure() {
        #expect(rule.lint(source: "consume(action: {\n    execute()\n})").isEmpty)
    }

    @Test("switch cases align with switch and case bodies add one level")
    func switchCases() {
        let source = """
        func run() {
            switch value {
            case 1:
                execute()
            default:
                break
            }
        }
        """
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("conditional compilation does not add indentation")
    func conditionalCompilation() {
        let source = """
        struct Example {
            #if DEBUG
            func run() {
                execute()
            }
            #else
            let value = 0
            #endif
        }
        """
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("fixes code without changing multiline literal contents or comments")
    func literalContents() {
        let source = "func run() {\n  // Comment\n  let text = \"\"\"\n   text\n  \ttext\n  \"\"\"\n  /* Comment */\n  consume(text)\n}"
        let (_, fixed) = rule.lintAndFix(source: source)
        #expect(fixed == "func run() {\n  // Comment\n    let text = \"\"\"\n   text\n  \ttext\n  \"\"\"\n  /* Comment */\n    consume(text)\n}")
        if let fixed { #expect(rule.lint(source: fixed).isEmpty) }
    }

    @Test("continuations use four-space units")
    func continuation() {
        let (diagnostics, fixed) = rule.lintAndFix(source: "let value = first +\n  second")
        #expect(diagnostics.count == 1)
        #expect(fixed == "let value = first +\n    second")
    }

    @Test("preserves CRLF line endings and reports the violated line")
    func lineEndings() {
        let (diagnostics, fixed) = rule.lintAndFix(source: "func run() {\r\n  execute()\r\n}\r\n")
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.line == 2)
        #expect(diagnostics.first?.severity == .error)
        #expect(fixed == "func run() {\r\n    execute()\r\n}\r\n")
    }

    @Test("severity can be configured")
    func severity() {
        let diagnostics = rule.lint(source: "func run() {\n  execute()\n}", argsYAML: "severity: warning")
        #expect(diagnostics.first?.severity == .warning)
    }

    @Test("indentation and multiline-call fixes agree on four-space depth")
    func combinedFixes() throws {
        let callRule = try #require(rules.find(id: "multiline-function-call"))
        let source = "func run() {\n  consume(first: 1,\n    second: 2)\n}"
        let diagnostics = rule.lint(source: source) + callRule.lint(source: source)
        let (fixed, _) = FixApplier.applyFixes(fixIts: diagnostics.flatMap(\.fixIts), to: source)
        #expect(fixed == """
        func run() {
            consume(
                first: 1,
                second: 2
            )
        }
        """)
        #expect(rule.lint(source: fixed).isEmpty)
        #expect(callRule.lint(source: fixed).isEmpty)
    }

    @Test("string literal opening quotes use the list's indentation")
    func literalOpening() {
        let (diagnostics, fixed) = rule.lintAndFix(source: "let values = [\n  \"text\"\n]")
        #expect(diagnostics.count == 1)
        #expect(fixed == "let values = [\n    \"text\"\n]")
    }
}
