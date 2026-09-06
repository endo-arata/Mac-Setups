# Tails 側の手順: Electrum を自前 Fulcrum に固定する

- 前提: Tails の永続ストレージで Electrum 機能が有効（確認済み）。
- 前提: Mac Studio 側で Fulcrum の初期同期が完了し、`hs-fulcrum` の .onion アドレスが分かっている。

## 1. 接続先を固定する

1. Tails を起動し、永続ストレージのロックを解除して Electrum を開く。
2. 画面右下のネットワーク状態（丸いアイコン）をクリックしてネットワーク設定を開く。
3. 「Server」タブで **Select server automatically のチェックを外す**。
4. Server 欄に `<hs-fulcrum の .onion アドレス>` を入れ、ポートを `50001`、プロトコルを **TCP（`t`）** にする。SSL は使わない（Tor が経路を暗号化し、.onion が相手の真正性を保証する）。
5. 「Proxy」タブは Tails が既に Tor（SOCKS5 `127.0.0.1:9050`）に設定しているので変更しない。
6. 閉じると Fulcrum に接続され、右下の丸が緑になる。

## 2. 他サーバーへの接続を完全に止める（oneserver）

自動選択を外しただけでは、Electrum はヘッダー検証のために他の公開サーバーへも接続し続ける。自分の Fulcrum 以外に一切繋がないようにするには `oneserver` を有効にする。

- 永続ストレージ内の Electrum 設定ファイル（`~/.electrum/config`）に次を追加する。

```
"oneserver": true,
"server": "<hs-fulcrum の .onion アドレス>:50001:t",
"auto_connect": false,
```

- 設定ファイルは JSON。既存の項目との間のカンマに注意する。Electrum を終了してから編集し、再起動して右下のアイコンが緑になることを確認する。

## 3. 確認事項

- ウォレットの残高・履歴が表示される（Fulcrum がアドレスを索引済みであること）。
- ネットワーク設定の「Overview」でサーバーが自分の .onion のみになっている。
- 送金テストは少額で 1 回行い、mempool に入ること、承認されることを確認する。

## 4. 注意

- Fulcrum の初期同期が終わる前に繋ぐと、残高が 0 や古い状態で表示される。同期完了を待つ。
- .onion アドレスは Mac Studio 側の `/opt/stack/tor/hs-fulcrum/hostname` にある。転記ミスを防ぐため、MacBook で表示したものを目視で照合する（Tails には LAN 経由でファイルを渡せない）。
- Tails の Electrum はシードを持つホットウォレットなので、Tails の起動媒体と永続ストレージのパスフレーズの管理が資産の安全性そのものになる。この点は本計画の範囲外だが、変えない。
