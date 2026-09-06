# フェーズ 1: ノード構築の実行手順

- 版: v0.1（設計中）
- 上位文書: `docs/plan.md`、設計根拠: `docs/node-design.md`
- 前提: `docs/phase0-macos.md` の完了チェックリストがすべて済んでいる。
- 完了条件: Tails の Electrum が自前 Fulcrum の .onion にだけ接続して残高・送金ができる。MacBook から Tor 経由で SSH できる。設定と鍵が暗号化 USB にある。
- 作業場所: 特記がなければ MacBook から LAN 経由で SSH した Mac Studio 上。`<...>` は環境に合わせて置き換える。

## 所要時間の見込み

| 段階 | 目安 | 備考 |
|---|---|---|
| 1. バイナリ取得と検証 | 1 時間 | |
| 2. Tor 起動と .onion 発行 | 30 分 | |
| 3. SSH onion のクライアント認証 | 30 分 | |
| 4. bitcoind 起動と初回同期（IBD） | **約 1 週間**（Tor のみ、決定 Q27） | 放置。監視は手動 |
| 5. Fulcrum の初期インデックス | 1〜2 日 | IBD 完了後 |
| 6. Tails の Electrum 接続 | 30 分 | |
| 7. 外出先からの SSH 確認 | 30 分 | |
| 8. バックアップ | 30 分 | |

## 1. バイナリの取得と署名検証

### 1.1 Bitcoin Core

MacBook でも Mac Studio でもよい。ここでは Mac Studio 上で行う（`gnupg` が要る）。

```
brew install gnupg
VER=<最新の安定版。例 29.0>
mkdir -p ~/dl && cd ~/dl
curl -O https://bitcoincore.org/bin/bitcoin-core-${VER}/bitcoin-${VER}-arm64-apple-darwin.tar.gz
curl -O https://bitcoincore.org/bin/bitcoin-core-${VER}/SHA256SUMS
curl -O https://bitcoincore.org/bin/bitcoin-core-${VER}/SHA256SUMS.asc

# ビルダーの公開鍵を取り込む（guix.sigs リポジトリ）
git clone --depth 1 https://github.com/bitcoin-core/guix.sigs.git
gpg --import guix.sigs/builder-keys/*.gpg

# 署名検証。複数の "Good signature" が出ること。"BAD signature" が 1 つでもあれば中止
gpg --verify SHA256SUMS.asc SHA256SUMS

# ハッシュ照合。"bitcoin-<VER>-arm64-apple-darwin.tar.gz: OK" が出ること
shasum -a 256 --ignore-missing --check SHA256SUMS

tar xzf bitcoin-${VER}-arm64-apple-darwin.tar.gz
sudo install -o root -g wheel -m 755 bitcoin-${VER}/bin/bitcoind bitcoin-${VER}/bin/bitcoin-cli /opt/stack/bin/
/opt/stack/bin/bitcoind --version
```

- `gpg --verify` の「この鍵は信頼された署名で証明されていません」という警告は、鍵の信頼度を設定していないだけなので問題ない。重要なのは Good か BAD か。
- 初回実行で Gatekeeper に止められたら、検証済みであることを確認したうえで `sudo xattr -dr com.apple.quarantine /opt/stack/bin/` を実行する。

### 1.2 Fulcrum

GitHub の Fulcrum リリースページ（cculianu/Fulcrum）で macOS 用の資産を確認する（未決 Q18）。

**arm64 バイナリがある場合:**

```
FVER=<Fulcrum のバージョン>
cd ~/dl
curl -LO https://github.com/cculianu/Fulcrum/releases/download/v${FVER}/Fulcrum-${FVER}-arm64-macos.zip   # 実際のファイル名はリリースページで確認
curl -LO https://github.com/cculianu/Fulcrum/releases/download/v${FVER}/Fulcrum-${FVER}-shasums.txt
curl -LO https://github.com/cculianu/Fulcrum/releases/download/v${FVER}/Fulcrum-${FVER}-shasums.txt.asc
# 作者（Calin Culianu）の公開鍵を取り込んで検証。鍵指紋はリポジトリの README で照合する
gpg --verify Fulcrum-${FVER}-shasums.txt.asc Fulcrum-${FVER}-shasums.txt
shasum -a 256 --ignore-missing --check Fulcrum-${FVER}-shasums.txt
unzip Fulcrum-${FVER}-arm64-macos.zip
sudo install -o root -g wheel -m 755 Fulcrum-${FVER}-arm64-macos/Fulcrum Fulcrum-${FVER}-arm64-macos/FulcrumAdmin /opt/stack/bin/
/opt/stack/bin/Fulcrum --version
```

**無い場合（ソースビルド）:**

```
brew install qt@5
cd ~/dl && git clone --depth 1 --branch v${FVER} https://github.com/cculianu/Fulcrum.git
cd Fulcrum
git verify-tag v${FVER}          # タグ署名の確認
/opt/homebrew/opt/qt@5/bin/qmake -makefile PREFIX=/opt/stack Fulcrum.pro
make -j"$(sysctl -n hw.ncpu)"
sudo install -o root -g wheel -m 755 Fulcrum FulcrumAdmin /opt/stack/bin/
```

## 2. Tor の起動と .onion アドレスの発行

```
sudo cp configs/tor/torrc /opt/stack/tor/torrc
sudo mkdir -p /opt/stack/tor/data /opt/stack/tor/hs-bitcoind /opt/stack/tor/hs-fulcrum /opt/stack/tor/hs-ssh/authorized_clients
sudo chown -R _btcnode:staff /opt/stack/tor
sudo chmod 700 /opt/stack/tor /opt/stack/tor/data /opt/stack/tor/hs-*
sudo -u _btcnode /opt/homebrew/bin/tor -f /opt/stack/tor/torrc --verify-config     # 構文確認

sudo cp configs/launchd/com.local.tor.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.tor.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.tor.plist
sleep 10; tail -n 20 /opt/stack/tor/tor.log      # "Bootstrapped 100%" を待つ

# 発行された .onion を控える（この 3 行の出力を後で転記する）
sudo cat /opt/stack/tor/hs-bitcoind/hostname
sudo cat /opt/stack/tor/hs-fulcrum/hostname
sudo cat /opt/stack/tor/hs-ssh/hostname
```

- hs-ssh は `authorized_clients/` が空の間は認証なしで公開される。3 節を終えるまで .onion を外に出さない。

## 3. SSH hidden service のクライアント認証

### 3.1 鍵の生成（MacBook 上で 2 組）

```
brew install tor openssl
mkdir -p ~/onion-auth && cd ~/onion-auth && chmod 700 .
for name in macbook spare; do
  openssl genpkey -algorithm x25519 -out ${name}.priv.pem
  priv=$(openssl pkey -in ${name}.priv.pem -outform DER | tail -c 32 | base32 | tr -d '=')
  pub=$(openssl pkey -in ${name}.priv.pem -pubout -outform DER | tail -c 32 | base32 | tr -d '=')
  echo "descriptor:x25519:${pub}" > ${name}.auth
  echo "${priv}" > ${name}.priv.b32
done
cat macbook.auth spare.auth
```

### 3.2 サーバー側に公開鍵を置く（Mac Studio）

```
sudo sh -c 'cat > /opt/stack/tor/hs-ssh/authorized_clients/macbook.auth' <<EOF
descriptor:x25519:<macbook.auth の公開鍵部分>
EOF
sudo sh -c 'cat > /opt/stack/tor/hs-ssh/authorized_clients/spare.auth' <<EOF
descriptor:x25519:<spare.auth の公開鍵部分>
EOF
sudo chown -R _btcnode:staff /opt/stack/tor/hs-ssh
sudo chmod 600 /opt/stack/tor/hs-ssh/authorized_clients/*
sudo launchctl kickstart -k system/com.local.tor
```

### 3.3 MacBook 側の Tor クライアント設定

```
ONION=<hs-ssh の .onion アドレス（.onion を除いた 56 文字）>
mkdir -p /opt/homebrew/etc/tor/onion_auth && chmod 700 /opt/homebrew/etc/tor/onion_auth
echo "${ONION}:descriptor:x25519:$(cat ~/onion-auth/macbook.priv.b32)" > /opt/homebrew/etc/tor/onion_auth/${ONION}.auth_private
chmod 600 /opt/homebrew/etc/tor/onion_auth/*.auth_private
echo "ClientOnionAuthDir /opt/homebrew/etc/tor/onion_auth" >> /opt/homebrew/etc/tor/torrc
brew services restart tor
```

- `configs/macbook/ssh_config` の内容を `~/.ssh/config` に追記し、`<hs-ssh の .onion>` と LAN の IP を埋める。
- `spare.priv.pem` と `spare.priv.b32` は暗号化 USB に移し、MacBook からは削除する（`rm -P`）。
- LAN 上で `ssh studio-tor` が通ることを確認（Tor 経由なので LAN 内でも数秒かかる）。

## 4. bitcoind の起動と初回同期

```
sudo cp configs/bitcoin/bitcoin.conf /opt/stack/bitcoin/bitcoin.conf
sudo sed -i '' "s|<hs-bitcoind の .onion アドレス>|$(sudo cat /opt/stack/tor/hs-bitcoind/hostname)|" /opt/stack/bitcoin/bitcoin.conf
sudo chown _btcnode:staff /opt/stack/bitcoin/bitcoin.conf
sudo chmod 640 /opt/stack/bitcoin/bitcoin.conf
grep externalip /opt/stack/bitcoin/bitcoin.conf          # 転記を目視確認

sudo cp configs/launchd/com.local.bitcoind.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.bitcoind.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.bitcoind.plist
sleep 30; tail -n 30 /opt/stack/data/bitcoin/debug.log
```

管理者のシェルに alias を入れておく（`~/.zshrc`）:

```
alias btc='sudo -u _btcnode /opt/stack/bin/bitcoin-cli -datadir=/opt/stack/data/bitcoin'
alias fadmin='sudo -u _btcnode /opt/stack/bin/FulcrumAdmin -p 8000'
```

確認:

```
btc getnetworkinfo | grep -A3 '"name": "onion"'     # reachable: true
btc getpeerinfo | grep -c '"network": "onion"'      # 数分後に 8〜10 前後
btc getblockchaininfo | grep -E '"blocks"|"headers"|verificationprogress'
```

- `verificationprogress` が 0.9999 以上になるまで放置する。Tor のみなので約 1 週間。
- この間 LLM は動かさない。
- 同期完了後、`dbcache=16384` を `dbcache=4096` に書き換えて再起動:

```
sudo sed -i '' 's/^dbcache=16384/dbcache=4096/' /opt/stack/bitcoin/bitcoin.conf
sudo launchctl kickstart -k system/com.local.bitcoind
```

## 5. Fulcrum の初期インデックス（IBD 完了後）

```
sudo cp configs/fulcrum/fulcrum.conf /opt/stack/fulcrum/fulcrum.conf
sudo sed -i '' "s|<hs-fulcrum の .onion アドレス>|$(sudo cat /opt/stack/tor/hs-fulcrum/hostname)|" /opt/stack/fulcrum/fulcrum.conf
sudo chown _btcnode:staff /opt/stack/fulcrum/fulcrum.conf
sudo chmod 640 /opt/stack/fulcrum/fulcrum.conf
grep tor_hostname /opt/stack/fulcrum/fulcrum.conf

sudo cp configs/launchd/com.local.fulcrum.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.fulcrum.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.fulcrum.plist
tail -f /opt/stack/fulcrum/launchd.log        # "Processed height: N" が進む。Ctrl-C で抜ける
```

- 完了の目安: ログに `Block height <最新>, up-to-date` が出る。`fadmin getinfo` の高さが `btc getblockcount` と一致する。
- 完了後、`fast-sync` 行を消して再起動:

```
sudo sed -i '' '/^fast-sync/d' /opt/stack/fulcrum/fulcrum.conf
sudo launchctl kickstart -k system/com.local.fulcrum
```

- ローカルからの疎通確認（Electrum プロトコルの `server.version`）:

```
printf '{"id":1,"method":"server.version","params":["test","1.4"]}\n' | nc 127.0.0.1 50001
```

## 6. Tails の Electrum を接続する

`docs/tails-electrum.md` の手順に従う。転記する .onion は `hs-fulcrum` のもの。Tails には LAN でファイルを渡せないので、MacBook の画面に表示した文字列を目視で入力し、入力後に Electrum の接続先表示で照合する。

## 7. 外出先からの SSH 確認

MacBook をスマホのテザリングなど自宅以外の回線に繋ぎ、`ssh studio-tor` で入れることを確認する。Wi‑Fi をオフにして LAN 経路が使えない状態で試す。

## 8. バックアップ（暗号化 USB）

```
# USB メモリを APFS 暗号化でフォーマット（中身は消える。デバイス名は diskutil list で確認）
diskutil list
sudo diskutil eraseDisk APFS BACKUP disk<N>
sudo diskutil apfs encryptVolume disk<M> -user disk -passphrase '<長いパスフレーズ>'   # または GUI のディスクユーティリティで「APFS（暗号化）」

# 設定と鍵を固めてコピー（Mac Studio 上、root で）
sudo tar czf /Volumes/BACKUP/stack-config-$(date +%Y%m%d).tgz \
  /opt/stack/secrets /opt/stack/scripts \
  /opt/stack/bitcoin/bitcoin.conf /opt/stack/fulcrum/fulcrum.conf \
  /opt/stack/tor/torrc /opt/stack/tor/hs-bitcoind /opt/stack/tor/hs-fulcrum /opt/stack/tor/hs-ssh \
  /opt/stack/monitor \
  /Library/LaunchDaemons/com.local.*.plist
sudo diskutil eject /Volumes/BACKUP
```

- MacBook の `~/onion-auth/spare.*` もこの USB に入れる。
- USB は普段は抜いて、FileVault の復旧キーを書いた紙とは別の場所に保管する。

## 9. 完了チェックリスト

- [ ] `btc getblockchaininfo` の `verificationprogress` が 0.9999 以上で、`initialblockdownload` が false
- [ ] `btc getnetworkinfo` で onion のみ reachable、`getpeerinfo` の全ピアが onion
- [ ] `fadmin getinfo` の高さが `btc getblockcount` と一致
- [ ] Tails の Electrum が自分の .onion のみに接続し、残高が正しい
- [ ] 少額の送金が mempool に入り承認された
- [ ] 外出先の回線から `ssh studio-tor` で入れる
- [ ] `sudo fdesetup authrestart` で再起動し、無人で Stack ボリュームがマウントされ、tor → bitcoind → Fulcrum が上がる
- [ ] 暗号化 USB に設定・鍵・予備の onion 認証鍵が入っている
- [ ] `dbcache` を 4096 に、`fast-sync` を削除済み
