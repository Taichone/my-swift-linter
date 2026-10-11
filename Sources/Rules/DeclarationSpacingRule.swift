import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Requires one blank line before methods and documented properties.
struct DeclarationSpacingArgs: Codable {
    var severity: Severity = .error
}

let declarationSpacingRule = ParameterizedRule(
    id: "declaration-spacing",
    defaultArguments: DeclarationSpacingArgs(),
) { file, context, args in
    let visitor = DeclarationSpacingVisitor(file: file, context: context, severity: args.severity)
    visitor.walk(file)
}

private final class DeclarationSpacingVisitor: SyntaxVisitor {
    private let file: SourceFileSyntax
    private let context: LintContext
    private let severity: Severity
    private let lines: [String]
    private let indentation: FourSpaceIndentation

    init(file: SourceFileSyntax, context: LintContext, severity: Severity) {
        self.file = file
        self.context = context
        self.severity = severity
        lines = context.sourceLocationConverter.sourceLines
        indentation = FourSpaceIndentation(converter: context.sourceLocationConverter)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        check(node, introducer: node.funcKeyword, isMethod: true)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        check(node, introducer: node.initKeyword, isMethod: true)
        return .visitChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        check(node, introducer: node.deinitKeyword, isMethod: true)
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        check(node, introducer: node.subscriptKeyword, isMethod: true)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        check(node, introducer: node.bindingSpecifier, isMethod: false)
        return .visitChildren
    }

    private func check(
        _ node: some WithAttributesSyntax & WithModifiersSyntax,
        introducer: TokenSyntax,
        isMethod: Bool
    ) {
        guard node.parent?.kind == .memberBlockItem,
              let token = node.firstToken(viewMode: .sourceAccurate) else { return }

        var offset = token.position.utf8Offset
        var documentationStart: Int?
        var commentStart: Int?
        var newlines = 0
        // Inline block documentation can belong to the preceding token's trailing trivia.
        if let previous = token.previousToken(viewMode: .sourceAccurate) {
            var trailingOffset = previous.endPositionBeforeTrailingTrivia.utf8Offset
            for piece in previous.trailingTrivia {
                if case .docBlockComment = piece, documentationStart == nil {
                    documentationStart = trailingOffset
                }
                trailingOffset += piece.sourceLength.utf8Length
            }
        }
        for piece in token.leadingTrivia {
            switch piece {
            case .docLineComment, .docBlockComment:
                if documentationStart == nil || newlines > 1 { documentationStart = offset }
                if commentStart == nil || newlines > 1 { commentStart = offset }
                newlines = 0
            case .lineComment, .blockComment:
                if commentStart == nil || newlines > 1 { commentStart = offset }
                newlines = 0
            case .newlines(let count), .carriageReturns(let count),
                 .carriageReturnLineFeeds(let count):
                newlines += count
            default:
                break
            }
            offset += piece.sourceLength.utf8Length
        }
        guard isMethod || documentationStart != nil
            || containsDocumentation(introducer.leadingTrivia)
            || node.attributes.contains(where: { containsDocumentation($0.leadingTrivia) })
            || node.modifiers.contains(where: { containsDocumentation($0.leadingTrivia) })
        else { return }
        // Keep documentation above attributes. Attached ordinary comments also stay with methods.
        let anchor = documentationStart
            ?? (newlines < 2 ? commentStart : nil)
            ?? token.positionAfterSkippingLeadingTrivia.utf8Offset
        let location = context.sourceLocationConverter.location(
            for: AbsolutePosition(utf8Offset: anchor)
        )
        let lineIndex = location.line - 1
        guard lines.indices.contains(lineIndex) else { return }
        let line = lines[lineIndex]
        let prefix = line.utf8.prefix(location.column - 1)
        let startsLine = prefix.allSatisfy { $0 == 32 || $0 == 9 }
        let lineStart = anchor - prefix.count
        let start: Int
        let end: Int
        if startsLine {
            var firstBlankLine = lineIndex
            var blankBytes = 0
            while firstBlankLine > 0, isBlank(lines[firstBlankLine - 1]) {
                firstBlankLine -= 1
                blankBytes += lines[firstBlankLine].utf8.count
            }
            guard lineIndex - firstBlankLine != 1 else { return }
            start = lineStart - blankBytes
            end = lineStart
        } else {
            // Move inline members onto a separate line without changing preceding code or comments.
            start = anchor - prefix.reversed().prefix { $0 == 32 || $0 == 9 }.count
            end = anchor
        }

        let newline = lineEnding(lineIndex > 0 ? lines[lineIndex - 1] : line)
            ?? lineEnding(line) ?? "\n"
        let replacement = startsLine ? newline : newline + newline
            + String(repeating: " ", count: indentation.level(of: token) * 4)
        let marker = TokenSyntax(
            .identifier(""), leadingTrivia: .spaces(anchor), presence: .present
        )
        context.reportWithFix(
            on: marker,
            message: "Use exactly one blank line before methods and documented properties.",
            severity: severity,
            fixIts: [FixIt(
                message: SimpleFixItMessage("Use one blank line before the declaration"),
                changes: [.replaceText(
                    range: AbsolutePosition(utf8Offset: start)..<AbsolutePosition(utf8Offset: end),
                    with: replacement,
                    in: Syntax(file)
                )],
            )],
        )
    }

    private func isBlank(_ line: String) -> Bool {
        line.utf8.allSatisfy { $0 == 32 || $0 == 9 || $0 == 10 || $0 == 13 }
    }

    private func containsDocumentation(_ trivia: Trivia) -> Bool {
        trivia.contains { piece in
            switch piece {
            case .docLineComment, .docBlockComment: return true
            default: return false
            }
        }
    }

    private func lineEnding(_ line: String) -> String? {
        if line.hasSuffix("\r\n") { return "\r\n" }
        if line.hasSuffix("\n") { return "\n" }
        if line.hasSuffix("\r") { return "\r" }
        return nil
    }
}
