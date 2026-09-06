# Mac Studio (M3 Ultra / 512GB) 設計書

- 版: v0.6（設計中。決定事項は「決定」、未決は「未決」と明記する）
- 関連文書: `docs/node-design.md`（ノード周りの詳細設計）、`configs/`（設定ファイル案）、`docs/tails-electrum.md`（Tails 側の手順）
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
- **第三者サービスに依存しない**: リモートアクセスは LAN と Tor のみ。Tailscale 等の調整サーバーを介するものは使わない（決定）。
- **すべてネイティブ**: Homebrew・公式バイナリ・launchd で構成し、Docker は使わない（決定）。macOS 上のコンテナは仮想マシン経由で I/O が遅く、管理系統も 2 つに割れるため。

## 2. ハードウェア

| 項目 | 内容 |
|---|---|
| 機種 | Mac Studio (M3 Ultra) |
| CPU / GPU / NE | 32 コア / 80 コア / 32 コア |
| メモリ | 512GB ユニファイド |
| SSD | 8TB 内蔵 |
| 運用形態 | 24 時間稼働のサーバー（決定） |
| 管理端末 | MacBook Air（既存）。SSH で Mac Studio を操作する。ウォレットは置かない |
| ウォレット端末 | Ryzen 機で起動する Tails（既存）。Tails は x86_64 専用のため Apple Silicon では動かない。Electrum はここでのみ使う |
| 電源 | UPS を新規導入する（決定）。USB 接続で macOS に認識させ、バッテリー残量低下時に自動で安全停止させる |
| ネットワーク | 有線 LAN（内蔵 10GbE ポート）（決定）。ルーターの DHCP 予約で固定プライベート IP を与える。Wi‑Fi は無効化する |
| 設置 | ヘッドレス。ただし FileVault のため、再起動時に使う小型モニタとキーボードを手の届く場所に置く |

## 3. 全体アーキテクチャ

```
[Tails on Ryzen 機]
   Electrum ウォレット ---(常に Tor → Fulcrum の .onion)-------------> [Mac Studio]
                                                                          |
[MacBook Air]                                                             |
   ssh クライアント   ---(自宅: LAN 直結 / 外出先: SSH の .onion)-------->  |
                                                                          +-- Bitcoin Core (bitcoind)  ... P2P は Tor 経由
                                                                          +-- Fulcrum (Electrum server) ... bitcoind の RPC を読む
                                                                          +-- Tor (hidden service)     ... Fulcrum / SSH を .onion で公開
                                                                          +-- [フェーズ2] mempool.space 自前ホスト（LAN 内、必要なら .onion も）
                                                                          +-- [フェーズ3] LLM ランタイム（LAN 内から API 利用）
```

- **ウォレットは Tails 上の Electrum（既存）をそのまま使う（決定）**。Tails は全通信を Tor に強制し、LAN 直結を許さないため、Electrum からの接続は自宅でも外出先でも **Fulcrum の .onion 経由に統一**される。設定変更は「接続先サーバーを自分の .onion に固定し、他サーバーへの自動接続を切る」の 1 点のみ。
- Tails 側は永続ストレージの Electrum 機能が有効（確認済み）。サーバー設定を一度 .onion に固定すれば再起動後も保持される。
- 署名形態: Tails の Electrum がシードを持ち、そこで署名する（現状維持、決定）。将来「監視専用＋オフライン署名」やハードウェアウォレットに分ける場合も、Fulcrum 側の構成は変わらない。
- MacBook Air は管理端末専用。ウォレットも秘密鍵も置かない。自宅では LAN 直結、外出先では SSH の hidden service 経由で Mac Studio に入る（決定）。
- グローバル IP へのポート開放は一切しない（決定）。
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
- 導入: 公式リリースの macOS (arm64) バイナリを使い、リリース署名（GPG / SHA256SUMS）を検証してから配置する（決定）。Homebrew 版は更新タイミングと署名検証の手順が Homebrew 任せになるため採らない。
- 主要設定（案）:
  - `txindex=1`（決定。任意の txid を自分のノードで引けるようにする。mempool 自前ホストの前提条件でもある。ディスクを約 60GB 追加で使う）
  - `server=1`, RPC はローカルのみ許可
  - `proxy=127.0.0.1:9050` と `onlynet=onion`（決定: P2P は Tor のみ。自宅 IP を Bitcoin ネットワークに一切出さない。初回同期は 1 週間程度を見込む）
  - 受信側は torrc に静的に定義した hidden service で受ける（`bind=127.0.0.1:8334=onion`、`externalip=<onion>`）。Tor の ControlPort は使わない
  - `dbcache=16384`（IBD 中）→ 同期後 `4096` に変更
  - `prune=0`
- 自動起動: launchd（LaunchDaemon）。

### 5.2 Fulcrum（決定）

- 役割: Electrum プロトコルのサーバー。自分のウォレットの接続先。
- 導入: 公式リリースの macOS (arm64) バイナリを署名検証のうえ使用（決定）。公式 macOS ビルドが無いバージョンの場合のみソースからビルドする。
- 主要設定（案）:
  - bitcoind の RPC を参照
  - TCP 50001 を `127.0.0.1` にのみ待ち受け、Tor hidden service 経由で公開する。Tor 自体が経路を暗号化し、.onion アドレスがサーバーの真正性を保証するため、Tor 経由では SSL は不要
  - SSL 50002 は LAN 内から使うクライアントが現れた場合のみ有効化する（現状ウォレットは Tails のみなので当面不要）
  - `peering=false`, `announce=false`（他の Electrum サーバーと繋がず、公開サーバー一覧にも載せない。自分専用のサーバーとして存在を隠す）
  - 初期同期時はメモリ割り当てを多めにし、完了後に下げる
- 自動起動: launchd。bitcoind が起動していることを前提に順序を制御する。

### 5.3 Tor（決定）

- 役割: (a) bitcoind の P2P を Tor 経由にして IP と取引の紐づけを防ぐ、(b) Fulcrum を hidden service として公開し、外出先からも自前サーバーに繋げる。
- 導入: Homebrew の `tor`（決定）。
- hidden service は 2 つ用意する: (1) Fulcrum 用（50001/50002）、(2) SSH 用（22）。それぞれ別の .onion アドレスにし、SSH 側はクライアント認証（authorized clients）を有効にして第三者からは存在自体を見えなくする。
- hidden service の秘密鍵はバックアップ対象（失うと .onion アドレスが変わる）。

### 5.4 リモートアクセス（決定: LAN + Tor）

- **ウォレット（Tails）**: 常に Tor 経由で Fulcrum の .onion に接続する。場所を問わず同じ設定で動く。
- **管理（MacBook、自宅）**: Mac Studio に固定のプライベート IP（ルーターの DHCP 予約）と LAN 内ホスト名を与え、SSH は直接接続する。
- **管理（MacBook、外出先）**: MacBook 上の Tor クライアント経由で SSH の .onion に接続する。速度は落ちるが、第三者のサーバーを一切介さない。
- **使わないもの**: Tailscale などのメッシュ VPN、ルーターのポート開放、DDNS。
- MacBook 側の準備（決定）: `tor` を Homebrew で入れて `brew services` で常駐させ、`~/.ssh/config` で .onion ホストに対して `ProxyCommand`（`nc -x 127.0.0.1:9050 -X 5 %h %p`）を設定する。SSH の hidden service はクライアント認証付きにし、MacBook の認証鍵を Tor の `ClientOnionAuthDir` に置く。

### 5.5 mempool.space 自前ホスト（フェーズ 2、暫定採用。ネイティブ導入の手間を要確認）

- 役割: 自分のノードをソースにしたブロックエクスプローラー。トランザクション確認や手数料推定を、外部サイトにアドレスを送らずに行える。
- 導入: 公式手順は Docker 前提だが、本計画は Docker を使わないので、Node.js + MariaDB + nginx を Homebrew で入れてバックエンド・フロントエンドをソースからビルドする（ネイティブ導入）。ノード本体より保守の手間が大きいため、フェーズ 2 の着手時に「導入する価値があるか」を再判断する（未決）。
- 公開範囲: LAN 内の HTTP のみ。外出先から使いたくなったら hidden service を追加する。

### 5.6 LLM ランタイム（フェーズ 3）

- 役割: まずは「試してみる」。MacBook Air との差を体感する。
- ランタイム: **MLX（mlx-lm）を直接使う（決定）**。Apple 純正の推論基盤で最速。CLI で完結し、`mlx_lm.chat`（対話）、`mlx_lm.generate`（単発）、`mlx_lm.server`（OpenAI 互換 API）が揃っている。
- Python 環境: Homebrew の `uv` で専用の仮想環境を作り、システムの Python を汚さない。管理者ユーザーの領域に置く（ノード系のサービスユーザーとは分ける）。
- モデル置き場: `/opt/stack/models`（Hugging Face のキャッシュ先を環境変数 `HF_HOME` でここに向ける）。MLX 形式に変換済みのモデルは `mlx-community` から取得する。
- 最初に試すモデル（案）: 中型（70B〜235B 級）で速度を確認 → 最大級（DeepSeek V3/R1 級、4bit で約 400GB）を試す。
- GPU メモリ上限（決定 Q16）: 起動時に LaunchDaemon（`configs/launchd/com.local.gpu-wired-limit.plist`）で `iogpu.wired_limit_mb=458752`（448GB）を設定する。ノード系と OS の 64GB は GPU から構造的に守られる。
- 上限を 448GB にしても、実際に LLM を動かしていない間はメモリは空いたままなので、ノード系の運用に影響は無い。
- MacBook から使う場合は OpenAI 互換 API を LAN 内にのみ公開する（外出先からは使わない前提。必要になれば hidden service 化を検討）。

## 6. セキュリティ方針（案）

- Mac Studio は基本ヘッドレス運用。SSH で操作。再起動時のみ物理モニタとキーボードを使う。
- **FileVault 有効（決定）**。盗難・持ち出し時のデータ保護を優先する。代償として、停電や再起動のたびに物理的にパスワード入力が必要（LaunchDaemon もロック解除後にしか起動しない）。UPS の導入と、計画停止時の `fdesetup authrestart`（次回 1 回だけパスワード不要で再起動）で運用負担を抑える。
- RPC・Fulcrum・LLM API はすべて LAN または Tor のみに公開。グローバル IP に直接ポートを開けない。
- SSH は公開鍵認証のみ。パスワード認証は無効化する。
- **ユーザー分離（決定）**: 管理者ユーザー 1 名（SSH ログイン用、LLM 実験用）に加え、ノード系サービス専用の非管理者ユーザーを作る。
  - サービスユーザー名（案）: `_btcnode`（macOS のシステムユーザー慣習に倣い先頭にアンダースコア。ログインシェル無し、ホームディレクトリはデータ置き場）。
  - bitcoind・Fulcrum・Tor はすべてこのユーザーで LaunchDaemon として起動する（`UserName` キーで指定）。FileVault のロック解除後、誰もログインしなくても起動する。
  - 監視スクリプトも同ユーザーで動かす。Telegram の Bot トークンはこのユーザーのみ読める（`chmod 600`）ファイルに置く。

### 6.1 ディレクトリ配置（案）

```
/opt/stack/                 ... ルート（所有者: _btcnode、管理者は読み取りのみ）
  bin/                      ... bitcoind, bitcoin-cli, Fulcrum などの実行ファイル
  bitcoin/                  ... bitcoin.conf, blocks/, chainstate/, indexes/
  fulcrum/                  ... fulcrum.conf, db/, 証明書
  tor/                      ... torrc, hidden service ディレクトリ（鍵はここ）
  monitor/                  ... 監視スクリプト、secrets/（Bot トークン）
  models/                   ... LLM モデル（所有者は管理者ユーザー。LLM はノードと分離）
/Library/LaunchDaemons/     ... com.local.bitcoind.plist など
```
- ウォレットの秘密鍵は Mac Studio にも MacBook にも置かない。署名は Tails 上の Electrum でのみ行う。
- Mac Studio が侵害されても失われるのは「どのアドレスを監視しているか」という情報までで、資金は動かせない。この分離を崩さない。
- 将来的にハードウェアウォレット導入を検討する余地を残す（保留）。

## 7. 運用方針（案）

- UPS を導入する（決定）。停電時に bitcoind と Fulcrum を安全停止させてから電源を落とす。chainstate や Fulcrum の DB が壊れると再同期で数日を失う。macOS は USB 接続の UPS を標準で認識し、「システム設定 > バッテリー」でシャットダウン条件を設定できる。
  - Mac Studio の実消費は高負荷でも 300W 前後なので、500〜750VA クラスで足りる。ルーターと ONU も同じ UPS に繋ぎ、短時間の停電では Tor 接続が切れないようにする。
  - launchd の `ExitTimeOut` を長め（bitcoind は 600 秒）に設定し、シャットダウン時に dbcache のフラッシュが完了する前に強制終了されないようにする。
- 停電復帰後は FileVault のため自動起動しない。物理的にパスワードを入れて復帰させる（設計上の割り切り）。
- バックアップ（決定: 暗号化した外付け SSD / USB メモリ）:
  - 対象: `/opt/stack/{bitcoin/bitcoin.conf, fulcrum/fulcrum.conf, fulcrum/証明書, tor/torrc, tor/hidden service ディレクトリ, monitor/}` と `/Library/LaunchDaemons/com.local.*.plist`。合計で数 MB。
  - 対象外: チェーンデータ、Fulcrum の DB、LLM モデル（すべて再取得・再構築可能）。
  - 方法: APFS 暗号化でフォーマットした USB メモリに `tar` で固めてコピー。設定を変えたときに手動で更新する。ディスクは普段は抜いて保管する。
  - 設定ファイルの「内容」はこの Git リポジトリにも残す（鍵・トークン・RPC パスワードは除外し、`.gitignore` で防ぐ）。
- 監視（決定: シェルスクリプト＋launchd の最小構成）:
  - launchd の定期実行（例: 10 分ごと）で以下を確認する。
    - bitcoind の生存と RPC 応答、ブロック高が外部と比べて遅れていないか（比較先は Tor 経由で取得するか、単純に「直近 N 時間ブロック高が進んでいない」で判定する）
    - Fulcrum の生存と、bitcoind との高さの一致
    - Tor の生存と hidden service の到達性
    - ディスク残量（閾値: 残り 500GB を切ったら警告）
    - UPS の状態（`pmset -g batt` で商用電源かバッテリー駆動か）
  - 異常時のみ通知し、正常時は沈黙する。復旧時に「復旧」を 1 回だけ送る。
- 通知先（決定: Telegram Bot API）:
  - 通知本文には**アドレス・残高・txid など資産に紐づく情報を一切含めない**。「bitcoind 停止」「ブロック高停滞」「ディスク残量」程度の汎用文言に限定する。
  - 通知の送信は Tor 経由（`curl --socks5-hostname 127.0.0.1:9050`）にし、通知サービス側に自宅 IP を渡さない。
  - Bot トークンは設定ファイルに平文で置かず、macOS キーチェーンまたは権限を絞ったファイルに置く。
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
| Q1 | リモートアクセス方式 | Tailscale / LAN+Tor / SSH over Tor | **決定: LAN + Tor（SSH も hidden service）** |
| Q2 | FileVault | 有効（安全だが停電復帰が手動） / 無効（自動復帰） | **決定: 有効。再起動は手動ログイン** |
| Q3 | コンテナ方針 | すべてネイティブ / mempool 等のみ Docker | **決定: すべてネイティブ** |
| Q4 | Bitcoin Core / Fulcrum の導入経路 | Homebrew / 公式バイナリ / ソースビルド | **決定: 公式バイナリ＋署名検証（Tor のみ Homebrew）** |
| Q5 | txindex | 有効 / 無効 | **決定: 有効** |
| Q6 | 監視方法 | シェル＋launchd / 既製ツール | **決定: シェル＋launchd、通知はチャット（Tor 経由）** |
| Q6b | 通知チャット | Telegram / Discord | **決定: Telegram** |
| Q7 | UPS | 導入する / しない | **決定: 導入する** |
| Q8 | LLM ランタイム | LM Studio / Ollama / MLX | **決定: MLX（mlx-lm）** |
| Q9 | mempool.space をネイティブ導入する価値 | 導入する / 見送る | 未決（フェーズ 2 着手時に判断） |
| Q10 | ネットワーク | 固定 IP の割り当て方、LAN 内ホスト名、Wi‑Fi か有線か | **決定: 有線 10GbE、DHCP 予約で固定 IP** |
| Q11 | ログイン・ユーザー構成 | 管理者 1 ユーザー / サービス専用ユーザーを分ける | **決定: 管理者＋サービス専用ユーザー `_btcnode`** |
| Q12 | 設定・鍵のバックアップ先 | 外付け SSD / MacBook / 紙（Tor 鍵は小さい） | **決定: 暗号化した外付け SSD / USB メモリ** |
| Q13 | Fulcrum の SSL 証明書 | 自己署名（Electrum 側で固定して信頼） / 使わず Tor のみ | **決定: Tor のみ（TCP 50001 を hidden service で公開）。ウォレットが Tails のため LAN 直結が無い** |
| Q17 | Tails の永続ストレージで Electrum 機能が有効か | 有効 / 未設定 | **確認済み: 有効** |
| Q14 | bitcoind の P2P 経路 | Tor のみ（onlynet=onion） / Tor＋クリアネット | **決定: Tor のみ** |
| Q15 | MacBook 側の Tor クライアント | Homebrew の tor 常駐 / Tor Browser 起動時のみ | **決定: Homebrew の tor を常駐** |
| Q16 | GPU メモリ上限の設定タイミング | 起動時に固定 / LLM 使用時だけ手動 | **決定: 起動時に launchd で 448GB に固定** |
| Q18 | Fulcrum の Apple Silicon 向け公式バイナリの有無 | 公式 arm64 バイナリ / ソースビルド | 未決（着手時にリリースページで確認） |
| Q19 | Bitcoin Core の blockfilterindex（BIP158） | 有効（約 10GB、将来の軽量クライアント用） / 無効 | **決定: 有効** |
| Q20 | macOS の自動アップデート方針 | 自動適用 / 通知のみで手動適用 / 無効 | 未決 |
| Q21 | Bitcoin Core / Fulcrum / Tor の更新方針 | 新版が出たら都度 / 数か月ごとにまとめて / セキュリティ修正のみ | 未決 |
| Q22 | 時刻同期・スリープ・Spotlight・Time Machine など macOS の固有設定 | 設計書に一覧化して確定 | 未決 |
