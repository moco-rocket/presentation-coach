# Presentation Coach

発表中の音声と画面を監視し、複数の審査員キャラクターがルールとLLMの両方からリアルタイムに反応するmacOS向けプロトタイプです。

## Current prototype

- Swift 6の共有イベント契約
- AVAudioEngineによるマイク入力とRMS・無音計測
- ScreenCaptureKitの画面ソース列挙
- ルールベースの低遅延コメント候補
- 非同期・キャンセル可能なLLMコメント生成インターフェースと疑似実装
- 期限、クールダウン、重複、優先度を扱うフィードバックディレクター
- SwiftUI・SpriteKitの4人審査員オーバーレイ
- JSONLの記録、再生、UI Fixture
- 計測値を根拠にした100点満点の基礎採点

## Development

```bash
swift test
swift run PresentationApp
swift run PresentationApp --demo
swift run PresentationApp --ui-demo
./scripts/run-app.sh
```

`--demo` はルール候補と疑似LLM候補を競合させ、選択された吹き出し、基礎スコア、保存したJSONLの場所を表示します。

`--ui-demo` は画面下部に透明オーバーレイを表示し、`Fixtures/Sessions/ui-demo.jsonl` の審査員リアクションを再生して自動終了します。素早く確認する場合は `--ui-demo-speed 10` を追加できます。

引数なしで起動するとメニューバーに常駐します。メニューの「練習を開始」「練習を停止」からオーバーレイを操作できます。
「権限を確認…」では、マイクと画面収録の状態確認、許可要求、システム設定への移動ができます。
通常起動とmacOS権限の確認には、安定したBundle IDと権限説明文を含む開発用`.app`が必要なため、`./scripts/run-app.sh`を使用してください。`swift run PresentationApp --ui-demo`はFixtureによるUI確認専用です。

マイク・画面収録をmacOSへ登録するには、XcodeでApple IDにサインインして作成した`Apple Development`証明書が必要です。`scripts/run-app.sh`はKeychain内の証明書を自動選択します。複数ある場合は`PRESENTATION_COACH_SIGNING_IDENTITY`で指定できます。

設計、分担、性能目標は [`plan.md`](plan.md) を参照してください。
