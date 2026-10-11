import SwiftASTLint
import SwiftSyntax

/// Rejects non-Latin letters in ordinary and documentation comments.
struct EnglishCommentsArgs: Codable {
    var severity: Severity = .error
}

let englishCommentsRule = ParameterizedRule(
    id: "english-comments",
    defaultArguments: EnglishCommentsArgs(),
) { file, context, args in
    let visitor = EnglishCommentsVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

private final class EnglishCommentsVisitor: SyntaxVisitor {
    private let context: LintContext
    private let severity: Severity
    // Unicode script matching allows accented Latin letters, punctuation, and emoji.
    // Short comments are checked by writing system; their language is not inferred.
    private let nonLatinLetter = #/[\p{L}&&[^\p{Latin}]]/#

    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        check(token.leadingTrivia, startingAt: token.position.utf8Offset)
        check(token.trailingTrivia, startingAt: token.endPositionBeforeTrailingTrivia.utf8Offset)
        return .visitChildren
    }

    private func check(_ trivia: Trivia, startingAt start: Int) {
        var offset = start
        for piece in trivia {
            switch piece {
            case .lineComment(let text), .blockComment(let text),
                 .docLineComment(let text), .docBlockComment(let text):
                if text.contains(nonLatinLetter) {
                    // Anchor the diagnostic to this comment, including comments on the EOF token.
                    let marker = TokenSyntax(
                        .identifier(""), leadingTrivia: .spaces(offset), presence: .present
                    )
                    context.report(
                        on: marker,
                        message: "Write all comments in English; non-Latin letters are not allowed.",
                        severity: severity,
                    )
                }
            default:
                break
            }
            offset += piece.sourceLength.utf8Length
        }
    }
}
