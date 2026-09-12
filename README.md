# AirDrop Auto Accept

macOSのAccessibility APIを使い、指定したAndroid端末から届くAirDrop／Quick Share通知を自動承認する個人向けユーティリティです。写真に限らず、動画、PDF、ZIPなどすべてのファイル種別を対象にします。

現在の既定の送信元は `Pixel 10 Pro Fold` です。macOS標準の受信処理を利用するため、受信ファイルは通常 `~/Downloads` に保存されます。アプリはバックグラウンド専用で、メニューバーやDockを占有しません。

## 仕組み

- Finder、通知センターなどのAirDrop UIをAccessibility APIで監視
- 送信元名が一致した通知だけを処理
- 「受け入れる」と、表示された場合は「Downloads」を自動選択
- AirDropプロトコルへの直接接続やネットワーク通信は行わない

## 必要環境

- macOS 13以降
- Swift 6 toolchain
- 初回のみ、システム設定の「プライバシーとセキュリティ > アクセシビリティ」でアプリを許可

## ビルド

```sh
./build.sh
```

arm64／x86_64のUniversal Binaryを作成し、`../../outputs/AirDropAutoAccept.app` に出力します。ビルド後に起動する場合は次のコマンドを使います。

```sh
open ../../outputs/AirDropAutoAccept.app
../../outputs/AirDropAutoAccept.app/Contents/MacOS/AirDropAutoAccept --status
```

`--status` はAccessibility権限を `granted` または `not-granted` で表示します。

## ダウンロード

公開LPは [konaito.github.io/airdrop-auto-accept](https://konaito.github.io/airdrop-auto-accept/) です。直接ダウンロードする場合は [AirDropAutoAccept.dmg](https://konaito.github.io/airdrop-auto-accept/downloads/AirDropAutoAccept.dmg) を使ってください。現在のDMGは未公証の個人ビルドです。

## 設定

送信元名はUserDefaultsで変更できます。

```sh
defaults write com.konaito.airdrop-auto-accept SenderName "端末名"
```

変更後はアプリを再起動してください。

## 注意事項

Accessibility APIで取得できるUI構造はmacOSのバージョンや通知表示状態に依存します。権限付与後、実際に複数種類のファイルを送って動作を確認してください。意図しない送信元を処理しないよう、既定では端末名を限定しています。

## ライセンス

MIT License。詳細は [`LICENSE`](LICENSE) を参照してください。

## コントリビュート

変更を送る前に `./build.sh` と `plutil -lint Info.plist` を実行し、Accessibility権限を付与した実機で動作を確認してください。UI検出を変更した場合は、送信元名とファイル種別、macOSのバージョン、Downloadsへの保存結果をPRに記載してください。
