import SwiftSyntax

/// A type directly in a source file or one of its conditional compilation branches.
struct TopLevelTypeDeclaration {
    let nameToken: TokenSyntax
    let modifiers: DeclModifierListSyntax
    let node: Syntax

    var name: String { nameToken.text }

    static func collect(in statements: CodeBlockItemListSyntax) -> [Self] {
        var declarations: [Self] = []
        collect(in: statements, into: &declarations)
        return declarations
    }

    private static func collect(in statements: CodeBlockItemListSyntax, into declarations: inout [Self]) {
        for statement in statements {
            let node = Syntax(statement.item)
            switch node.kind {
            case .structDecl:
                let type = node.cast(StructDeclSyntax.self)
                declarations.append(Self(nameToken: type.name, modifiers: type.modifiers, node: node))
            case .classDecl:
                let type = node.cast(ClassDeclSyntax.self)
                declarations.append(Self(nameToken: type.name, modifiers: type.modifiers, node: node))
            case .enumDecl:
                let type = node.cast(EnumDeclSyntax.self)
                declarations.append(Self(nameToken: type.name, modifiers: type.modifiers, node: node))
            case .actorDecl:
                let type = node.cast(ActorDeclSyntax.self)
                declarations.append(Self(nameToken: type.name, modifiers: type.modifiers, node: node))
            case .ifConfigDecl:
                for clause in node.cast(IfConfigDeclSyntax.self).clauses {
                    if let branch = clause.elements?.as(CodeBlockItemListSyntax.self) {
                        collect(in: branch, into: &declarations)
                    }
                }
            default:
                break
            }
        }
    }
}
