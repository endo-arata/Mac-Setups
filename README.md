# Mac-Setups

Mac Studio (M3 Ultra, 512GB) を 24 時間稼働の Bitcoin フルノード（Bitcoin Core + Fulcrum + Tor）兼ローカル LLM 実験機として構築するための設計と設定。

| パス | 内容 |
|---|---|
| `docs/plan.md` | 全体設計書。目的、リソース予算、決定事項と未決事項 |
| `docs/phase0-macos.md` | フェーズ 0。macOS の初期設定・ヘッドレス化・SSH・サービスユーザー作成の手順 |
| `docs/node-design.md` | ノード周りの詳細設計（プロセス構成、通信経路、各設定の根拠） |
| `docs/tails-electrum.md` | Tails 上の Electrum を自前 Fulcrum に固定する手順 |
| `configs/` | 設定ファイル案。`<...>` は環境に合わせて置き換える |

秘密情報（Tor hidden service の鍵、RPC クッキー、Telegram トークン）は `.gitignore` で除外している。コミット前に `git status` で確認すること。
