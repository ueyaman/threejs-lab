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

## 2026-06-10 — 03-mona-lisa-warp（マウスドラッグ歪み）

### 「引きずって粘る」質感は速度注入だけでは出ない＝位置ドラッグ＋低剛性バネ
- マウス移動を頂点「速度」に積分注入するだけだと、止めた瞬間バネが素直に戻るだけで
  中村勇吾作品の「カーソルに粘着して伸びる」感が出ない（最大変位が画像幅の1/4程度で
  地味）。対策: ポインタ近傍頂点を**毎フレーム位置ごとカーソル進行方向へドラッグ**
  （`x += ptrVel.x * w`）＋一部を速度に banking してオーバーシュート。剛性を下げ
  （stiff 4→2.2）減衰を上げる（damp 0.86→0.91）と、粘り＋ぷるぷる余韻が両立。
- 数値で確認: 変位が 0.63→2.10（planeW=2.28 相当）に増、止めると振動しながら0へ収束。

### キャッシュした派生データは「リビルドの起点」で必ず無効化する
- グリッド辺インデックスを `let cache = null; if(!cache) build()` で遅延生成したが、
  画像差し替え（buildMesh）で `cache=null` リセットを忘れ、**別アスペクト画像をD&D
  すると旧グリッドの index で新しい（小さい）頂点配列を範囲外アクセス → NaN/破損**。
  Three.js の `getX(i)`/`setXYZ` は範囲外でも例外を出さず**サイレント破損**するので
  気づきにくい。対策: `disposeMesh()`（リビルドの単一起点）で `cache=null`。
- **検証の盲点**: 同じアスペクト比の画像でしかD&Dを試さないと一生再現しない。
  派生キャッシュを持つUIは「形の違う入力」で必ずテストする。
- 出典: Code Reviewer の指摘（Critical）。レビュー無しなら確実に本番に出ていた。

### パブリックドメイン画像は本番同梱できる（ライセンス素材と扱いを分ける）
- モナリザ等 PD 画像は Wikimedia Commons から取得しリポジトリ同梱可（02 の Adobe Stock
  とは逆で gitignore 不要）。Wikimedia は任意サイズの thumbnail 生成を制限しているので、
  Commons API（`action=query&prop=imageinfo&iiurlwidth=N`）で**許可済み thumburl を取得**
  してから落とす（直 URL で 600px 等を叩くと 400 "Use thumbnail sizes listed"）。

## 2026-06-10/11 — 04-emergent-portrait（生成AI画像 → Tripo3D → 2D→3D遷移）

### 画像生成 → 3D化のパイプラインは「2枚作り分け + i2i」で人物同一性を担保
- 1枚の画像に「美術的な情緒」と「3D化しやすいクリーンさ」を両立させようとしない。
  (a) Tripo 入力用＝正面・均一光・輪郭明瞭のクリーン版、(b) 2D背景プレート用＝薄暗い
  室内の美術版、の2枚を作り、**クリーン版を i2i の参照画像にして背景版を生成**すると
  同一人物のまま雰囲気だけ変えられる（nano banana pro: medias の role:image に prior
  job_id を渡す）。NotebookLM 正典照合の裁定:「光と輪郭は3Dのためクリーンに保ち、
  不穏さは視線・表情・髪のタイトさに全振り」。

### Tripo3D REST フロー（upload → image_to_model → poll → pbr_model）
- `https://api.tripo3d.ai/v2/openapi` に upload → task 作成（type: image_to_model）→
  status poll → `output.pbr_model` の URL から GLB を DL。1生成 ≈ 30クレジット。
  再現スクリプト: `docs/260610/tripo-gen.sh`。

### 生成GLBの「正面」は仕様で決まっていない＝yaw掃引で実測する
- Tripo のバストは **−X 向き**でエクスポートされていた（+Z 正面を仮定すると横顔になる）。
  `model.rotation.y` を 90° 刻みでスクショ比較して正面を確定（今回は `Math.PI * 1.5`）。
  生成系3Dは毎回向きが違い得るので、取り込んだら必ず正面を実測する。
- あわせて Tripo は metallic=1/roughness=1 で出してくるので、石膏調にするなら
  metalness 0 / roughness 0.92 へ上書き（テクスチャは活かす）。

### 画像→3D→Web は「素材をそのまま置くと 30MB 超」— Draco + WebP で 94% 削減
- Tripo GLB はジオメトリが支配的（26万頂点 f32 = 14.35MB。テクスチャは 2048² JPEG
  ×3 で計 400KB しかない）→ **テクスチャ縮小は効かず、Draco 圧縮が本命**。
  `npx @gltf-transform/cli draco in.glb out.glb` だけで 14.7MB → 1.75MB（見た目無劣化）。
- HTML 側は `DRACOLoader` + `setDecoderPath(CDN の three と同バージョンの
  examples/jsm/libs/draco/gltf/)` が必要。デコーダ実費は +70KB で元が取れる。
- 暗い写真の背景プレートは WebP 圧縮が極端に効く（17.8MB PNG → 1600px q85 で 78KB、
  バンディングなし）。cwebp/magick が無い環境でも **ffmpeg の libwebp** で変換できる
  （`ffmpeg -i in.png -vf scale=1600:-2 -c:v libwebp -quality 85 out.webp`）。
- 原寸 PNG・無圧縮 GLB は中間素材として `.gitignore`（`*.orig.glb` 等）し、配信用だけ
  コミットする。合計ロード 32.6MB → 1.86MB。
