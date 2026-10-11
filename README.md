# my-swift-linter

[swift-ast-lint](https://github.com/Ryu0118/swift-ast-lint) 上に構築した、汎用的な Swift Lint ルール集。

複数プロジェクトで使い回せる「マイルール」を1つのリポジトリにまとめ、各プロジェクトからは
インストールしたバイナリを実行して利用する。ルールの有効/無効・severity・閾値は、
利用側プロジェクトの `.swift-ast-lint.yml` で制御する。

> 参考にした作者のマイルール集: [Ryu0118/my-swift-linter](https://github.com/Ryu0118/my-swift-linter)

## インストール

macOS の universal バイナリを GitHub Releases から取得して PATH に置く。

```bash
curl -fsSL https://raw.githubusercontent.com/Taichone/my-swift-linter/main/install.sh | bash
```

- 既定のインストール先は `~/.local/bin`。PATH に含まれていなければ警告が出るので、シェルの
  プロファイルに `export PATH="$HOME/.local/bin:$PATH"` を追加する。
- インストール先を変えるには `INSTALL_DIR=/usr/local/bin` のように指定する。
- 特定バージョンを入れるには `VERSION=0.1.0`、再インストールを強制するには `FORCE=1` を付ける。

```bash
# 例: /usr/local/bin に特定バージョンを入れる
curl -fsSL https://raw.githubusercontent.com/Taichone/my-swift-linter/main/install.sh \
  | INSTALL_DIR=/usr/local/bin VERSION=0.1.0 bash
```

## 使い方

リポジトリ直下に `.swift-ast-lint.yml` を置き、対象パスと各ルールの挙動を設定した上で、
Lint 対象を引数に渡して実行する。

```bash
my-swift-linter Sources          # Lint
my-swift-linter --fix Sources    # 自動修正を適用しながら Lint
```

### 設定（`.swift-ast-lint.yml`）

```yaml
included_paths:
  - "Sources/**/*.swift"
excluded_paths:
  - ".build/**"

rules:
  # ドキュメントコメント必須。退行を防ぐため error で運用する例。
  missing-docs:
    args:
      severity: error

  # 各ルールは ParameterizedRule。args で severity や閾値を上書きできる。
  no-magic-number:
    args:
      severity: warning
      allowed_values: ["0", "1"]
```

すべてのルールは実行バイナリに組み込み済みで、既定で有効。プロジェクトごとに不要なルールは
`.swift-ast-lint.yml` で severity を下げる／無効化するなどして調整する。既定値（閾値・対象など）は
各 `Sources/Rules/*Rule.swift` を参照。

## 収録ルール

| ルール ID | 内容 | 既定 severity |
|-----------|------|---------------|
| `one-type-per-file` | 1ファイル1型 + ファイル名一致（`#if`/`#else` の同名型・`Foo+Bar.swift` は許容） | warning |
| `no-dispatch-queue` | `DispatchQueue` 禁止（Swift Concurrency を使用） | error |
| `no-hardcoded-color` | `.white`/`.black`・`Color(red:)`/`Color(hex:)` 等の固定色禁止 | warning |
| `no-magic-number` | レイアウト/フォントの数値リテラル直書き禁止（`.infinity`・定数参照・`0`/`1` は除外） | warning |
| `deep-nesting` | 制御構文の深いネストを禁止（既定: 深さ3） | error |
| `single-large-type-per-file` | 1ファイルに大きな public/package 型を複数置かない | warning |
| `property-declaration-ordering` | プロパティを wrapper→アクセス修飾子順に並べ、`var body` を最初の computed に | warning |
| `function-access-modifier-grouping` | 関数をアクセス修飾子ごとにグループ化 | warning |
| `swiftui-view-property` | SwiftUI View のプロパティ規約 | warning |
| `branch-assignment-to-tuple` | 分岐代入のタプル化を提案 | warning |
| `no-top-level-function` | ファイルスコープ関数を禁止 | warning |
| `return-if-expression` | 多分岐 return を `return if` 式に | warning |
| `return-switch-expression` | 多分岐 return を `return switch` 式に | warning |
| `use-url-file-path` | 非推奨の `URL(fileURLWithPath:)` を置換 | warning |
| `multiline-function-call` | 複数行呼び出しの引数を4スペースで改行し、閉じ括弧を単独行にする | error |
| `indentation` | ブロック・引数・配列などを1段4スペースでインデントし、タブを禁止（自動修正対応） | error |
| `line-length` | インデント・コメント・文字列を含め、各行を最大100文字に制限 | error |
| `missing-docs` | 公開宣言にドキュメントコメント必須 | error |
| `meaningful-suite-description` | 冗長な `@Suite` description を検出 | warning |
| `test-function-naming` | `@Test` 関数の命名規約 | warning |

`indentation` は構文の入れ子に応じて4・8・12スペースのように検査する。継続式の行は
4スペース単位で検査し、コメント・空行・文字列や正規表現リテラルの内容は対象外とする。
`switch` の `case` は `switch` と同じ深さ、`#if` は追加のインデントなしとする。

`line-length` は Unicode の文字数（Swift の `Character`）で数え、改行コードは含めない。
100文字ちょうどは許可し、超えた行ごとに診断する。自動改行の Fix-It は提供しない。

各ルールは1ルール1ファイル（`Sources/Rules/*Rule.swift`）で実装し、`Sources/Rules/Rules.swift` で
`RuleSet` として合成している。すべて `ParameterizedRule` で、severity や閾値などを
`.swift-ast-lint.yml` の `args` から上書きできる。

## 開発

```bash
swift build            # ビルド
swift test             # ルールのユニットテスト
swift run my-swift-linter Sources   # ソースからそのまま実行
```

ルールの追加・調整は `Sources/Rules/*Rule.swift` を編集し、`Sources/Rules/Rules.swift` に合成、
`Tests/RulesTests/*` を追加して `swift test` で検証する。

## リリース

GitHub Actions の **Publish Release** ワークフロー（`workflow_dispatch`）にバージョン（例: `0.1.0`）を
渡すと、macOS universal バイナリをビルドしてアーカイブを作成し、そのバージョンの GitHub Release を
作成してアセットを添付する。`install.sh` はこの Release から最新のバイナリを取得する。

## ライセンス

[MIT](LICENSE)
