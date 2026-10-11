import SwiftSyntax

/// Access levels ordered from least to most visible.
enum DeclarationAccessLevel: String, Comparable {
    case `private`
    case `fileprivate`
    case `internal`
    case package
    case `public`
    case open

    /// Returns only an explicitly written access level; callers choose their implicit default.
    init?(modifiers: DeclModifierListSyntax) {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.private): self = .private
            case .keyword(.fileprivate): self = .fileprivate
            case .keyword(.internal): self = .internal
            case .keyword(.package): self = .package
            case .keyword(.public): self = .public
            case .keyword(.open): self = .open
            default: continue
            }
            return
        }
        return nil
    }

    private var rank: Int {
        switch self {
        case .private: 0
        case .fileprivate: 1
        case .internal: 2
        case .package: 3
        case .public: 4
        case .open: 5
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }
}
