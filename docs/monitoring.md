# 監視設計（check.sh と Telegram 通知）

- 版: v0.1（設計中）
- 上位文書: `docs/plan.md` 7 節、`docs/node-design.md` 9 節
- 実装: `configs/monitor/check.sh`, `configs/monitor/notify.sh`, `configs/launchd/com.local.monitor.plist`
- 方針: シェルスクリプトと launchd だけで完結する。外部依存は `curl` と Tor のみ。異常時と復旧時にだけ通知し、正常時は沈黙する。

## 1. 動作

- launchd が **10 分ごと**に `_btcnode` として `/opt/stack/monitor/check.sh` を実行する。
- 各チェックは「OK / FAIL」を返し、前回結果を `/opt/stack/monitor/state/<check>.status` に残す。
- **OK → FAIL** に変わったときだけ「異常」を、**FAIL → OK** に変わったときだけ「復旧」を Telegram に送る。連続して FAIL でも 1 回しか送らない。
- 通知の送信は Tor（SOCKS `127.0.0.1:9050`）経由。Tor が落ちていて送れなかった通知は `state/pending.txt` に溜め、次回以降に再送する。
- 1 日 1 回（既定 09:00 以降の最初の実行）、生存確認として 1 行の状態報告を送る（**未決 M1**: 送るか送らないか）。これが届かなければ「Mac ごと落ちている」か「Tor が長時間落ちている」と分かる。

## 2. チェック項目

| 名前 | 判定 | FAIL の意味 |
|---|---|---|
| `tor` | `nc -z 127.0.0.1 9050` が成功 | Tor 停止。通知も送れないので pending に溜まる |
| `bitcoind` | `bitcoin-cli getblockcount` が数値を返す | bitcoind 停止、または RPC 応答なし |
| `stall` | ブロック高が **2 時間**以上増えていない（IBD 中は判定しない） | Tor 経由のピア接続が全滅、または bitcoind がハング |
| `fulcrum` | Electrum プロトコルの `blockchain.headers.subscribe` が高さを返す | Fulcrum 停止 |
| `fulcrum_lag` | Fulcrum の高さが bitcoind より **3 以上**低い | Fulcrum が追随していない |
| `disk` | `/opt/stack/data` の空き < **500GB** | チェーン成長で逼迫。放置すると bitcoind が止まる |
| `power` | `pmset -g batt` が「Battery Power」 | 停電中。UPS で動いている |

閾値はスクリプト冒頭の変数で変更できる。

## 3. 通知の文面

資産に紐づく情報（アドレス、残高、txid、ウォレット名）は一切含めない。文面は次の形式に固定する。

```
[studio] 異常: bitcoind が応答しません
[studio] 復旧: bitcoind
[studio] 異常: ブロック高が 2 時間以上進んでいません (height 912345)
[studio] 異常: ディスク残量 480GB
[studio] 異常: バッテリー駆動（停電の可能性）
[studio] 日次: height 912345 / fulcrum 912345 / disk 5210GB / AC
```

ブロック高は公開情報なので含めてよい。

## 4. Telegram Bot の準備（1 回だけ）

1. スマホの Telegram で `@BotFather` に `/newbot` を送り、名前とユーザー名を決める。表示される **トークン**を控える。
2. 作った Bot に何か 1 通メッセージを送る（Bot は自分から会話を始められない）。
3. Mac Studio で自分の chat_id を取得する（Tor 経由）:

```
curl --silent --socks5-hostname 127.0.0.1:9050 "https://api.telegram.org/bot<トークン>/getUpdates"
```

出力の `"chat":{"id":123456789,...` の数値が chat_id。

4. `/opt/stack/monitor/secrets/telegram.env` を作る（`_btcnode` のみ読める）:

```
sudo -u _btcnode sh -c 'umask 077; cat > /opt/stack/monitor/secrets/telegram.env' <<EOF
TELEGRAM_TOKEN=<トークン>
TELEGRAM_CHAT_ID=<chat_id>
EOF
```

5. 手動送信で疎通確認:

```
sudo -u _btcnode /opt/stack/monitor/notify.sh "[studio] テスト通知"
```

- Bot のトークンは「この Bot として発言できる権限」でしかなく、ノードや資産には触れない。漏れたら BotFather で再発行する。
- Bot の会話は Telegram 社のサーバーに残る。だから文面に資産情報を入れない。

## 5. 導入手順

```
sudo mkdir -p /opt/stack/monitor/state
sudo cp configs/monitor/check.sh configs/monitor/notify.sh /opt/stack/monitor/
sudo chown -R _btcnode:staff /opt/stack/monitor
sudo chmod 700 /opt/stack/monitor/secrets
sudo chmod 755 /opt/stack/monitor/check.sh /opt/stack/monitor/notify.sh

# 1 回手動で実行して動作確認（初回は全チェックの状態ファイルを作るだけで通知しない）
sudo -u _btcnode /opt/stack/monitor/check.sh
cat /opt/stack/monitor/state/*.status

sudo cp configs/launchd/com.local.monitor.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.monitor.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.monitor.plist
```

動作テスト: `sudo launchctl bootout system/com.local.fulcrum` で Fulcrum を止め、10 分以内に「異常: Fulcrum」が届き、`bootstrap` で戻すと「復旧: Fulcrum」が届くことを確認する。

## 6. 未決事項

| # | 項目 | 状態 |
|---|---|---|
| M1 | 日次の生存報告を送るか | 未決（案: 送る） |
| M2 | 日次報告の時刻 | 未決（案: 09:00） |
| M3 | ディスク閾値 | 案: 500GB |
| M4 | ブロック停滞の閾値 | 案: 2 時間（平均 10 分間隔なら 2 時間無ブロックは約 0.0006% の確率） |
