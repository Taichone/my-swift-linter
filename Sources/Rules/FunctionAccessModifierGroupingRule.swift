import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Emits an error when function declarations within a type are not grouped by access modifier.
///
/// Expected order: open → public → package → internal (implicit) → fileprivate → private
///
/// Relative declaration order within the same access level is preserved (stable sort).
/// A Fix-It is provided to reorder automatically.
/// init / deinit / subscript are excluded; only regular `func` declarations are checked.
struct FunctionAccessModifierGroupingArgs: Codable {
    var severity: Severity = .error
}

let functionAccessModifierGroupingRule = ParameterizedRule(
    id: "function-access-modifier-grouping",
    defaultArguments: FunctionAccessModifierGroupingArgs(),
) { file, context, args in
    let visitor = FunctionAccessGroupingVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

private struct FunctionInfo {
    let index: Int
    let member: MemberBlockItemSyntax
    let level: DeclarationAccessLevel
}

// MARK: - Visitor

private final class FunctionAccessGroupingVisitor: SyntaxVisitor {
    let context: LintContext
    let severity: Severity

    init(context: LintContext, severity: Severity) {
        self.context = context
        self.severity = severity
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        checkMemberBlock(node.memberBlock, reportOn: Syntax(node))
        return .visitChildren
    }

    // MARK: - Check

    private func checkMemberBlock(
        _ memberBlock: MemberBlockSyntax,
        reportOn typeNode: Syntax,
    ) {
        let members = Array(memberBlock.members)
        let functions = members.enumerated().compactMap { index, member -> FunctionInfo? in
            guard let function = member.decl.as(FunctionDeclSyntax.self) else { return nil }
            return FunctionInfo(
                index: index,
                member: member,
                level: DeclarationAccessLevel(modifiers: function.modifiers) ?? .internal,
            )
        }
        guard functions.count >= 2 else { return }

        guard !isGrouped(functions) else { return }

        let sorted = buildSorted(members: members, functions: functions)
        let newBlock = memberBlock.with(\.members, MemberBlockItemListSyntax(sorted))

        context.reportWithFix(
            on: typeNode,
            message: "Functions should be grouped by access modifier"
                + " (open → public → package → internal → fileprivate → private).",
            severity: severity,
            fixIts: [
                FixIt(
                    message: SimpleFixItMessage("Group functions by access modifier"),
                    changes: [.replace(oldNode: Syntax(memberBlock), newNode: Syntax(newBlock))],
                ),
            ],
        )
    }

    // MARK: - Grouping check

    private func isGrouped(_ functions: [FunctionInfo]) -> Bool {
        var seen: Set<DeclarationAccessLevel> = []
        var current: DeclarationAccessLevel?
        for function in functions where function.level != current {
            guard seen.insert(function.level).inserted else { return false }
            current = function.level
        }
        return true
    }

    // MARK: - Sort

    /// Stable-sorts function declarations by access level, preserving non-function member positions.
    private func buildSorted(
        members: [MemberBlockItemSyntax],
        functions: [FunctionInfo],
    ) -> [MemberBlockItemSyntax] {
        let sortedFuncs = functions
            .sorted { $0.level > $1.level }
            .map(\.member)

        var result = members
        for (idx, function) in functions.enumerated() {
            result[function.index] = sortedFuncs[idx]
        }
        return result
    }
}
