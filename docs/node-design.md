# ノード詳細設計（Bitcoin Core + Fulcrum + Tor）

- 版: v0.1（設計中）
- 上位文書: `docs/plan.md`
- 設定ファイル案: `configs/`

## 1. プロセス構成

すべて `_btcnode` ユーザーの LaunchDaemon として動かす。launchd には依存関係の機能が無いので、起動順は「各プロセスが相手を待つ」性質に任せる。

| プロセス | 実行ファイル | 待ち受け | 依存 |
|---|---|---|---|
| tor | `/opt/homebrew/bin/tor` | SOCKS `127.0.0.1:9050`、hidden service 3 つ | なし |
| bitcoind | `/opt/stack/bin/bitcoind` | RPC `127.0.0.1:8332`、P2P `127.0.0.1:8334`（onion 受信用）、ZMQ `127.0.0.1:28332` | tor（無くても起動はする。接続できないだけ） |
| Fulcrum | `/opt/stack/bin/Fulcrum` | Electrum TCP `127.0.0.1:50001` | bitcoind（RPC が応答するまで自分で待つ） |

- 全ポートを `127.0.0.1` にのみ束縛する。LAN からも直接は届かない。外に出る経路は Tor の hidden service だけ。
- SSH（macOS の「リモートログイン」）だけは LAN からも使うので、LAN の固定 IP でも待ち受ける。

## 2. 通信経路

```
                +---------------------------- Mac Studio ----------------------------+
                |                                                                    |
 Tor network <==| tor :9050 (SOCKS) <-- bitcoind (outbound, onlynet=onion)           |
                |                                                                    |
 Tor network ==>| hs-bitcoind  (xxx.onion:8333)  --> 127.0.0.1:8334  bitcoind (inbound)|
 Tor network ==>| hs-fulcrum   (yyy.onion:50001) --> 127.0.0.1:50001 Fulcrum          |
 Tor network ==>| hs-ssh       (zzz.onion:22, client auth) --> 127.0.0.1:22 sshd      |
                |                                                                    |
 LAN (MacBook) =| 192.168.x.y:22 sshd                                                |
                +--------------------------------------------------------------------+

 Tails (Ryzen) --Tor--> yyy.onion:50001  （Electrum。場所を問わずこの 1 経路）
 MacBook（自宅）--LAN--> 192.168.x.y:22
 MacBook（外出）--Tor--> zzz.onion:22
```

hidden service は 3 つとも torrc に静的に定義する（Bitcoin Core の Tor 自動設定は使わない）。理由:

- 鍵が `/opt/stack/tor/hs-*/` に固まり、バックアップ対象が明確になる。
- Tor の ControlPort を開けずに済む。
- .onion アドレスが再起動で変わらない。

## 3. Bitcoin Core

### 3.1 導入

1. bitcoincore.org のダウンロードページから `bitcoin-<ver>-arm64-apple-darwin.tar.gz` と `SHA256SUMS`、`SHA256SUMS.asc` を取得。
2. ビルダーの GPG 鍵（guix.sigs リポジトリで公開）で署名を検証し、`shasum -a 256 --check` でハッシュを照合。
3. `bitcoind` と `bitcoin-cli` を `/opt/stack/bin/` に配置。所有者 root、実行権限あり。
4. 初回起動時に macOS の Gatekeeper に止められる場合は `xattr -d com.apple.quarantine` で隔離属性を外す（署名検証を通した後にのみ行う）。

### 3.2 設定の要点（`configs/bitcoin/bitcoin.conf`）

| 項目 | 値 | 理由 |
|---|---|---|
| `daemon=0` | launchd が前面プロセスとして管理する | launchd はフォークして消えるプロセスを追えない |
| `txindex=1` | 全 tx を引ける | 決定事項 |
| `prune=0` | 全ブロック保持 | 決定事項 |
| `dbcache=16384` | IBD 中の上限値 | 同期後は `4096` に下げる（メモリを LLM に返す） |
| `proxy=127.0.0.1:9050`, `onlynet=onion` | 発信は Tor のみ | 決定事項 |
| `listen=1`, `bind=127.0.0.1:8334=onion`, `externalip=<hs-bitcoind の onion>` | 受信は Tor hidden service 経由 | 静的 hidden service を使う |
| `listenonion=0`, `torcontrol` 無し | Tor 自動設定を使わない | 上記 |
| `discover=0`, `upnp=0`, `natpmp=0` | LAN/グローバル IP を探索・公開しない | 存在を出さない |
| `rpcbind=127.0.0.1`, `rpcallowip=127.0.0.1` | RPC はローカルのみ | |
| RPC 認証 | クッキーファイル（既定） | パスワードを設定ファイルに書かない。Fulcrum も同じユーザーなので読める |
| `zmqpubhashblock=tcp://127.0.0.1:28332` | 新ブロック通知 | Fulcrum がポーリングより早く追随できる |
| `rpcthreads=16`, `rpcworkqueue=64` | Fulcrum の初期同期を速くする | 32 コアあるので余裕 |
| `maxmempool=2000` | mempool を大きめに保持 | メモリに余裕がある。手数料推定の精度が上がる |
| `blockfilterindex=1` | BIP158 フィルタ（未決 Q19） | 約 10GB。将来の軽量クライアント用 |

### 3.3 初回同期（IBD）の見込み

- Tor のみで行うため帯域は Tor リレー次第。数日から 1 週間を見込む。
- IBD 中は CPU（検証）とディスク I/O が張り付く。この期間は LLM を動かさない。
- 進捗確認: `bitcoin-cli -datadir=/opt/stack/bitcoin getblockchaininfo | grep -E 'blocks|headers|verificationprogress'`
- 完了後の作業: `dbcache` を `4096` に下げて再起動。

## 4. Fulcrum

### 4.1 導入

1. GitHub の Fulcrum リリースページで macOS 向けバイナリの有無を確認（Q18）。arm64 ビルドがあればそれを使い、無ければソースビルド（Qt5 と rocksdb を Homebrew で導入）。
2. リリース署名（作者の GPG 鍵）とハッシュを検証。
3. `Fulcrum` と `FulcrumAdmin` を `/opt/stack/bin/` に配置。

### 4.2 設定の要点（`configs/fulcrum/fulcrum.conf`）

| 項目 | 値 | 理由 |
|---|---|---|
| `datadir=/opt/stack/fulcrum/db` | インデックスの置き場 | 約 200GB |
| `bitcoind=127.0.0.1:8332`, `rpccookie=/opt/stack/bitcoin/.cookie` | RPC 接続 | クッキー認証 |
| `tcp=127.0.0.1:50001` | Electrum TCP | Tor 経由のみなので SSL 不要 |
| `ssl` 未設定 | SSL を開かない | 決定 Q13 |
| `peering=false`, `announce=false` | 他サーバーと繋がない・公開しない | 自分専用 |
| `tor_hostname=<hs-fulcrum の onion>`, `tor_tcp_port=50001` | サーバー自身が自分の onion を知る | `server.features` の応答用 |
| `zmq_block=tcp://127.0.0.1:28332` | 新ブロック通知 | |
| `fast-sync=16000` | 初期同期時の UTXO キャッシュ（MB） | 同期後はこの行を消す |
| `db_mem=4096` | 定常時の DB キャッシュ（MB） | |
| `worker_threads=16`, `bitcoind_clients=8` | 並列度 | bitcoind の `rpcthreads` より少なくする |
| `admin=127.0.0.1:8000` | FulcrumAdmin 用 | ローカルのみ |

### 4.3 初期同期の見込み

- bitcoind の IBD 完了後に開始する（同時進行は両者が遅くなる）。
- 全ブロックを RPC で読んでインデックスを作る。1〜2 日を見込む。
- 完了後の作業: `fast-sync` 行を削除して再起動。

## 5. Tor

### 5.1 導入

- `brew install tor`。実行ファイルは `/opt/homebrew/bin/tor`。
- Homebrew の `brew services` は使わず、自前の LaunchDaemon で `_btcnode` として起動する（Homebrew のサービスは管理者ユーザーで動いてしまうため）。

### 5.2 設定の要点（`configs/tor/torrc`）

- `SocksPort 127.0.0.1:9050`（bitcoind の発信用）
- hidden service 3 つ（`hs-bitcoind`, `hs-fulcrum`, `hs-ssh`）。すべて v3。
- `hs-ssh` は `authorized_clients/` にクライアント公開鍵を置き、鍵を持たないクライアントからは存在を検出できないようにする。
- ログはファイルに `notice` レベルのみ。

### 5.3 hidden service 鍵の扱い

- 初回起動時に `/opt/stack/tor/hs-*/` 配下に鍵と `hostname` が生成される。
- `hostname` の内容（.onion）を bitcoin.conf の `externalip`、fulcrum.conf の `tor_hostname`、Tails の Electrum、MacBook の ssh config に転記する。
- ディレクトリ丸ごとをバックアップ（暗号化 USB）。

## 6. launchd

`configs/launchd/` の 3 つの plist を `/Library/LaunchDaemons/` に置く。共通事項:

- `UserName` = `_btcnode`
- `RunAtLoad` = true、`KeepAlive` = true（落ちたら再起動）
- `ThrottleInterval` = 30（再起動の間隔。連続クラッシュ時の暴走防止）
- `ExitTimeOut` = bitcoind 600 秒、Fulcrum 300 秒、tor 30 秒（SIGTERM 後にこれだけ待ってから SIGKILL）
- 標準出力・エラーは `/opt/stack/<name>/launchd.log` へ

操作:

```
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.tor.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.bitcoind.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.fulcrum.plist

sudo launchctl bootout system/com.local.fulcrum     # 停止
sudo launchctl print system/com.local.bitcoind      # 状態確認
```

停止順は Fulcrum → bitcoind → tor。起動順はその逆。

## 7. ユーザーとパーミッション

```
sudo sysadminctl -addUser _btcnode -fullName "Bitcoin Node Service" -shell /usr/bin/false -home /opt/stack -password -   # ログイン不可
sudo mkdir -p /opt/stack/{bin,bitcoin,fulcrum/db,tor,monitor/secrets,models}
sudo chown -R _btcnode:staff /opt/stack/{bitcoin,fulcrum,tor,monitor}
sudo chmod 700 /opt/stack/tor /opt/stack/monitor/secrets
sudo chown -R root:wheel /opt/stack/bin && sudo chmod 755 /opt/stack/bin/*
sudo chown -R <admin>:staff /opt/stack/models
```

- `_btcnode` はログインシェル無し、パスワード無し、管理者グループに入れない。
- 管理者ユーザーは `sudo -u _btcnode` で `bitcoin-cli` を叩くか、クッキーファイルを読める権限を自分に付ける（後者は `chmod 640` とグループ設定で対応）。

## 8. SSH

- macOS の「リモートログイン」を有効化し、対象ユーザーを管理者ユーザーのみに限定。
- `/etc/ssh/sshd_config.d/100-hardening.conf`（`configs/ssh/`）で公開鍵認証のみに制限。
- MacBook の `~/.ssh/config`（`configs/macbook/ssh_config`）に LAN 用と Tor 用の 2 エントリ。

## 9. 監視（`/opt/stack/monitor/`）

10 分ごとに launchd（`StartInterval=600`）で `check.sh` を実行し、状態ファイルに前回結果を残す。前回正常・今回異常なら「異常」を、前回異常・今回正常なら「復旧」を Telegram に送る。

チェック項目と閾値:

| 項目 | 判定 |
|---|---|
| bitcoind 生存 | `bitcoin-cli getblockchaininfo` が応答する |
| ブロック追随 | 直近 2 時間ブロック高が増えていない → 警告（Tor 切断や停止の兆候） |
| Fulcrum 生存 | `FulcrumAdmin getinfo` が応答し、高さが bitcoind と一致（差 1 以内） |
| tor 生存 | `127.0.0.1:9050` に接続できる |
| ディスク | `/` の空き < 500GB → 警告 |
| 電源 | `pmset -g batt` が「Battery Power」→ 警告 |

通知の送信:

```
curl --silent --socks5-hostname 127.0.0.1:9050 \
  -d chat_id="$CHAT_ID" -d text="$MSG" \
  "https://api.telegram.org/bot$TOKEN/sendMessage"
```

トークンと chat_id は `/opt/stack/monitor/secrets/telegram.env`（`chmod 600`、所有者 `_btcnode`）から読む。

## 10. 未決事項（ノード周り）

| # | 項目 | 状態 |
|---|---|---|
| N1 | Fulcrum の arm64 公式バイナリの有無（Q18） | 着手時に確認 |
| N2 | blockfilterindex の有効化（Q19） | 未決 |
| N3 | 管理者ユーザーから `bitcoin-cli` を叩く方法（sudo か、クッキーのグループ読み取りか） | 未決 |
| N4 | Fulcrum の初期同期を bitcoind の IBD 完了後に始める運用にするか、同時に始めるか | 案: 完了後 |
| N5 | 監視スクリプトの実装（設計は上記） | フェーズ 2 |
