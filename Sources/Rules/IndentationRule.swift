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
    private var nextLineOffset = 0

    init(file: SourceFileSyntax, context: LintContext, severity: Severity) {
        self.file = file
        self.context = context
        self.severity = severity
        lines = context.sourceLocationConverter.sourceLines
        indentation = FourSpaceIndentation(converter: context.sourceLocationConverter)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        guard token.presence == .present, token.tokenKind != .endOfFile else {
            return .visitChildren
        }
        let position = token.positionAfterSkippingLeadingTrivia
        guard position.utf8Offset >= nextLineOffset else { return .visitChildren }
        let location = context.sourceLocationConverter.location(for: position)
        guard lines.indices.contains(location.line - 1) else { return .visitChildren }
        let line = lines[location.line - 1]
        nextLineOffset = position.utf8Offset - location.column + 1 + line.utf8.count
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let actualWidth = indent.utf8.count
        // Inspect only the first code token of a line. Literal contents are not indentation.
        guard location.column == actualWidth + 1 else { return .visitChildren }
        let layout = indentation.context(of: token)
        guard layout.literalStart == nil || layout.literalStart == token.id else {
            return .visitChildren
        }

        let expectedWidth: Int
        if isLayoutAnchor(token) {
            expectedWidth = layout.level * 4
        } else {
            // Continuation expressions can choose their depth, but must use four-space units.
            let width = indent.reduce(0) { width, character in
                character == "\t" ? (width / 4 + 1) * 4 : width + 1
            }
            expectedWidth = ((width + 3) / 4) * 4
        }
        guard actualWidth != expectedWidth || indent.contains("\t") else { return .visitChildren }
        let expected = String(repeating: " ", count: expectedWidth)

        let end = position
        let start = AbsolutePosition(utf8Offset: end.utf8Offset - actualWidth)
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
final class FourSpaceIndentation {
    struct Context {
        var level = 0
        var literalStart: SyntaxIdentifier?
        var addsLevel = false
    }

    let converter: SourceLocationConverter
    private var contexts: [SyntaxIdentifier: Context] = [:]

    init(converter: SourceLocationConverter) {
        self.converter = converter
    }

    func level(of syntax: some SyntaxProtocol) -> Int {
        context(of: syntax).level
    }

    /// Caches ancestor depth and literal membership once per node for this file.
    func context(of syntax: some SyntaxProtocol) -> Context {
        var path: [Syntax] = []
        var ancestor = syntax.parent
        var result = Context()
        while let node = ancestor {
            if let cached = contexts[node.id] {
                result = cached
                break
            }
            path.append(node)
            ancestor = node.parent
        }
        for node in path.reversed() {
            result.addsLevel = computeAddsLevel(node)
            if result.addsLevel { result.level += 1 }
            if result.literalStart == nil {
                switch node.kind {
                case .stringLiteralExpr, .simpleStringLiteralExpr, .regexLiteralExpr:
                    result.literalStart = node.firstToken(viewMode: .sourceAccurate)?.id
                default:
                    break
                }
            }
            contexts[node.id] = result
        }
        return result
    }

    func addsLevel(_ node: Syntax) -> Bool {
        contexts[node.id]?.addsLevel ?? computeAddsLevel(node)
    }

    private func computeAddsLevel(_ node: Syntax) -> Bool {
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
