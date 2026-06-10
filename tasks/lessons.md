# threejs-lab lessons

実験を作るたびに得た再利用可能な教訓。セッション開始時に確認する。

## 2026-06-09 — 02-photo-terrain（画像地形化）

### Three.js: リソース破棄は geometry だけでなく texture も
- メッシュを作り直すとき `geometry.dispose()` は呼んでも `Texture.dispose()` を忘れがち。
  GPU テクスチャは GC では解放されず、画像を差し替えるたびに VRAM がリークする
  （4096px texture ≈ 最大 64MB/枚）。画像 D&D で繰り返し差し替える UI では致命的。
- 対策: 新テクスチャ代入の直前に `if (currentTex) currentTex.dispose();`。
  使い回す material 本体は dispose しない（共有インスタンス）。
- 出典: Code Reviewer サブエージェントの指摘（Major #1）。

### 任意入力（D&D）を受けるなら分割数に上限を
- `segY = round(SEG_X * aspect)` は通常画像なら問題ないが、1x4000 のような病的な
  アスペクト比だと数億頂点を要求して即クラッシュ。`Math.min(MAX_SEG_Y, ...)` で上限。
- 同じ値を 2 箇所（輝度グリッド生成とメッシュ生成）で独立計算する場合は、必ず共通
  ヘルパー（`segYFor(aspect)`）に切り出す。片方だけクランプすると配列長が不一致になる。

### PlaneGeometry の高さマップ整合
- 頂点行 iy=0 はプレーン上端。デフォルト UV（v=1=上端）+ Texture.flipY=true で
  画像 row 0（上端）が上端に表示される。よって輝度サンプリングは **上下反転しない**
  （row 0 → 頂点上端）のが正しい。反転すると額の隆起が顎に出る。

### ライセンス素材は public repo に置かない
- Adobe Stock 等の素材原本は `.gitignore`。ローカルでは原寸を使い、公開版は
  プロシージャル生成 + D&D アップロードにフォールバックさせるとツールとして成立し、
  再配布問題も回避できる。

## 2026-06-10 — 02-photo-terrain 改良（操作性）

### 「自動回転」に OrbitControls.autoRotate を使うと浅いレリーフで被写体が崩れる
- `controls.autoRotate` は水平360°オービット。高さ 0.3 程度の浅いレリーフを
  真横から見る瞬間が来て、起伏のエッジだけになり顔が真っ黒に崩壊する。
- 対策: 全周回転ではなく **正面中心の首振り**（`sin` で azimuth ±24°往復）を
  ループ内で自前実装。正面付近に留まるので被写体が常に判別でき立体感も出る。
- 出典: 自動回転をデフォルトONにした際に Playwright スクショで崩壊を発見。

### autoRotate 系をデフォルトONにしたら「ユーザー操作で必ず止める」をセットで
- 自動演出（首振り等）と OrbitControls のドラッグ/ズームは両立しない。ドラッグ後に
  演出が即再開すると、ユーザーが選んだ角度・ズームを毎フレーム奪い返して「壊れてる」
  体感になる（例外は出ないので smoke test を通過してしまう）。
- 対策: `controls` の `start` イベントで演出フラグを OFF にし、トグルUIにも反映。
  トグルを唯一の真実源にする。`isDragging` だけでは離した瞬間に再開して不十分。
- 自前で `camera.position` を毎フレーム書くなら半径は固定値でなく
  `Math.hypot(x,z)` で現在値を維持（でないとズームが効かない）。
- 出典: Code Reviewer の指摘（Major #1/#2）。

### CanvasTexture は dispose だけでなく source canvas も 0×0 に
- `tex.dispose()` で GPU 側は解放されるが、`CanvasTexture` が参照する元 `<canvas>`
  （最大 4096² ≒ 64MB の backing store）は GC されるまで残る。D&D で何枚も差し替える
  公開デモではメモリスパイクの原因。dispose 後に `canvas.width = canvas.height = 0`
  で backing store を即解放する。[[texture-dispose]] の続き。
- 出典: Code Reviewer の指摘（Major #3）。
