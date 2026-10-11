import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Requires a multiline call's parentheses and arguments to use a vertical layout.
struct MultilineFunctionCallArgs: Codable {
    var severity: Severity = .error
}

let multilineFunctionCallRule = ParameterizedRule(
    id: "multiline-function-call",
    defaultArguments: MultilineFunctionCallArgs(),
) { file, context, args in
    let visitor = MultilineFunctionCallVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

private final class MultilineFunctionCallVisitor: SyntaxVisitor {
    private let context: LintContext
    private let severity: Severity
    private let indentation: FourSpaceIndentation
    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
        indentation = FourSpaceIndentation(converter: context.sourceLocationConverter)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let leftParen = node.leftParen, let rightParen = node.rightParen else {
            return .visitChildren
        }

        let location = context.sourceLocationConverter
        func line(_ token: TokenSyntax) -> Int {
            location.location(for: token.positionAfterSkippingLeadingTrivia).line
        }
        func column(_ token: TokenSyntax) -> Int {
            location.location(for: token.positionAfterSkippingLeadingTrivia).column
        }

        // A newline inside an argument expression also makes its enclosing call multiline.
        guard line(leftParen) != line(rightParen) else { return .visitChildren }

        let level = indentation.level(of: node)
        let baseIndent = String(repeating: " ", count: level * 4)
        let argumentIndent = baseIndent + "    "
        let arguments = Array(node.arguments)
        var boundaries: [(TokenSyntax, TokenSyntax, String)] = []
        if arguments.isEmpty {
            boundaries.append((leftParen, rightParen, baseIndent))
        } else if let first = arguments.first?.firstToken(viewMode: .sourceAccurate) {
            boundaries.append((leftParen, first, argumentIndent))
        }
        for index in arguments.indices.dropFirst() {
            guard let comma = arguments[index - 1].trailingComma,
                  let first = arguments[index].firstToken(viewMode: .sourceAccurate) else {
                continue
            }
            boundaries.append((comma, first, argumentIndent))
        }
        if let last = arguments.last?.lastToken(viewMode: .sourceAccurate) {
            boundaries.append((last, rightParen, baseIndent))
        }

        let expectedColumns = arguments.allSatisfy { argument in
            guard let first = argument.firstToken(viewMode: .sourceAccurate) else { return true }
            return column(first) == argumentIndent.utf8.count + 1
        }
        let boundariesValid = boundaries.allSatisfy { before, after, _ in
            line(after) > line(before) && startsWithNewline(between: before, and: after)
        }
        let closingAligned = column(rightParen) == baseIndent.utf8.count + 1
        guard !expectedColumns || !boundariesValid || !closingAligned else {
            return .visitChildren
        }

        let message = "Multiline calls must put `(`, each equally indented argument, and `)` on separate lines."
        if let fix = makeFix(boundaries: boundaries) {
            context.reportWithFix(on: node, message: message, severity: severity, fixIts: [fix])
        } else {
            context.report(on: node, message: message, severity: severity)
        }
        return .visitChildren
    }

    private func startsWithNewline(between before: TokenSyntax, and after: TokenSyntax) -> Bool {
        let gap = before.trailingTrivia.description + after.leadingTrivia.description
        return gap.hasPrefix("\n") || gap.hasPrefix("\r\n")
    }

    /// Replaces only whitespace trivia at token boundaries. Comments remain untouched and
    /// prevent an automatic fix, because moving them could change which argument they document.
    private func makeFix(boundaries: [(TokenSyntax, TokenSyntax, String)]) -> FixIt? {
        var replacements: [Int: (old: TokenSyntax, new: TokenSyntax)] = [:]
        for (before, after, indent) in boundaries {
            guard isWhitespace(before.trailingTrivia), isWhitespace(after.leadingTrivia) else {
                return nil
            }
            let beforeKey = before.position.utf8Offset
            let afterKey = after.position.utf8Offset
            let currentBefore = replacements[beforeKey]?.new ?? before
            let currentAfter = replacements[afterKey]?.new ?? after
            replacements[beforeKey] = (before, currentBefore.with(\.trailingTrivia, []))
            let newTrivia = Trivia(pieces: [.newlines(1), .spaces(indent.utf8.count)])
            replacements[afterKey] = (after, currentAfter.with(\.leadingTrivia, newTrivia))
        }
        let changes = replacements.values.map { replacement in
            FixIt.Change.replace(oldNode: Syntax(replacement.old), newNode: Syntax(replacement.new))
        }
        return FixIt(message: SimpleFixItMessage("Format multiline call"), changes: changes)
    }

    private func isWhitespace(_ trivia: Trivia) -> Bool {
        trivia.allSatisfy { piece in
            switch piece {
            case .spaces, .tabs, .newlines, .carriageReturns, .carriageReturnLineFeeds, .verticalTabs, .formfeeds:
                return true
            default:
                return false
            }
        }
    }
}
