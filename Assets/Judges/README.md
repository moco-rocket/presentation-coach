# Judge manifests

UI素材制作時のマニフェスト原本です。`Sources/PresentationOverlay/Resources/Judges` の同名ファイルがアプリへ同梱されます。

- `themeColorHex` / `accentColorHex`: 仮キャラクターと将来の素材の配色
- `stageSlot`: 左からの表示順
- `bubbleAnchor`: 将来のキャラクター別吹き出し位置（0〜1の正規化座標）
- `animations`: 感情からアニメーション素材IDへの対応
- `soundIDs`: 感情に付随する任意の効果音ID

`Concepts/judges-expression-sheet-v1.png` は4人×5表情のデザイン原本です。
アプリには背景を透過した同シートを
`Sources/PresentationOverlay/Resources/Judges/judges-expression-sheet-v1.png`
として同梱し、`JudgeArtworkSheet` が審査員IDと感情から表示セルを選択します。
`happy` と `impressed`、`confused` と `panic` は同じ基本表情を共有し、
SpriteKitの演出で反応差を付けます。

素材更新時は同名の同梱用JSONにも反映してください。
