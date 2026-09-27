import SwiftASTLint
import SwiftSyntax

/// The set of general-purpose Swift Lint rules provided by this package.
///
/// Each rule is implemented one-per-file in `*Rule.swift` and composed here. Every rule is
/// enabled by default; consuming projects tune severity/thresholds (or opt out) via their own
/// `.swift-ast-lint.yml`.
///
/// Some conventions (`one-type-per-file`, `no-dispatch-queue`, `no-hardcoded-color`,
/// `no-magic-number`) originated from a specific project but are broadly reusable, so they live
/// here alongside the other general-purpose rules.
public let rules = RuleSet {
    oneTypePerFileRule
    noDispatchQueueRule
    noHardcodedColorRule
    noMagicNumberRule

    deepNestingRule
    singleLargeTypePerFileRule
    propertyDeclarationOrderingRule
    functionAccessModifierGroupingRule
    swiftUIViewPropertyRule
    branchAssignmentToTupleRule
    noTopLevelFunctionRule
    returnIfExpressionRule
    returnSwitchExpressionRule
    useURLFilePathRule
    multilineFunctionCallRule
    meaningfulSuiteDescriptionRule
    testFunctionNamingRule
    missingDocsRule
}
