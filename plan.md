# 発表練習デスクトップアプリ 実装計画

## 1. 目的

macOS上で発表開始と同時にマイク音声と指定画面を監視し、画面下部の複数審査員がリアルタイムに反応する常駐アプリを作る。

リアルタイムコメントは次の二系統を同時に動かす。

- 高速レーン: 音量、無音、話速、フィラー、スライド滞在時間などをルールで判定する。
- 理解レーン: 直近の文字起こし、スライドOCR、発表設定をLLMへ渡し、内容に即した短いコメント候補を作る。

終了後はセッション全体を根拠付きで採点し、改善案を提示する。

## 2. MVPの対象

- macOS 14以降、Apple Siliconを第一対象とする。
- 審査員は `tempo`、`clarity`、`slide`、`audience` の4人。
- 透明・常に最前面・クリック透過可能なオーバーレイを表示する。
- マイク音声、画面変化、部分文字起こし、LLMコメントを統合する。
- LLMが利用できなくてもルール判定とUIは動作し続ける。
- 初期設定では発表動画全体を保存せず、イベント、文字起こし、特徴量、変更時の縮小画像だけを保存する。

## 3. 非対象

- Windows対応
- カメラによる姿勢・表情解析
- 発表中の長文アドバイス
- キャラクターや素材による既存ゲーム作品の直接的な模倣

## 4. 技術構成

- 言語: Swift 6
- UI: SwiftUI + AppKit
- 2D演出: SpriteKit
- マイク: AVAudioEngine
- 画面・システム音声: ScreenCaptureKit
- OCR: Vision
- 文字起こし: 初期実装は抽象化された `TranscriptionProviding`。後続で whisper.cpp/Core MLアダプターを追加する。
- LLM: 抽象化された `CommentGenerating`。HTTP実装と疑似実装を分離する。
- 永続化: MVPではJSONL。スキーマ安定後にSQLiteを追加する。
- ビルド・テスト: Swift Package Manager

## 5. モジュール構成

```text
Package.swift
Sources/
  PresentationContracts/     # 全ラインが共有するデータ契約
  PresentationCapture/       # 音声・画面・セッション入力
  PresentationFeedback/      # ルール、LLM候補、演出調停、採点
  PresentationOverlay/       # 審査員、吹き出し、オーバーレイ
  PresentationApp/           # composition root / macOSアプリ
Tests/
  PresentationContractsTests/
  PresentationCaptureTests/
  PresentationFeedbackTests/
  PresentationOverlayTests/
Fixtures/
  Sessions/                   # UI/AIを独立開発するJSONL
Assets/
  Judges/                     # キャラクター定義とアニメーション情報
docs/
  event-contract.md
  comment-policy.md
```

## 6. 共有イベント契約

すべてのモジュール間通信は `PresentationEvent` を使う。UIは実データとFixtureを区別しない。

主要イベント:

- `sessionStarted` / `sessionStopped`
- `audioMetric`
- `speechPartial` / `speechFinal`
- `slideChanged`
- `ruleCommentCandidate`
- `llmCommentCandidate`
- `judgeReaction`
- `timerUpdated`
- `scoreUpdated`

コメント候補は最低限、次を持つ。

- 審査員ID
- 表示文字列
- 感情・アニメーション種別
- 優先度
- 信頼度
- 根拠となる文字列またはイベントID
- 有効期限
- `rule` または `llm` の生成元

## 7. リアルタイム処理

### 高速レーン

- 音声特徴抽出: 10〜20ms単位
- 無音・音量反応: 200ms以内
- 画面差分検出: 200〜300ms単位
- OCR: 画面変更検出時だけ実行
- ルール判定は同期的で決定的にする。

### LLM理解レーン

LLMへの入力:

- 直近20〜30秒の文字起こし
- 現在スライドのOCR
- 発表タイトル、目的、対象者
- 現在セクションと残り時間
- 直近30秒に表示したコメント
- 4人の審査員ペルソナ

呼び出し条件:

- 文が確定したとき
- スライドが切り替わったとき
- 発話継続中の2〜4秒ハートビート

高速化条件:

- 1回の呼び出しで最大3候補を生成する。
- 出力は短い構造化JSONに限定する。
- 同時実行数は原則1。
- 2.5秒を超えた要求や文脈が古くなった結果は破棄する。
- LLMを待つ間も高速レーンとアニメーションを止めない。

### 演出ディレクター

LLMやルールはUIを直接操作しない。`FeedbackDirector` が候補を調停し `judgeReaction` を発行する。

優先順位:

1. 発表継続に必要な警告
2. 内容に具体的に反応するLLMコメント
3. 時間・構成に関する指摘
4. コミカルな小ネタ

制約:

- 原則として同時表示は1件。
- 審査員ごとに6〜12秒のクールダウンを持つ。
- 同一意味の連投を抑制する。
- 吹き出しは原則18〜28文字、最大40文字。
- 有効期限切れの候補は表示しない。

## 8. UIデータの独立開発

UI担当はキャプチャやLLMの完成を待たず、JSONLのFixtureを再生して実装する。

最初に用意するFixture:

- 通常進行
- 話速過多
- 長い無音
- 情報量過多のスライド
- ルールとLLM候補の競合
- LLM遅延・タイムアウト
- コメント集中時の優先順位

キャラクターの見た目と挙動はデータ化する。

- `judge.json`: ID、表示名、テーマ色、吹き出し位置
- `animations.json`: idle、happy、confused、panic、sleepなどの状態
- Sprite Atlasまたは仮のベクター描画
- 効果音のIDと再生タイミング

## 9. 3人の担当

### 開発者A: キャプチャ・基盤・統合

- Swift PackageとmacOSアプリ骨格
- 共有イベント契約
- セッションイベントバス
- AVAudioEngine入力と軽量音声特徴抽出
- ScreenCaptureKitアダプター
- JSONL記録・再生
- 最終統合と性能計測

### 開発者B: AI・評価

- ルールエンジン
- `CommentGenerating` プロトコル
- LLM向け入力コンテキストと構造化出力
- 候補の期限切れ、キャンセル、重複排除
- `FeedbackDirector`
- 最終採点の基礎モデル

### 開発者C: UI・演出

- 透明オーバーレイ
- SpriteKit審査員シーン
- 吹き出し
- アニメーション状態機械
- UI用Fixtureプレイヤー
- キャラクターマニフェスト

各担当は自分のモジュールとテストを主に編集する。`PresentationContracts` の変更は全員で確認する。

## 10. 実装順

### フェーズ0: 契約と技術検証

- [x] Swift Packageを作成する。
- [x] イベント契約を実装する。
- [x] JSONL Fixtureを作成する。
- [x] 各モジュールの単体テストを起動できるようにする。
- [x] 透明ウィンドウとSpriteKit描画を検証する。
- [x] マイク入力とRMS計測を検証する。

### フェーズ1: 動く縦切り

- [x] マイク音量イベントを発行する。
- [x] ルールがコメント候補を生成する。
- [x] ディレクターが `judgeReaction` を選ぶ。
- [x] UIが審査員と吹き出しを表示する。
- [x] セッションをJSONLへ保存・再生する。

### フェーズ2: LLMコメント

- [x] 部分文字起こしをイベント契約へ追加する。
- [x] 疑似LLMの構造化レスポンスを実装する。
- [x] キャンセル、期限切れ、古い応答の破棄を実装する。
- [x] ルールとLLMの競合をテストする。
- [ ] 実LLM向けHTTPアダプターと資格情報設定を実装する。

### フェーズ3: 画面解析と最終評価

- [ ] 画面変更検出と自アプリ除外を実装する。
- [ ] OCRを追加する。
- [ ] 最終スコアと根拠タイムラインを作る。

## 11. 初期性能目標

- ルール反応: 入力から200ms以内
- LLMコメント: p50 1.5秒以内、p95 2.5秒以内を目標
- オーバーレイ: 60fpsを維持
- キャプチャ処理中もUIメインスレッドをブロックしない
- LLM停止・ネットワーク断でも高速レーンが継続する
- 古い画面フレームはキューに溜めず破棄する

## 12. 最初の完了条件

以下がローカルで再現できた時点を最初の縦切り完了とする。

1. アプリまたはデモ実行を開始する。
2. Fixtureまたはマイク入力からイベントが流れる。
3. ルールコメントと疑似LLMコメントが競合する。
4. ディレクターが1件を選択する。
5. UIまたはCLI表示に審査員、感情、吹き出しが現れる。
6. 同じイベント列をJSONLに保存し再生できる。
7. `swift test` が成功する。
