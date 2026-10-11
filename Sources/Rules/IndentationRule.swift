import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Requires four spaces per indentation level and forbids indentation tabs.
struct IndentationArgs: Codable {
    var severity: Severity = .error
}

let indentationRule = ParameterizedRule(
    id: "indentation",
    defaultArguments: IndentationArgs(),
) { file, context, args in
    let visitor = IndentationVisitor(file: file, context: context, severity: args.severity)
    visitor.walk(file)
}

private final class IndentationVisitor: SyntaxVisitor {
    private let file: SourceFileSyntax
    private let context: LintContext
    private let severity: Severity
    private let lines: [String]
    private let indentation: FourSpaceIndentation

    init(file: SourceFileSyntax, context: LintContext, severity: Severity) {
        self.file = file
        self.context = context
        self.severity = severity
        lines = file.description.components(separatedBy: "\n")
        indentation = FourSpaceIndentation(converter: context.sourceLocationConverter)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        guard token.presence == .present, token.tokenKind != .endOfFile else {
            return .visitChildren
        }
        let location = context.sourceLocationConverter.location(for: token.positionAfterSkippingLeadingTrivia)
        guard lines.indices.contains(location.line - 1) else { return .visitChildren }
        let indent = String(lines[location.line - 1].prefix { $0 == " " || $0 == "\t" })
        // Inspect only the first code token of a line. Literal contents are not indentation.
        guard location.column == indent.utf8.count + 1, !isInsideLiteral(token) else {
            return .visitChildren
        }

        let expectedWidth: Int
        if isLayoutAnchor(token) {
            expectedWidth = indentation.level(of: token) * 4
        } else {
            // Continuation expressions can choose their depth, but must use four-space units.
            let width = indent.reduce(0) { width, character in
                character == "\t" ? (width / 4 + 1) * 4 : width + 1
            }
            expectedWidth = ((width + 3) / 4) * 4
        }
        let expected = String(repeating: " ", count: expectedWidth)
        guard indent != expected else { return .visitChildren }

        let end = token.positionAfterSkippingLeadingTrivia
        let start = AbsolutePosition(utf8Offset: end.utf8Offset - indent.utf8.count)
        context.reportWithFix(
            on: token,
            message: "Use four spaces per indentation level (expected \(expectedWidth) spaces); tabs are not allowed.",
            severity: severity,
            fixIts: [
                FixIt(
                    message: SimpleFixItMessage("Use \(expectedWidth) spaces for indentation"),
                    changes: [.replaceText(range: start..<end, with: expected, in: Syntax(file))],
                ),
            ],
        )
        return .visitChildren
    }

    private func isInsideLiteral(_ token: TokenSyntax) -> Bool {
        var ancestor = token.parent
        while let node = ancestor {
            switch node.kind {
            case .stringLiteralExpr, .simpleStringLiteralExpr, .regexLiteralExpr:
                if node.firstToken(viewMode: .sourceAccurate)?.id != token.id { return true }
                ancestor = node.parent
            default:
                ancestor = node.parent
            }
        }
        return false
    }

    private func isLayoutAnchor(_ token: TokenSyntax) -> Bool {
        switch token.tokenKind {
        case .rightBrace, .rightParen, .rightSquare, .rightAngle:
            return true
        default:
            break
        }
        var ancestor = token.parent
        while let node = ancestor {
            guard node.firstToken(viewMode: .sourceAccurate)?.id == token.id else { break }
            switch node.parent?.kind {
            case .codeBlockItemList, .memberBlockItemList, .accessorDeclList,
                 .switchCaseList, .ifConfigClauseList:
                return true
            default:
                if let parent = node.parent, indentation.addsLevel(parent) { return true }
                ancestor = node.parent
            }
        }
        return false
    }

}

/// Shared by indentation and multiline-call fixes so both rules agree on syntax depth.
struct FourSpaceIndentation {
    let converter: SourceLocationConverter

    func level(of syntax: some SyntaxProtocol) -> Int {
        var level = 0
        var ancestor = syntax.parent
        while let node = ancestor {
            if addsLevel(node) { level += 1 }
            ancestor = node.parent
        }
        return level
    }

    func addsLevel(_ node: Syntax) -> Bool {
        switch node.kind {
        case .memberBlockItemList:
            return node.parent?.kind == .memberBlock
        case .codeBlockItemList:
            switch node.parent?.kind {
            case .codeBlock, .closureExpr, .switchCase: return true
            default: return false
            }
        case .accessorDeclList:
            return true
        case .arrayElementList, .dictionaryElementList, .labeledExprList,
             .functionParameterList, .closureParameterList, .enumCaseParameterList,
             .genericParameterList, .genericArgumentList, .tupleTypeElementList,
             .tuplePatternElementList:
            // Inline lists do not add a level to a closure or nested call's body.
            guard let first = node.firstToken(viewMode: .sourceAccurate),
                  let opening = first.previousToken(viewMode: .sourceAccurate) else { return false }
            return converter.location(for: first.positionAfterSkippingLeadingTrivia).line
                > converter.location(for: opening.positionAfterSkippingLeadingTrivia).line
        default:
            return false
        }
    }
}
