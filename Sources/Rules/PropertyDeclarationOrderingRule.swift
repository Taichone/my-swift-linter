import SwiftASTLint
import SwiftDiagnostics
import SwiftSyntax

/// Emits an error when property declarations within a type are not grouped
/// (1) by property wrapper and (2) by access modifier.
///
/// Sort priority:
///   1. Property wrapper name alphabetically (unwrapped properties last)
///   2. Access modifier within the same wrapper group (open → public → package → internal → fileprivate → private)
///
/// Relative declaration order within the same group is preserved (stable sort).
/// `var body` is always placed first among computed properties.
/// A Fix-It is provided to reorder automatically.
struct PropertyDeclarationOrderingArgs: Codable {
    var severity: Severity = .error
}

let propertyDeclarationOrderingRule = ParameterizedRule(
    id: "property-declaration-ordering",
    defaultArguments: PropertyDeclarationOrderingArgs(),
) { file, context, args in
    let visitor = PropertyDeclarationOrderingVisitor(context: context, severity: args.severity)
    visitor.walk(file)
}

// MARK: - Sort Key

/// Composite sort key for a property: (wrapper, accessLevel).
private struct PropertySortKey: Comparable {
    /// Wrapper name; empty string means no wrapper (sorted last via "~" sentinel).
    let wrapperName: String
    let accessLevel: DeclarationAccessLevel

    private var wrapperSortKey: String {
        wrapperName.isEmpty ? "~" : wrapperName
    }

    static func < (lhs: PropertySortKey, rhs: PropertySortKey) -> Bool {
        if lhs.wrapperSortKey != rhs.wrapperSortKey {
            return lhs.wrapperSortKey < rhs.wrapperSortKey
        }
        return lhs.accessLevel > rhs.accessLevel
    }
}

private struct StoredProperty {
    let index: Int
    let key: PropertySortKey
}

// MARK: - Visitor

private final class PropertyDeclarationOrderingVisitor: SyntaxVisitor {
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

    // MARK: - Check logic

    private func checkMemberBlock(_ memberBlock: MemberBlockSyntax, reportOn typeNode: Syntax) {
        let members = Array(memberBlock.members)
        let properties = classifyProperties(members)

        guard hasViolation(
            stored: properties.stored,
            computed: properties.computed,
            bodyPosition: properties.bodyPosition,
        ) else {
            return
        }

        let sorted = buildSortedMembersWithStoredFirst(
            members: members,
            stored: properties.stored,
            computedIndices: properties.computed,
            propertyIndices: properties.indices,
            bodyPosition: properties.bodyPosition,
        )
        let newBlock = memberBlock.with(\.members, MemberBlockItemListSyntax(sorted))

        context.reportWithFix(
            on: typeNode,
            message: "Properties should be grouped by wrapper, then access modifier."
                + " Stored before computed. var body must be first computed property.",
            severity: severity,
            fixIts: [
                FixIt(
                    message: SimpleFixItMessage("Reorder: stored → body → other computed"),
                    changes: [.replace(oldNode: Syntax(memberBlock), newNode: Syntax(newBlock))],
                ),
            ],
        )
    }

    /// Extracts property metadata once for both detection and the fix.
    private func classifyProperties(
        _ members: [MemberBlockItemSyntax],
    ) -> (stored: [StoredProperty], computed: [Int], indices: [Int], bodyPosition: Int?) {
        var stored: [StoredProperty] = []
        var computed: [Int] = []
        var indices: [Int] = []
        var bodyPosition: Int?
        for index in members.indices {
            guard let varDecl = members[index].decl.as(VariableDeclSyntax.self) else { continue }
            indices.append(index)
            if isComputedProperty(varDecl) {
                if bodyPosition == nil, isBodyProperty(varDecl) { bodyPosition = computed.count }
                computed.append(index)
            } else {
                let key = PropertySortKey(
                    wrapperName: wrapperName(of: varDecl),
                    accessLevel: DeclarationAccessLevel(modifiers: varDecl.modifiers) ?? .internal,
                )
                stored.append(StoredProperty(index: index, key: key))
            }
        }
        return (stored, computed, indices, bodyPosition)
    }

    /// Returns `true` when any ordering violation is detected:
    /// - stored properties not grouped by wrapper / access modifier
    /// - stored and computed properties interleaved
    /// - `var body` not first among computed properties
    private func hasViolation(
        stored: [StoredProperty],
        computed: [Int],
        bodyPosition: Int?,
    ) -> Bool {
        let hasEnough = stored.count >= 2
            || (!stored.isEmpty && !computed.isEmpty)
            || computed.count >= 2
        guard hasEnough else { return false }

        if !isGrouped(stored) { return true }
        if hasStoredComputedMixing(stored: stored, computed: computed) { return true }
        return bodyPosition.map { $0 != 0 } ?? false
    }

    private func hasStoredComputedMixing(stored: [StoredProperty], computed: [Int]) -> Bool {
        let firstStored = stored.first?.index ?? Int.max
        let lastStored = stored.last?.index ?? -1
        let lastComputed = computed.last ?? -1
        let storedAfterComputed = lastStored > lastComputed && lastComputed >= 0
        let computedBetweenStored = computed.contains { $0 > firstStored && $0 < lastStored }
        return storedAfterComputed || computedBetweenStored
    }

    /// Returns `true` when all equal-key elements are contiguous (no interleaving).
    /// Checks wrapper runs and access-level runs together without intermediate arrays.
    private func isGrouped(_ stored: [StoredProperty]) -> Bool {
        var seenWrappers: Set<String> = []
        var seenLevels: Set<DeclarationAccessLevel> = []
        var currentWrapper: String?
        var currentLevel: DeclarationAccessLevel?
        for property in stored {
            let key = property.key
            if key.wrapperName != currentWrapper {
                guard seenWrappers.insert(key.wrapperName).inserted else { return false }
                currentWrapper = key.wrapperName
                currentLevel = nil
                seenLevels.removeAll(keepingCapacity: true)
            }
            if key.accessLevel != currentLevel {
                guard seenLevels.insert(key.accessLevel).inserted else { return false }
                currentLevel = key.accessLevel
            }
        }
        return true
    }

    /// Builds the reordered member list: sorted stored properties first, then computed
    /// (with `var body` leading), non-property members stay in their original slots.
    private func buildSortedMembersWithStoredFirst(
        members: [MemberBlockItemSyntax],
        stored: [StoredProperty],
        computedIndices: [Int],
        propertyIndices: [Int],
        bodyPosition: Int?,
    ) -> [MemberBlockItemSyntax] {
        let sortedStored = stored
            .sorted { $0.key < $1.key }
            .map { members[$0.index] }

        var computedOrder = computedIndices
        if let bodyPosition, bodyPosition != 0 {
            let bodyIndex = computedOrder.remove(at: bodyPosition)
            computedOrder.insert(bodyIndex, at: 0)
        }

        let reordered = sortedStored + computedOrder.map { members[$0] }

        var result = members
        for (idx, originalIndex) in propertyIndices.enumerated() {
            result[originalIndex] = reordered[idx]
        }
        return result
    }

    /// Returns the first property wrapper name, or empty string if none.
    private func wrapperName(of varDecl: VariableDeclSyntax) -> String {
        for attribute in varDecl.attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               let identType = attr.attributeName.as(IdentifierTypeSyntax.self)
            {
                return identType.name.text
            }
        }
        return ""
    }

    /// Returns `true` when the variable has an accessor block (computed property).
    private func isComputedProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        varDecl.bindings.contains { $0.accessorBlock != nil }
    }

    private func isBodyProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        return varDecl.bindings.contains { $0.pattern.trimmedDescription == "body" }
    }
}
