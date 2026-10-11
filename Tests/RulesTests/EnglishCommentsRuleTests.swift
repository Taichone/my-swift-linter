@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct EnglishCommentsRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "english-comments"))
    }

    @Test("rejects Japanese in every comment style", arguments: [
        "// 日本語のコメント",
        "/* 日本語のコメント */",
        "/// 日本語のドキュメント",
        "/** 日本語のドキュメント */",
    ])
    func japaneseComments(comment: String) {
        let diagnostics = rule.lint(source: comment + "\nstruct Example {}")
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.ruleID == "english-comments")
        #expect(diagnostics.first?.severity == .error)
        #expect(diagnostics.first?.line == 1)
        #expect(diagnostics.first?.column == 1)
    }

    @Test("accepts English in every comment style", arguments: [
        "// An ordinary comment.",
        "/* An ordinary comment. */",
        "/// Describes the example type.",
        "/** Describes the example type. */",
    ])
    func englishComments(comment: String) {
        #expect(rule.lint(source: comment + "\nstruct Example {}").isEmpty)
    }

    @Test("rejects non-Latin writing systems", arguments: [
        "かな", "カナ", "漢字", "中文", "한국어", "Русский", "العربية", "Ελληνικά",
    ])
    func nonLatinScripts(text: String) {
        #expect(rule.lint(source: "// " + text).count == 1)
    }

    @Test("allows Unicode punctuation, symbols, emoji, and Latin letters")
    func allowedUnicode() {
        let source = """
        /// Returns the café’s name — preserving the user’s text.
        // Decomposed accent: cafe\u{301}. Temperature: 20°C. Check: ✅.
        /* Symbols: ∑ ∞ →; an emoji sequence: 👩🏽‍💻. */
        struct Example {}
        """
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("reports mixed English and Japanese once per comment")
    func mixedComments() {
        let source = """
        // Cache the result. 結果を保存する。
        /// Returns the result. 結果を返す。
        struct Example {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.map(\.line) == [1, 2])
        #expect(diagnostics.map(\.column) == [1, 1])
    }

    @Test("checks multiline and nested block comments")
    func blockComments() {
        let source = """
        /* An English opening.
           /* 日本語のネスト */
        */
        /** An English opening.
            日本語の説明
        */
        struct Example {}
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.map(\.line) == [1, 4])
        #expect(diagnostics.map(\.column) == [1, 1])
    }

    @Test("reports adjacent comments and trailing comments at their own positions")
    func adjacentAndTrailingComments() {
        let source = "let value = 0 /* 説明 */ /* 補足 */ // 追記"
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.map(\.line) == [1, 1, 1])
        #expect(diagnostics.map(\.column) == [15, 28, 41])
    }

    @Test("uses UTF-8 columns after Unicode code and English comments")
    func unicodePositions() {
        let source = "let text = \"日本語\" /* café */ // 説明"
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.line == 1)
        #expect(diagnostics.first?.column == 36)
    }

    @Test("checks comment-only files and comments after the final declaration", arguments: [
        "// 日本語", "/* 日本語 */", "/// 日本語", "/** 日本語 */",
    ])
    func endOfFileComments(comment: String) {
        let onlyComment = rule.lint(source: comment)
        #expect(onlyComment.count == 1)
        #expect(onlyComment.first?.line == 1)
        #expect(onlyComment.first?.column == 1)

        let afterDeclaration = rule.lint(source: "struct Example {}\n    " + comment)
        #expect(afterDeclaration.count == 1)
        #expect(afterDeclaration.first?.line == 2)
        #expect(afterDeclaration.first?.column == 5)
    }

    @Test("tracks physical lines with each line ending", arguments: ["\n", "\r\n", "\r"])
    func lineEndings(newline: String) {
        let source = "// English ✅" + newline + "struct Example {}" + newline + "  // 日本語"
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.line == 3)
        #expect(diagnostics.first?.column == 3)
    }

    @Test("ignores comment-like text in strings and regular expressions")
    func literals() {
        let source = #"""
        let text = "// 日本語"
        let 日本語 = "English"
        let raw = #"/** 日本語 */"#
        let multiline = """
        /// 日本語
        /* 日本語 */
        """
        let regex = #/日本語\/\/ /#
        """#
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("checks comments in conditional compilation branches")
    func conditionalCompilation() {
        let source = """
        #if DEBUG
        // 日本語
        #else
        /// 日本語
        #endif
        """
        let diagnostics = rule.lint(source: source)
        #expect(diagnostics.map(\.line) == [2, 4])
    }

    @Test("checks writing systems without guessing the language of Latin text")
    func latinLanguageLimitation() {
        #expect(rule.lint(source: "// Bonjour le monde.").isEmpty)
    }

    @Test("empty sources and comments without prose are valid", arguments: [
        "", "//", "/* */", "///", "/** */", "// MARK: - Helpers", "// 123 → 456",
    ])
    func emptyAndNonProseComments(source: String) {
        #expect(rule.lint(source: source).isEmpty)
    }

    @Test("severity can be configured without translating the source")
    func configurableSeverityAndNoFix() {
        let result = rule.lintAndFix(source: "// 日本語", argsYAML: "severity: warning")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.severity == .warning)
        #expect(result.diagnostics.first?.fixIts.isEmpty == true)
        #expect(result.fixedSource == nil)
    }
}
