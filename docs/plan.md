# Mac Studio (M3 Ultra / 512GB) 設計書

- 版: v0.1（設計中。決定事項は「決定」、未決は「未決」と明記する）
- 最終更新: 2026-09-06

## 1. 目的と原則

### 1.1 目的（優先順）

1. **自己主権とセキュリティの確立** — 自前フルノードで検証し、自前 Electrum サーバーに自分のウォレットを接続する。第三者サーバーへの残高・アドレス情報の漏洩をなくす。
2. **利便性の向上** — 自分のノードを使ったブロックエクスプローラー等で、プライバシーを保ったまま日常の確認作業を快適にする。
3. **ローカル LLM の実験** — 512GB の余剰メモリで巨大モデルを試す。ノード運用を圧迫しない範囲で行う。

### 1.2 設計原則

- **ノード優先**: メモリ・ディスク・CPU はノード系に先に予約し、LLM は残りを使う。
- **最小構成から積む**: フェーズ 1 は「Bitcoin Core + Fulcrum + Tor」のみ。動いてから足す。
- **CLI で完結**: 操作はターミナルと設定ファイルで行う。自作プログラミングは前提にしない（既製ツール＋設定＋シェル）。
- **再現可能**: 設定ファイルと手順はこのリポジトリに残し、再構築できる状態を保つ。
- **プルーニングしない**: 8TB あるので全ブロックを保持し、Fulcrum の完全インデックスを作る。

## 2. ハードウェア

| 項目 | 内容 |
|---|---|
| 機種 | Mac Studio (M3 Ultra) |
| CPU / GPU / NE | 32 コア / 80 コア / 32 コア |
| メモリ | 512GB ユニファイド |
| SSD | 8TB 内蔵 |
| 運用形態 | 24 時間稼働のサーバー（決定） |
| 操作端末 | MacBook Air（既存）、Ryzen 機（既存） |

## 3. 全体アーキテクチャ

```
[MacBook Air] --(Tailscale or LAN / Tor)--> [Mac Studio]
   Electrum ウォレット                          |
                                               +-- Bitcoin Core (bitcoind)  ... P2P は Tor 経由
                                               +-- Fulcrum (Electrum server) ... bitcoind の RPC を読む
                                               +-- Tor (hidden service)     ... Fulcrum を .onion で公開
                                               +-- [フェーズ2] mempool.space 自前ホスト
                                               +-- [フェーズ3] LLM ランタイム（LM Studio / MLX 等）
```

- ウォレットは MacBook 側の Electrum（既存）をそのまま使い、接続先だけ自前 Fulcrum に固定する（決定）。
- Ethereum ノードは立てない。MetaMask は従来通り外部 RPC を使う（決定）。
- Lightning / BTCPay は当面見送り。必要になったら別フェーズで検討（未決 → 保留）。

## 4. リソース予算

### 4.1 メモリ（512GB）

| 用途 | 予約量 | 備考 |
|---|---|---|
| macOS + 余裕 | 24GB | |
| Bitcoin Core | 最大 16GB | dbcache は上限 16GiB。初回同期後は 4GB 程度に下げる |
| Fulcrum | 最大 16GB | 初回同期時に多めに割り当て、完了後に下げる |
| Tor / mempool 等 | 8GB | |
| **ノード系 合計（予約）** | **64GB** | 定常時の実使用は 10〜20GB 程度の見込み |
| **LLM 用（GPU wired 上限）** | **最大 448GB** | `iogpu.wired_limit_mb` で上限を設定し、ノード系の 64GB を侵さないようにする |

初回同期（IBD）と Fulcrum の初期インデックス構築中（合計 1〜3 日）は LLM を動かさない。

### 4.2 ディスク（8TB）

| 用途 | 見込み | 備考 |
|---|---|---|
| macOS + アプリ | 100GB | |
| Bitcoin Core（blocks + chainstate + indexes） | 約 800GB〜 | 年 60〜80GB 程度増える |
| Fulcrum インデックス | 約 200GB | |
| mempool.space（DB 等） | 100GB 以下 | フェーズ 2 |
| LLM モデル置き場 | 2〜3TB | 400GB 級モデルを複数置ける |
| 予備 | 残り | ETH ノード等を後日検討する余地として 2TB は空けておく |

### 4.3 CPU / GPU

- ノード系: 初回同期時のみ CPU とディスク I/O が張り付く。以後はほぼアイドル。
- LLM: GPU（Metal）とメモリ帯域を使う。ノード系と使う資源が異なるため定常時の競合は小さい。

## 5. コンポーネント

### 5.1 Bitcoin Core（決定）

- 役割: フルノード。全ブロックを保持し検証する。
- 導入: Homebrew もしくは公式バイナリ（未決: どちらにするか）。
- 主要設定（案）:
  - `txindex=1`（Fulcrum には不要だが、mempool 等の利便性向上のため有効化を検討。未決）
  - `server=1`, RPC はローカルのみ許可
  - `proxy=127.0.0.1:9050`（Tor 経由で P2P）, `listen=1`, `bind=127.0.0.1`, onion サービスで受信
  - `dbcache=16384`（IBD 中）→ 同期後 `4096` に変更
  - `prune=0`
- 自動起動: launchd（LaunchDaemon）。

### 5.2 Fulcrum（決定）

- 役割: Electrum プロトコルのサーバー。自分のウォレットの接続先。
- 導入: 公式リリースの macOS バイナリ、またはソースからビルド（未決）。
- 主要設定（案）:
  - bitcoind の RPC を参照
  - TCP 50001 / SSL 50002 をローカルおよび Tor hidden service に公開
  - 初期同期時はメモリ割り当てを多めにし、完了後に下げる
- 自動起動: launchd。bitcoind が起動していることを前提に順序を制御する。

### 5.3 Tor（決定）

- 役割: (a) bitcoind の P2P を Tor 経由にして IP と取引の紐づけを防ぐ、(b) Fulcrum を hidden service として公開し、外出先からも自前サーバーに繋げる。
- 導入: Homebrew の `tor`。
- hidden service の秘密鍵はバックアップ対象（失うと .onion アドレスが変わる）。

### 5.4 リモートアクセス（未決）

候補:

- **Tailscale**（推奨候補）: MacBook からどこにいても Mac Studio に到達できる。Electrum の接続先を Tailscale の IP に固定できる。
- **LAN のみ + Tor**: 自宅では LAN、外では Fulcrum の .onion を使う。
- **SSH over Tor**: 管理用 SSH も hidden service 経由にする。

### 5.5 mempool.space 自前ホスト（フェーズ 2、暫定採用）

- 役割: 自分のノードをソースにしたブロックエクスプローラー。トランザクション確認や手数料推定を、外部サイトにアドレスを送らずに行える。
- 導入: Docker（OrbStack など）での compose 構成が一般的。macOS でのコンテナ運用方針は未決。

### 5.6 LLM ランタイム（フェーズ 3）

- 役割: まずは「試してみる」。MacBook Air との差を体感する。
- 導入候補: LM Studio（GUI、手軽）、Ollama（CLI）、MLX（Apple 純正の推論基盤、最速）。
- 最初に試すモデル（案）: 中型（70B〜235B 級）で速度を確認 → 最大級（DeepSeek V3/R1 級、4bit で約 400GB）を試す。
- MacBook から使う場合は OpenAI 互換 API を Tailscale 経由で提供する。

## 6. セキュリティ方針（案）

- Mac Studio は基本ヘッドレス運用。物理的にはディスプレイ無し、SSH で操作。
- FileVault の扱いは未決（有効にすると停電後の再起動時にパスワード入力が必要で、リモート復帰できない）。
- RPC・Fulcrum・LLM API はすべてローカル or Tailscale or Tor のみに公開。グローバル IP に直接ポートを開けない。
- ウォレットの秘密鍵は Mac Studio に置かない。署名は MacBook（既存 Electrum）で行う。
- 将来的にハードウェアウォレット導入を検討する余地を残す（保留）。

## 7. 運用方針（案）

- UPS を用意する（停電時のディスク破損防止。chainstate の破損は再同期で数日を失う）。
- バックアップ対象: 設定ファイル群、Tor hidden service 鍵、launchd 定義。チェーンデータはバックアップしない（再同期可能）。
- 監視: 最低限、bitcoind と Fulcrum の生存確認とブロック高の追随を確認する仕組みを用意する（方法は未決）。
- 更新: Bitcoin Core / Fulcrum / Tor のバージョンアップ手順を定める（未決）。

## 8. フェーズ計画

| フェーズ | 内容 | 完了条件 |
|---|---|---|
| 0. 準備 | macOS 初期設定、ヘッドレス化、SSH、リモートアクセス、ディスク配置 | MacBook から SSH で操作できる |
| 1. コア | Bitcoin Core + Tor で IBD 完了 → Fulcrum インデックス完了 → Electrum を自前 Fulcrum に接続 | Electrum が自前サーバーのみで残高・送金できる |
| 2. 利便性 | mempool.space 自前ホスト、監視、バックアップ、自動起動の整備 | 再起動後に全サービスが自動復帰する |
| 3. LLM | ランタイム導入、メモリ上限設定、モデル評価 | ノードを止めずに 400GB 級モデルが動く |
| 4. 拡張（保留） | Lightning、BTCPay、ETH ノード、ハードウェアウォレット | 必要になったら着手 |

## 9. 未決事項一覧

| # | 項目 | 選択肢 | 状態 |
|---|---|---|---|
| Q1 | リモートアクセス方式 | Tailscale / LAN+Tor / SSH over Tor | 未決 |
| Q2 | FileVault | 有効（安全だが停電復帰が手動） / 無効（自動復帰） | 未決 |
| Q3 | コンテナ方針 | すべてネイティブ / mempool 等のみ Docker | 未決 |
| Q4 | Bitcoin Core / Fulcrum の導入経路 | Homebrew / 公式バイナリ / ソースビルド | 未決 |
| Q5 | txindex | 有効 / 無効 | 未決 |
| Q6 | 監視方法 | シェル＋launchd / 既製ツール | 未決 |
| Q7 | UPS | 導入する / しない | 未決 |
| Q8 | LLM ランタイム | LM Studio / Ollama / MLX | 未決 |
