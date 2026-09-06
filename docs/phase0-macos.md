# フェーズ 0: macOS 初期設定と準備

- 版: v0.1（設計中）
- 上位文書: `docs/plan.md`
- 目的: Mac Studio を「ヘッドレスで 24 時間動く、外に何も漏らさないサーバー」に仕立て、MacBook から SSH で操作できる状態にする。
- 完了条件: MacBook から LAN 経由で公開鍵認証の SSH に入れ、`_btcnode` ユーザーと `/opt/stack` が用意され、Homebrew と tor が入っている。

## 0. 物理準備

| 項目 | 内容 |
|---|---|
| 設置 | 通気の良い場所。UPS と同じ場所に置く |
| 電源 | UPS（500〜750VA）経由。ルーターと ONU も同じ UPS に接続 |
| ネットワーク | 内蔵 10GbE ポートに有線接続。Wi‑Fi は使わない |
| 入力 | 初期設定と FileVault 解除用のキーボード。USB 有線を推奨（Bluetooth を完全に切れる。未決 Q24） |
| 表示 | 初期設定と再起動時のみ使う小型モニタ（HDMI）。普段は外してよい |
| USB | UPS の USB 信号ケーブルを Mac Studio に接続（macOS がバッテリー状態を認識する） |

## 1. 初回起動（セットアップアシスタント）

| 画面 | 選択 | 理由 |
|---|---|---|
| 言語・地域 | 日本語 / 日本 | |
| アクセシビリティ | スキップ | |
| ネットワーク | 有線が認識されていることを確認 | |
| 移行アシスタント | 「今は情報を転送しない」 | 他 Mac の設定を持ち込まない |
| Apple ID | **サインインしない（推奨、未決 Q23）** | App Store も iCloud も使わない。Apple にこの機体の稼働状況を紐づけない |
| 利用規約 | 同意 | |
| アカウント作成 | 管理者ユーザーを 1 人。名前は個人を特定しないもの（例: `admin` ではなく短い任意の語）。パスワードは長いパスフレーズ | このアカウントが SSH ログイン先になる |
| 位置情報サービス | オフ | |
| 解析（Apple と共有） | すべてオフ | |
| スクリーンタイム | 今はしない | |
| Siri | 使わない | |
| Apple Intelligence | 使わない（表示された場合） | |
| Touch ID | Mac Studio には無い | |
| FileVault | **有効にする**。復旧キーは「iCloud に保存しない」を選び、表示された復旧キーを紙に書いて暗号化 USB と別の場所に保管 | 決定 Q2 |
| 外観 | 任意 | |

## 2. システム設定（GUI）

設定アプリで行う項目。あとで CLI で確認できるものは 3 節にコマンドも載せる。

### 2.1 一般

- **ソフトウェアアップデート > 自動アップデート**（決定 Q20）
  - 「アップデートを確認」オン
  - 「新しいアップデートが利用可能な場合はダウンロード」オン
  - 「macOS アップデートをインストール」**オフ**
  - 「セキュリティ対応とシステムファイルをインストール」**オン**
- **共有**
  - 「リモートログイン」**オン**。アクセスを許可: 「次のユーザーのみ」→ 管理者ユーザーだけ
  - 「リモートログインユーザーにフルディスクアクセスを許可」オフ
  - 画面共有、ファイル共有、メディア共有、プリンタ共有、リモートマネージメント、Bluetooth 共有、インターネット共有、AirPlay レシーバー: すべて**オフ**
- **AirDrop と Handoff**: すべてオフ
- **日付と時刻**: 「日付と時刻を自動的に設定」オン。時刻がずれると bitcoind がピアを拒否する（許容 ±70 分）
- **ログインウインドウ**（ロック画面の項目）: ゲストユーザー無効

### 2.2 プライバシーとセキュリティ

- FileVault: オンになっていることを確認
- ファイアウォール: **オン**。オプションで「ステルスモードを有効にする」**オン**、「内蔵ソフトウェアが受信接続を受け付けるのを自動的に許可」オン（sshd 用）
- 位置情報サービス: オフ
- 解析と改善: すべてオフ
- Apple 広告: パーソナライズ広告オフ

### 2.3 ネットワーク

- Wi‑Fi: **オフ**（メニューバーからも消す）
- Ethernet: DHCP のまま。固定 IP はルーター側の DHCP 予約で与える（決定 Q10）。IP を確認してメモする
- Bluetooth: USB キーボードなら**オフ**（未決 Q24）

### 2.4 省エネルギー（デスクトップは「エネルギー」）

- 「ディスプレイがオフのときに自動でスリープさせない」**オン**
- 「停電後に自動的に起動」**オン**（FileVault の画面で止まるが、ログイン待ち状態まで自動で進む）
- 「ネットワークアクセスによるスリープ解除」オフ
- 「Power Nap」オフ
- UPS 接続後に現れる「UPS」タブ: バッテリー残量が 20% を切ったらシャットダウン（数値は UPS 容量に合わせて後で調整）

### 2.5 ロック画面

- 「使用していない場合はスクリーンセーバを開始」: 開始しない（ヘッドレスなので不要）
- 「スクリーンセーバの開始後またはディスプレイがオフになった後にパスワードを要求」: すぐに
- ログインウインドウの表示: 「名前とパスワード」（ユーザー一覧を出さない）

### 2.6 Spotlight

- 「検索結果」内の Siri の提案などをすべてオフ
- 「検索のプライバシー」に `/opt/stack` を追加（作成後）。チェーンデータのインデックス作成で I/O を浪費させない

### 2.7 Time Machine

- 使わない（推奨、未決 Q26）。設定と鍵は暗号化 USB へ手動でコピーする（決定 Q12）

## 3. ターミナルで行う設定

管理者ユーザーでログインし、ターミナルで実行する。ここから先は MacBook から SSH で行ってもよい（3.3 まで済ませた後）。

### 3.1 ホスト名

個人を特定しない短い名前にする。以下は例。

```
sudo scutil --set ComputerName  studio
sudo scutil --set HostName      studio
sudo scutil --set LocalHostName studio
```

### 3.2 電源・スリープ（GUI の裏付けと補完）

```
sudo pmset -a sleep 0 disksleep 0 displaysleep 10
sudo pmset -a autorestart 1 womp 0 powernap 0
pmset -g            # 反映確認
```

### 3.3 リモートログインと SSH の強化

```
sudo systemsetup -setremotelogin on
sudo mkdir -p /etc/ssh/sshd_config.d
sudo cp configs/ssh/sshd_config.d/100-hardening.conf /etc/ssh/sshd_config.d/   # <管理者ユーザー名> を書き換えてから
sudo sshd -t                                   # 構文チェック
sudo launchctl kickstart -k system/com.openssh.sshd
```

MacBook 側:

```
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_studio -C studio
ssh-copy-id -i ~/.ssh/id_ed25519_studio.pub <管理者ユーザー名>@192.168.<x>.<y>   # パスワード認証を切る前に 1 回だけ
ssh -i ~/.ssh/id_ed25519_studio <管理者ユーザー名>@192.168.<x>.<y>              # 鍵で入れることを確認
```

鍵で入れることを確認してから、`100-hardening.conf` を置いて sshd を再起動する（順序を逆にすると締め出される）。

### 3.4 ファイアウォール（GUI の裏付け）

```
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

### 3.5 時刻同期の確認

```
sudo systemsetup -getusingnetworktime
sntp -sS time.apple.com      # 手動で一度合わせる。以後は自動
```

### 3.6 ログインウインドウ・ゲスト

```
sudo defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
```

### 3.7 Homebrew と基本ツール

```
xcode-select --install                    # コマンドラインツール
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew analytics off
brew install tor uv
```

- Homebrew のインストールスクリプトは実行前に内容を一読する。
- `tor` は Homebrew で入れるが、`brew services` は使わない（`_btcnode` で動かすため。`docs/node-design.md` 5.1）。
- `uv` は LLM フェーズ用の Python 環境管理（`docs/plan.md` 5.6）。

### 3.8 サービスユーザーとディレクトリ

```
sudo sysadminctl -addUser _btcnode -fullName "Bitcoin Node Service" -shell /usr/bin/false -home /opt/stack -password -
sudo mkdir -p /opt/stack/{bin,bitcoin,fulcrum/db,tor,monitor/secrets,models}
sudo chown -R _btcnode:staff /opt/stack/bitcoin /opt/stack/fulcrum /opt/stack/tor /opt/stack/monitor
sudo chmod 700 /opt/stack/tor /opt/stack/monitor/secrets
sudo chown root:wheel /opt/stack /opt/stack/bin
sudo chmod 755 /opt/stack /opt/stack/bin
sudo chown -R "$(whoami)":staff /opt/stack/models
```

- `_btcnode` はログインウインドウに表示されない（アンダースコア始まりのシステムユーザー扱い）。表示される場合は `sudo dscl . -create /Users/_btcnode IsHidden 1`。
- `/opt/stack` を別 APFS ボリュームにする案（未決 Q25）を採る場合は、ここで `diskutil apfs addVolume` で作成し `/opt/stack` にマウントする。

### 3.9 Spotlight 除外とログローテーション

```
sudo touch /opt/stack/.metadata_never_index     # 別ボリュームの場合に有効。フォルダの場合は GUI の「検索のプライバシー」で除外
sudo cp configs/newsyslog/stack.conf /etc/newsyslog.d/stack.conf
```

`configs/newsyslog/stack.conf` は各サービスの `launchd.log` を週次で圧縮ローテーションする（bitcoind の `debug.log` は自前で縮小するので対象外）。

### 3.10 GPU wired メモリ上限（フェーズ 3 で有効化してもよい）

```
sudo cp configs/launchd/com.local.gpu-wired-limit.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.gpu-wired-limit.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.gpu-wired-limit.plist
sysctl iogpu.wired_limit_mb      # 458752 になっていれば反映済み
```

## 4. 完了チェックリスト

- [ ] FileVault が有効で、復旧キーを紙で保管している
- [ ] Apple ID にサインインしていない（Q23 の決定に従う）
- [ ] Wi‑Fi・Bluetooth（USB キーボードの場合）・各種共有・AirDrop・Handoff がオフ
- [ ] ファイアウォールがオンでステルスモード
- [ ] 「停電後に自動的に起動」がオンで、スリープしない
- [ ] 時刻が自動同期されている
- [ ] MacBook から LAN 経由で公開鍵認証のみで SSH できる（パスワード認証が拒否される）
- [ ] `_btcnode` と `/opt/stack` が作成され、パーミッションが設計どおり
- [ ] `brew` と `tor`、`uv` が入っている
- [ ] 一度 `sudo fdesetup authrestart` で再起動し、パスワード入力なしに復帰してサービスが上がることを確認（LaunchDaemon 登録後）
- [ ] 電源ケーブルを抜いて UPS がバッテリー駆動に切り替わり、macOS がそれを認識することを確認

## 5. この段階で行わないこと

- Bitcoin Core / Fulcrum のバイナリ配置と起動（フェーズ 1、`docs/node-design.md`）
- Tor の hidden service 作成（フェーズ 1）
- Telegram Bot の作成と監視スクリプト（フェーズ 2）
- MLX の導入とモデル取得（フェーズ 3）
