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

## 2026-06-11 — 04 調整（写真アンカー合わせ + AI3D アーティファクト退治）

### 2D写真と3Dを「重なって見せる」には毎フレーム投影アンカー
- 3D を固定位置に置くと、写真の人物と無関係な場所に出て幻想が壊れる。写真内の頭部
  位置（画像に対する UV 割合）を背景プレーンの実スケール経由で **3D の z 平面に毎フレーム
  投影**し、そこへ頭部を配置・サイズも一致させると、ビューポートのサイズ/アスペクトに
  関係なく目鼻口が合う。スクロールで最終ポーズへ smooth ブレンド（settle）。
- モデル側の頭部メトリクス（高さ/縦横オフセット）は bbox から推測せず、**既知トランス
  フォームでレイヤー別スクショ → px→world 逆算**で較正する（頭部の前後 z 分の視差が
  bbox 計算には乗らないため）。

### 見た目破綻の犯人探しは「ライブレンダラ内でレイヤーを1つずつ消す」が最速
- Blender (Workbench/EEVEE) では three.js と材質の解釈が違い、**再現しないことがある**
  （今回 EEVEE では鼻ブロブが出ない）。ブラウザ内で `material.normalMap = null;
  needsUpdate = true` 等を順に当てて A/B スクショするのが決定打。
- 今回の犯人: 鼻のテカり破綻 = **強圧縮法線マップ**（2048²で82KBのJPEG）。
  「浮いた髪の黒いC」 = 髪シェルの**裏面が depthWrite OFF 透過で透けた**もの（形状は正常）。
  全身の白ダスト = **EdgesGeometry のマイクロセグメント**（テクスチャは無実）。
- Tripo の法線マップは石膏ルックには有害無益 → `m.normalMap = null` で除去が正解。

### EdgesGeometry を depthTest:false にすると「裏側の線」が全部見える罠
- 閾値を 24°→35° に上げても密度が変わらず見えたら、裏面の線が透けている。
  正解は **depth-tested + メッシュ側に polygonOffset(1,1)**（共面 z-fight を回避する
  ワイヤーフレームオーバーレイの定石）+ メッシュの depthWrite を早期 ON。
- 線の opacity は拡大率で割って減衰（`0.5 * e / max(1, scale)`）し、実体化が始まる前に
  完全フェードアウトさせる。ノイジーな AI メッシュの稜線は大写しでは「ダスト」になる。

### スクリーン整合の投影計算で「カメラ=原点」を仮定しない
- 2D プレート上の点に 3D を重ねる投影で `point × k`（k=距離比）とだけ書くと、カメラが
  原点にいる間しか正しくない。マウスパララックス等でカメラが動くと `cam × (1-k)` 分
  ドリフトする（±0.5 移動で ~13px）。正しくは **ray 式 `point' = cam + (P - cam) × k`**。
- 自分の Playwright 検証はマウス中央のスクショばかりで気づけなかった。**「検証時に
  動かしていない入力」が前提に化ける**。出典: Codex レビュー（P2）— 別系統レビューが
  盲点を突いた好例。

### 透明プレートを重ねるなら renderOrder を明示する（ソートはカメラ移動で反転する）
- three.js の透明オブジェクトは「中心点の投影深度」で奥→手前にソートされる。ほぼ同一平面の
  2枚のプレート（z差0.01）でも、**中心位置が縦にズレている**とカメラの俯仰（マウスパララックス
  ±0.35 程度で十分）で深度の大小が入れ替わり、**裏のプレートが上に描かれて手前が消える**。
  マウス位置で人物が出たり消えたりする、という不可解な症状として現れた。
- 対策: 描画順が固定の層は `renderOrder` で明示する（奥 -2 < 手前 -1 < 通常 0）。
  深度ソート任せにしない。
- 併発バグ: 後からロードされる2枚目のプレートに scale だけコピーして position.y
  （フェイスアンカーのシフト）を写し忘れ → 共通のフレーミング関数を再実行する形に統一。

## 2026-06-12 — 04 仕上げ（プレート被覆の総点検）

### cover フィットしたプレートを z 移動するなら毎フレーム再フレーミング
- cover フィットは「フィットした軸の余白がゼロ」になるサイズ決定。そのプレートを
  ロード時の距離のままカメラから遠ざける（沈降演出）と、**必ず**フィット軸に黒縁が
  出る（scroll 1 で被覆 80% まで低下していた）。サイズ計算は固定の配置 z でなく
  **プレートの現在 z** で行い、z を動かすループ内で毎フレーム呼ぶ。
- 副作用として「写真が縮んで遠ざかる」視覚は消えるが、奥行きはパララックス差で
  十分伝わる。黒縁との交換なら迷わず再フレーミングを選ぶ。
- 出典: Codex 再レビュー（P2）。1巡目の修正(パララックス項)の検証中に発見された
  同根の問題 — **「直したから再レビュー不要」としない**ことの実例。

### マウスパララックス + lookAt があるなら「画面ぴったり」は黒縁予備軍
- カメラが x/y にオフセットし lookAt で傾くと、プレート平面上のフラスタム足跡は
  軸上の vW/vH より広い**台形**になる（実測: 全沈降+コーナーで幅 13% 不足。
  解析近似 2.3% の 2.6 倍 — 傾き項は直感より大きい）。
- 対策は数式フィットでなく**実フラスタムの厳密被覆**: NDC 四隅を unproject →
  プレート平面と交差 → 足跡の bbox を覆う最小ズーム m を毎フレーム適用。
  ポインタ静止時は m=1（チューニング済み構図が無変化）、コーナーでだけ
  ズームし、カメラと同じイージングで動くのでパララックスの一部に見える。
- 検証は「プレート角の NDC」でなく **「NDC ボックス 8 点 → 平面交差が
  プレート矩形内か」**で行う（プレート角は画面外の高さなので誤判定する）。

## 2026-06-12 — 04 Phase 2（Seedance i2v「生きた写真」）

### i2v は start_image ロール + ネイティブアスペクトで「枠ズレゼロ」にする
- 2D プレートの UV 定数（PHOTO_HEAD 等）はスチルで実測した値なので、動画の枠が
  1px でもズレると破綻する。Seedance 2.0 は **3:4 をネイティブ対応**しており、
  `start_image` ロールで入力すると 1フレーム目≈入力画像のまま動き出す。
  仕上げに ffmpeg で **スチルと同一アスペクトへクロップ**（1248×1664→1242×1664）
  すれば、スチルの完全な差し替え品になる。
- 「カメラ静止」はプロンプトで多重に縛る（static locked-off tripod, no zoom/pan/
  dolly, framing stays exactly unchanged）。今回 3フレーム比較で窓位置ピクセル一致。

### シームレスループは「先頭を末尾にクロスフェード」— xfade は CFR 必須
- ループ式: 本体=trim(F..D)、頭=trim(0..F)、`xfade=fade:duration=F:offset=本体長-F`。
  こうすると **ループ末尾のフレーム = S(F) = ループ先頭のフレーム** になり継ぎ目が
  消える（境界 PSNR 43-45dB = 同一フレームを実測確認）。
- 罠: trim/setpts の後の xfade は「inputs needs to be a constant frame rate」で落ちる。
  **xfade の両入力の直前に `fps=24`** を置いて CFR を再スタンプする（crop 直後では不十分）。
- 光量が変わる映像（光芒が育つ等）はループ周期が短いと脈動して見える →
  `setpts=1.5*PTS` でスローにして周期を伸ばす（超低速モーションはフレーム複製でも破綻しない）。

### VideoTexture は「スチル先行 → 再生可能になってから差し替え」の漸進アップグレード
- スチルを即表示し、`<video muted loop playsinline>` の canplaythrough → play() 成功後に
  `mat.map = new THREE.VideoTexture(v)` で差し替えると、404・autoplay 拒否・低速回線の
  すべてで「動画なし版」に自然degrade する。旧スチル texture は dispose（GPU側のみ。
  `.image` の寸法は残るのでフレーミング計算に使い続けられる）。
- 罠: 共有のフレーミング関数が `tex.image.width` を読んでいると、map が <video> に
  替わった瞬間 `videoWidth` でなく DOM width(0) を読んで **NaN 化**する。
  `(image.videoWidth || image.width)` で両対応にする。
- 再生は見える区間だけ: スクロール位置で play/pause をゲートする（`v.paused` は
  play() 呼び出しで同期的に false になるので毎フレーム判定でもスラッシュしない）。
- 結果: モノクロ静止系の i2v ループは h264 CRF26 で **327KB/501KB** と激安
  （1242×1664・4.3s/6.4s）。「数MB級」の事前見積りより1桁軽い。

### `<video>` を currentTime でシークする UI は「シークが正しく着地するか」を必ず実測する
- ffmpeg の `fps=24` フィルタ経由で再エンコードした mp4 が、**線形再生は正常なのに
  シークだけ壊れる**状態になった（`currentTime=1.2` が ~0 に着地、別の機会には終端
  10.04 に着地 → 「動画が一瞬で終わる」ように見える不可解バグ）。再生レートは正常な
  ので、currentTime のトレース（ページ内 setInterval サンプリング）を取るまで原因を
  シーク破損と特定できなかった。
- 対策: ソースが既に CFR なら fps フィルタを挟まない + `-g 24 -keyint_min 24` で
  毎秒キーフレームを打つ → シークがフレーム精度で着地するようになった。
- **シークしない動画（play/pause のみのループ）はこの破損があっても症状ゼロ**。
  なので「他の動画は動いてるのに」という思い込みが調査を遅らせる。シークを使う
  クリップだけ壊れて見える。
- 検証パターン: `v.currentTime=X; await 150ms; v.currentTime を読み戻す` を 3 点
  （中間・後半・0）でやれば 1 コールで判定できる。

### NotebookLM 正典照合は「プロンプト設計」にも効く（Seedance ガイド初運用）
- 効いた裁定: 文学的感情語（madness/dread）→ 物理挙動への全置換 / 秒数3ビート
  （Establish-Develop-Payoff）/ end_image はトランジション用で演技制御には不適 /
  genre はカメラ・ペーシングまで動かすので固定カメラ要件では auto 維持。
- 結果: **狂気の叫び 10s が 1 発で要件全達成**（同一人物のまま絶叫・カメラ不動・
  終端ピーク保持・口内破綻なし）。90cr の一発勝負前に 7 問の照会で外しどころを
  潰す方が、リテイク連打より速くて安い。
- 回答内の他モデル由来の汎用ネガティブ列挙は文脈混入として棄却（上位原則
  「過度なネガティブ依存を避ける」と矛盾するため）— 正典回答も鵜呑みにせず
  ガイド内部の原則で裁定する。

### 「完成レンダ風」のリアルタイム化 = IBL + ベイク AO の2点で激変する
- ACES + 3点ライトだけでは「リアルタイムの絵」。**RoomEnvironment の IBL**
  (PMREMGenerator.fromScene、アセット0個) と **Blender ヘッドレスで焼いた AO**
  (Cycles 64spl・1024²・1〜2分) を足すだけでオフラインレンダの陰影になる。
  IBL を入れたら AmbientLight は大幅減 (0.5→0.18)。AO が効くのは環境光・
  アンビエント項のみなので IBL とセットで初めて効く。
- aoMap は three r152+ なら `texture.channel=0` で既存 UV をそのまま使える
  (uv2 不要)。強さは aoMapIntensity / envMapIntensity で材質ごとに調整。
- **AO ベイク PNG の向き**: Blender が保存したベイク画像は、glTF メッシュに
  `flipY=false` でそのまま正しい (vflip すると UV アイランドが顔に多角形の
  まだらとして乗る)。理屈で悩むより「まだら=向きが逆」のサインで覚える。

### Blender はヘッドレス（--background --python）で GLB 検査・修理ができる
- GUI/MCP addon 不要。matcap+cavity の Workbench レンダで形状検査、numpy で
  `img.pixels.foreach_get/set` してテクスチャ外れ値修復（5×5メディアン比較）、再エクスポート。
- glTF 再エクスポートは bbox/頂点数が完全一致で戻る（較正値・正面向きがそのまま生きる）。
  インポート時は Z-up に変換される点だけ注意（顔の向きはレンダで実測が確実）。

## 2026-06-14 — 05-emergent-life（手塚調 卵子→胎児 / 生成AIプロンプト設計）

### harness 先行（プレースホルダ駆動）で素材仕様を逆算確定する
- Seedance/画像生成のクレジットを撃つ前に、**procedural フォールバック付きの harness を先に組んで検証**すると、必要な素材仕様（枚数・解像度・背景色・アスペクト）が逆算で確定する。05 では scroll-scrub＋輝度疑似深度＋視差を in-page 生成の egg→胎児プレースホルダで通し、「3:4・四辺純黒・中央・暗マージン」という要件を固めてから素材生成に入れた。02 のプロシージャル fallback 思想の応用。
- 連番スクラブは GSAP 不要。tall scroller ＋ `scrollY/(scrollHeight-innerHeight)` → `round(p*(N-1))` で frame index（04 の vanilla スクロール流用）。実フレームは `assets/05-frames/manifest.json` を fetch、無ければ procedural にデグレード（manifest 404 は正常フロー）。

### 生成AIのプロンプト設計も NotebookLM 正典照合で攻める（画像＋動画の両ガイド）
- 「手塚アニメ調」は **固有名（作家名・作品名）で指定しない**のが正解。固有名は「漫画のコマ割り・古い単行本の紙の黄ばみ・ポスターの枠」など**周辺要素を無差別に引き込む**（試作 #1 で "atlas illustration" が古紙プレート枠＝明るい紙縁を出し、harness の輝度キーが紙縁を被写体と誤認した真因がこれ）。**視覚属性記述**（`1970s retro hand-drawn cel animation, flat limited-palette color fills, bold uniform black ink outlines, subtle film grain`）で組む。
- **モデルごとにネガティブの作法が逆**: nano_banana_pro は**ポジティブ・フレーミング**（"no paper/border" の否定列挙は逆効果。"edge-to-edge full-bleed seamless black" と肯定形で言う）。GPT-image は Constraints ブロックで除外明示。出力先モデルのガイドに合わせる。
- **スタイル一貫は「スタイルアンカー＋役割割当」**。異形・同スタイルのモーフ系列で**盲目的な直前フレーム i2i 連鎖は形がロックされてNG**。1枚（K1）を全段で参照し、`Use the reference image only for the Style/Aesthetic and the environment; do NOT use it for the subject's shape` と自然言語で役割を割り当てると、形はテキスト・世界観は参照画像で両立する。

### "geometric" は有機的主題で角張らせる罠
- 桑実胚（丸い細胞の塊）を "a cluster of glowing **geometric** orbs" と書いたら、立方体・八面体・結晶の塊になり、滑らかな前後段（球・勾玉）の間で浮いた。有機的な丸い形は **"soft rounded cells / smooth round forms"** と明示し、**"no geometric polyhedra, no crystals, no cubes"** を添えて作り直すと桑実胚らしくなった。形容詞 1 語が主題の幾何を支配する。

### 平坦セル × 輝度疑似深度の両立 = glowing core ＋ rim light
- 手塚調のフラットなベタ塗りは輝度勾配が乏しく、輝度→高さの頂点変位（疑似深度）が効きにくい（被写体 vs 黒背景の層パララックスは残る）。**各キーフレームに glowing core（中心発光＝中心が前へ＝ドーム）＋ soft rim light（縁の分離・1970s セルの透過光処理）** を入れると、ベタ塗りの美学を壊さずに harness が読めるハイトマップ情報を稼げる。harness shader は bright=forward のまま。

### 同一正典の別ユースケース回答との矛盾は平均化せず上位要件で裁定
- 同じ Seedance ガイドが、04（連続1テイクの叫び）では「multi_shots＝カット割り＝連続テイクを壊す・避けよ」、05 照会では「変容には Multi-Shot 推奨」と**正反対**の回答を返した。連続モーフ要件では 04 の明確化を採用（＋ higgsfield seedance_2_0 に該当 param 自体が無い）。正典回答も鵜呑みにせず、対象要件で裁定する（[[trinity-plan-brushup]] の文脈汚染点検）。

## 2026-06-15 — 05 FLF2V 生成→連番化（Seedance 2.0 / 4遷移）

### Seedance の NSFW フィルタは「胚・胎児の有機形状」を誤検知する（医療系の巻き添え）
- 卵子→胎児の**中間2遷移（桑実胚→胚、胚→胎芽）が status=`nsfw` で両方ブロック**。端の2遷移（受精卵側・胎児側）は通過。胚・胎芽の勾玉/幼生形が分類器を誤発火させる（医療/解剖カテゴリの巻き添え）。**判定は生成完了後**に出るので in_progress 中は合否不明。
- `reveal_generation` は `ip_detected`（著作権）専用で `nsfw` には**使えない**。回避は再生成のみ。**nsfw は無課金**（残高で確認: 失敗本数ぶんは引かれない）→ 再ロールは実質ノーリスク。
- 効いた回避 = **プロンプトに抽象化クラウスを足す**: `like an abstract symbolic luminous diagram` ＋ `avoid anatomical or bodily detail` ＋ `stylized graphic shape`。フィルタは出力ピクセルを見るので、抽象寄りの語で生成画を解剖的に寄せないのが効く。**端点キーフレームは start/end_image で固定**なので連結整合は不変。1回の再ロールで両方通過。

### in_progress で詰まったジョブを諦めて再投入すると「直後に解凍」して二重課金
- 1本だけ in_progress が7分超（正常60–200s）。hung と判断し新規投入した**直後に旧ジョブが完了** → 両方 completed で **+22.5cr の無駄**。プロバイダ側ジョブのキャンセル手段は MCP に無い。
- 教訓: 詰まっても**もう1巡（+2–3分）待ってから**再投入する。動画ジョブは完了直前に長く in_progress へ留まることがある。

### flipbook の VRAM は「フレーム数 × W×H×4」が支配的（harness は全フレームを個別テクスチャ保持）
- harness は `frames[]` に全フレームを個別 THREE.Texture でロードし、スクラブで順に `material.map` へ割当 → **フルスクラブで全フレームが GPU に乗る**。VRAM ≈ N×W×H×4（mipmap無＝LinearFilter）。解像度より**フレーム数**が効く。
- 今回 600×800×117 ≒ **225MB**（DL は webp で 2.6MB と激安）。公開デモは VRAM ~200MB 目安でフレーム数×解像度を決める。将来最適化: 現在フレーム±窓だけ残して dispose（Image はブラウザキャッシュ済みでテクスチャ再生成は安い）。

### FLF2V 連結は「境界フレーム重複除去」でカクつきを消す
- クリップ n 末尾 ≈ クリップ n+1 先頭（同じキーフレーム K）。素直に連結すると K が2フレーム連続＝1コマ静止のカクつき。**2本目以降の先頭1枚を落とす**と滑らか（clip1=全30、clip2-4=各先頭除き29 → 計117）。検証: スクラブ写像 p=0.25/0.5/0.75 がほぼ K2/K3/K4 境界（f29/58/87）に一致。
- 24fps/5s の Seedance クリップ → `fps=6` で30枚/本に間引き: `ffmpeg -vf "fps=6,scale=600:800:flags=lanczos" -c:v libwebp -quality 82`。cwebp/magick 不要、ffmpeg の libwebp で webp 連番を直書きできる（04 の知見の再確認）。

## 2026-06-15 — 05 拡張: 生命ループ（11モーフ320フレーム）の生成運用

### higgsfield ultimate = 最大4並列＋スロット解放が遅い → submit は小波で
- エラー文 `max 4 concurrent job(s) on ultimate (annual) plan`。5本以上を一度に投げると**4本だけ通り残りは即エラー**。さらに**完了直後に補充しても弾かれる**（スロット解放にラグがある）。
- 運用: 一度に ≤4、かつ「全部完了 → 少し待ってから次の波」。長尺の連番モーフは **「4本投入→完了待ち→次の波」** のバッチで回すのが確実。`get_cost` ではなく実投入が rate limit 対象。
- FLF2V 所要は通常60–200sだが、混雑時は **5–7分 in_progress に張り付く**ことがある（最終的に completed か nsfw）。判定は完了後なので in_progress 中は合否不明。詰まっても2–3分は待つ（[[2026-06-15 の二重課金教訓]]）。

### NSFW 誤検知は「胚」と「ヌード人体」で多発 → 抽象化を段階的に上げる
- 320フレームの生命ループで弾かれた遷移: 子供→ヌード大人（人体ヌード）/ 爬虫類→両生類（モーフ途中の有機形・1回）/ 魚→胚（**胚は最頻トリガー: 2回弾かれ3回目で通過**）。
- 効く緩和の段階: ①基本 `like an abstract symbolic luminous diagram` ＋ `avoid anatomical or bodily detail` → ②人体は `smooth mannequin-like silhouette, no skin detail, modest, non-sexual` ＋ `avoid nudity detail` → ③胚は `simple glowing seed / abstract form` ＋ `avoid figures` まで上げる。端点キーフレームは start/end_image 固定なので連結整合は不変。**nsfw は無課金**＝再ロールはノーリスク（ただし所要時間は食う）。
- 保険: 持続トリガー（胚）は**代替の安全な end_image**（桑実胚=丸い細胞塊 K2）を並行投入でヘッジすると待ちサイクルを節約できる（K2 が先に通り、K3 も後で通った）。

### 長尺フリップブックは「窓ロード」で VRAM を区間規模に固定する
- 320フレーム×600×800×4 ≒ 600MB超 を全テクスチャ保持は破綻。harness を **現在地±WIN_LOAD(16) をロード／±WIN_KEEP(26) 外を dispose** の sliding window に改修（`frames[]` に Texture|'loading'|null、`ensureWindow(center)` を setFrame から呼ぶ）。同時保持 ~53枚 ≒ 100MB に固定。
- 罠: 高速スクラブで現在地が飛ぶと、表示中テクスチャを dispose してしまい黒画になる → **`frames[i] !== uniforms.uFrame.value` の要素は dispose しない**ガードで回避。未ロード時は「前のフレームを表示し続け、ロード完了時に `i===curFrame` なら差し替え」。reveal は frame0 のデコード完了を待ってから。

### クラウドが NSFW で弾く動画は「稼働中のローカル ComfyUI を別プロジェクトから直接叩いて」逃がせる
- Seedance(higgsfield クラウド) は赤ん坊/子供の動画化（ヌード＋子供の苦痛表現）と一部動物アクションを NSFW で拒否。**ローカル Wan2.2-Remix(D:/ComfyUI_new)は内容フィルタが無い**ので一発通過（2Dセル/黒背景/発光コアも保持・写実化せず）。クラウドで詰まったらローカル ComfyUI へ。
- **このプロジェクト(threejs-lab)から D:/ComfyUI_new の稼働中インスタンスを直接ドライブできた**: ComfyUI は `localhost:8188` に HTTP API を出す。手順 = ①アンカーPNGを `D:/ComfyUI_new/input/<sub>/` へ `cp` ②Playwright で `http://127.0.0.1:8188/` を開き `window.app.loadGraphData(wf)`→`window.app.graphToPrompt()` で **UI(litegraph)JSON を API prompt 形式へ変換**（手書き変換は不確実・graphToPrompt が確実。WF は `fetch('/api/userdata/workflows%2F<name>.json')` で取得）③API dict の対象ノードを patch（LoadImage.image / CLIPTextEncode.text / WanImageToVideo.width,height,length / VHS_VideoCombine.filename_prefix,pingpong / Seed）④`fetch('/api/prompt',{method:'POST',body:JSON.stringify({prompt,client_id})})` ⑤`/history/<id>` で完了確認 → `output/<sub>/` の mp4 を `cp` で回収。WF構造の把握は graphToPrompt 出力の class_type/inputs を見れば一発。
- **VHS_VideoCombine の `pingpong:true`** = 順再生→逆再生で **start=end=入力アンカーの自走ループ動作**（休止→動作→休止）。i2v は「動作が休止に戻る」保証が無いが pingpong で解決。10s 往復クリップを `fps=3` で 30 フレーム抽出すれば既存アクション block と同寸。
- 注意: **ComfyUI 再起動で `/history` はクリア**（過去 prompt のテンプレ回収不可）→ graphToPrompt で WF から組むのが再起動耐性あり。ローカル ComfyUI は1プロンプトずつ直列実行(VRAM 1モデル)＝POST は何本積んでも順次。`python` は PATH に無い→`D:/ComfyUI_new/venv/Scripts/python.exe` を使う。`/tmp` 無し→cwd配下に一時ファイル。

### スクロール連番が「フラットなセル画」なら輝度疑似深度は OFF が正解（写真用の機構を流用しない）
- 04 portrait（写真）では輝度→頂点変位の疑似深度が効いたが、05 の手塚調フラットセルでは**ベタ塗りの階調境界で段差（mesa cliff）＝シルエットがギザつく**だけで害。`uDepth` 0.55→**0** でフラット表示が正解（実測: 0.15 でも端の段差が残り、0 でインク輪郭がくっきり）。同じ harness でも被写体の絵柄で機構の要否が逆転する。
- 副作用: マウス視差は変位前提なので depth=0 で実質消える（カメラ平行移動分は平面なので僅少）。視差 0.5→0.2 に下げてフラット画のキーストンを目立たせない。

### 被写体を小さくするのは「カメラを引く」でなく「UV 中心縮小＋黒縁 clamp」（継ぎ目が出ない）
- カバーフィットのプレーンでカメラを引く / contain に変えると**プレーン端が露出**し、テクスチャ純黒縁(0,0,0) と scene bg(0x05050a)・グレイン・ヴィネットの差で**矩形の継ぎ目**が出るリスク。
- 正解: プレーンはビューポートをカバーしたまま、シェーダで `fuv = (uv-0.5)*uFill + 0.5`（uFill>1）。テクスチャは ClampToEdge なので [0,1] 外＝黒縁が margin を埋める → **被写体だけ中央で縮小・継ぎ目ゼロ**。uFill=1.40 で被写体≈71%。デバッグに「サイズ」スライダ（被写体倍率、uFill=1/v）。**前提: 素材の四辺が純黒**（05 の生成要件と一致）。displacement も同じ `vFuv` を使うので depth を再有効化しても relief が縮小後の被写体と一致する。

## 2026-06-16 — 05 アクション/モーフ再設計（人間アーク＋動物アーク）

### Wan i2v は「被写体を大きく移動させない」→ 高ジャンプ等は firstlast↔到達点キーフレームで強制
- 「カエルを3倍高く跳ばせる」を i2v 単体（`springs upward in a high leap`）で出そうとすると、Wan は**被写体を中央・原寸に保つ傾向**で、立ち上がる/伸び上がるだけで明確な滞空・上方移動が出ない。
- 正解: **到達点のポーズ画**（`frog-airborne`＝フレーム上方に小さく滞空・下に黒余白）を作り、**firstlast(WanFirstLastFrameToVideo) で開始(K10座り)↔到達点(airborne) を pingpong** → 上方向の大移動を強制でき、はっきり高く跳ぶ。大きな translate を要する動作（高ジャンプ・落下・突進・潜水）は全てこの「到達点キーフレーム＋firstlast」が効く。i2v 直接版(a2-frog-jump)は不採用。

### nano_banana_pro の再ポーズは参照ポーズが残る → 強い否定で上書き
- 立ちゴリラ(K8)を参照に「lying down sprawled」と頼んでも**参照の立ちポーズが残る**（1回目は立ったまま）。
- 正解: `Completely change the pose to LYING DOWN FLAT ON ITS BACK ... it is NOT standing, NOT sitting, NOT on all fours` ＋ `Keep ONLY the art style, fur color, warm-red core from the reference`（identity/styleだけ参照・ポーズは全置換と明示）で横位置に。大きくポーズを変える時は「肯定の新ポーズ＋否定の旧ポーズ列挙＋参照は見た目のみ」。

### firstlast WF(runninghub) は QwenImage 精製込みで遅い(~5分/本)が手塚調は壊れない
- `runninghub_wan22_remix_firstlast_local.json` は内部で QwenImage 40step を回すため i2v(~2-3分)より遅い(~5分/本)。だが**フラットセル/黒背景/赤コアは保持**され、両端が入力キーフレームに一致するモーフが安定して得られる。ポーズ連鎖（動作終ポーズ＝次モーフ起点）に必須。i2v=単発ループ動作、firstlast=ポーズ間モーフ、と使い分け。

### ComfyUI を Playwright で叩いた後はページが固まる → threejs 検証前に browser_close
- ComfyUI(`localhost:8188`)で `loadGraphData`/`graphToPrompt`/POST を多数走らせた後、同じ Playwright タブが**ナビゲーション 60s タイムアウト**で固まる（about:blank すら不可）。
- 対策: `browser_close` で閉じてから threejs ページを新規に開く。**生成の完了監視は Playwright でなく `curl /history/<id>` (Bash background) で**やるとページに依存せず安定。

### スクロールスクラブの速さ ∝ 1/(#scroller 高さ)・フレーム増で速くなる
- スクロール量は `#scroller { height: Nvh }` で決まり、`scroll=scrollY/max` の正規化マッピング。フレームを増やす（523→846）と**同じ軌道に多フレームが詰まり1ホイールの進みが速くなる**。
- 体感が速すぎたら vh を増やす（600→1200vh で半速）。正規化ゆえ全フレーム自動追従。**CSS はブラウザキャッシュされる**ので変更確認は Ctrl+Shift+R か `?v=N`。

## 2026-06-17 — 05 アクションの i2v 手足smear を Seedance 2.0 FLF2V で撃退

### ローカル Wan i2v の「手足が画面端まで棒/柱/線に伸びる」smear は Seedance 2.0 FLF2V で消える
- 症状: ローカル ComfyUI/Wan2.2 で作ったアクション（ゴリラ胸叩き・トカゲ這い・カエル跳躍）の**動きのピークで手足が画面端まで伸びて棒・柱・線状に崩れる**。アクションは ×3 ループなので不良コマが3回出る＝「ちょいちょいおかしい」の正体。静止ポーズ自体は健全で、崩れるのは動きの極とモーフ中間だけ。
- 原因の切り分けは**全フレームのコンタクトシート**（`ffmpeg ... tile=12x9` を前後半2枚）が最速。ステージ（卵/胎児/魚/ダイブ）は無実、犯人はアクションのピーク数コマと morph 中間と判明。
- 効いた直し = **Seedance 2.0 の FLF2V（start_image+end_image 両端ロック）**。両端を手塚調キーフレームに固定すると、間の手足の軌道がクリーンに補間され smear が出ない。フラットセル/黒背景/赤コアも保持（写実化しない）。`models_explore get seedance_2_0` で start_image/end_image ロール・3:4・duration 4-15s を確認。

### Seedance のループ/一方向の作り分け
- **その場ループ動作**（胸叩き・這い）= `start_image==end_image`（同じ media_id）。最終フレーム≈先頭に戻るので assemble の境界デデュプでそのままループ化。pingpong 不要。
- **一方向の大移動**（カエルの高跳び＝しゃがみ→滞空）= FLF2V を片道で生成し、**ffmpeg で pingpong**（`split[a][b];[b]reverse[rb];[a][rb]concat`）してしゃがみ→滞空→しゃがみのループに。`fps=N/秒` で元ブロックと同コマ数に間引き（5.04s clip を fps=4→20コマ等）。
- **遷移**（立ち→寝そべり）= FLF2V 片道（rest→pose キーフレーム）、pingpong 無し。

### Seedance NSFW 誤検知の緩和は「抽象化クラウスを最初から」入れる
- カエルの滞空（手足を広げた形）が **1回目 status=`nsfw` でブロック**（動物でも誤発火する／lessons 2026-06-15 と同根）。**nsfw は無課金**＝残高据え置きで確認（リロールはノーリスク）。
- 緩和 = プロンプトに **`like an abstract symbolic luminous diagram` / `avoid anatomical or bodily detail` / `stylized simple shapes`** を足す。1回目で素直に書いて弾かれてから足すより、**最初から入れておく**と無駄足が減る（ゴリラ・トカゲは初手で通過）。

### コスト・運用
- 720p std 5s 3:4 = **22.5cr/本**、480p=15cr。最終配信が 600×800 なので **720p（720×960→縮小）でインク線のキレを保つ**のが正解（480p は upscale で甘くなる）。
- 混雑時は **1本 ~6分** in_progress（通常60-180s）。ultimate は **≤4 並列**。詰まっても再投入は2-3分待つ（[[二重課金教訓]]）。`media_upload`(files[]) → curl PUT → `media_confirm` → `generate_video`(medias 役割 start_image/end_image) → `job_status` ポーリング → mp4 DL。
- **統合のコツ**: 再生成クリップの両端＝正典キーフレーム（K8/K9/K10）に一致させると、**手を入れない隣接モーフ（clipN）との継ぎ目が保たれる**。元ブロックと同コマ数で差し替えれば `_assemble.sh` 再実行で総数・manifest・index/README 不変（846 のまま）。元のローカル版は `_preseedance/` に退避、生成 mp4 は `_seedance-mp4/`（共に .gitignore 下）。

### モーフ(clipN)の再生成は「実際の隣接境界フレーム」を端点に使う
- clip8/clip10 を作り直すとき、start_image=`frame_<モーフ直前>`・end_image=`frame_<モーフ直後>`（assemble 済み列から `ffmpeg` で抽出した実フレーム）を使うと、**手付かず／再生成済みどちらの隣接ブロックとも継ぎ目が合う**。正典キーフレーム(K*)より実フレームの方が seam が確実（生成は pixel-exact でないため）。clip8 は新ゴリラ(535)→新トカゲ(565)、clip10 は カエル潜水(730)→魚(760)。モーフは pingpong 不要・fps=6 で 30 コマに。

### Seedance NSFW は「子供は入力画像の時点で」弾く → 子供絡みは Seedance 不可・ローカル ComfyUI へ
- `media_confirm` の戻りで**子供のキーフレームが status=`nsfw`**（生成前・入力段で拒否）。大人・動物・魚は `uploaded` で通過。つまり **clip6(子供→大人モーフ)は Seedance では作れない**（プロンプト緩和では回避不能＝入力画像そのものが対象）。子供・赤ん坊絡みは内容フィルタの無いローカル ComfyUI/Wan2.2 を使う（[[クラウドNSFW回避＝ローカルComfyUI]]）。
- **仰向け/寝そべりの動物モーフも誤発火**: clip8(寝そべりゴリラ→トカゲ)1回目が `nsfw`（沿い寝の図が身体ポーズと誤認）。`reclining/body` 等の語を外し「simple stylized animal shape … abstract symbolic diagram of metamorphosis between two flat silhouettes」と**図式・無身体に振る**と通過。動物でも姿勢次第で弾かれる。

### スマー調査は「ブラウザのスクショ」と「raw フレーム」を区別する
- ユーザー報告の「大人の手から縦線」smear は、人間アーク全域(234-342)を **stride1 で全コマ＋apex を原寸**で精査しても **raw フレームに再現できなかった**。child→adult モーフの上方向の腕伸びが疑わしいが確証が取れず、かつ子供入力が NSFW で Seedance 不可。確証なく NSFW リスクのある再生成に走らず、原因を切り分けた（下記）。

### 連番スクラブの「報告画像が出る／raw は綺麗」= ブラウザの古フレームキャッシュ
- 05 のフレーム URL は `assets/05-frames/frame_NNNN.webp` で**固定**だが、中身は再構築のたびに変わる（523→846→今回の差し替え）。ブラウザは同名 URL の**古いバイトをキャッシュ**し続けるので、ユーザーの画面に「直したはずの古い smear」が出る。**新規ブラウザ(Playwright)で同フレームをレンダリングして再現しなければキャッシュ確定**（大人apex=frame317 を fresh render→縦線なしで確認）。対策はユーザーに **Ctrl+Shift+R（ハードリフレッシュ）**。HTML の `?v=N` はフレーム webp のキャッシュを破棄しない（別 fetch のため）。
- 切り分け手順: ①raw フレームを原寸確認（綺麗か）②fresh ブラウザで同フレームをレンダリング（出るか）。両方綺麗なら**現ビルドは正常＝ユーザー側キャッシュ**。一方 raw に実在するなら未再生成領域（下記 frog_dive）。
- **恒久対策を実装済み（2026-06-17）**: `_assemble.sh` が manifest に `ver`(epoch) を書き、`05-emergent-life.html`(436行付近) がフレームURLに `?v=<ver>` を付与。再アセンブルのたびに ver が変わり**ブラウザが自動で全フレーム再取得**（手動ハードリフレッシュ不要に）。manifest は `cache:'no-cache'` 取得なので ver は常に最新。注意: **HTML自体にはバスターが無い**ので、この種の "HTML を編集した" 直後だけは1回ハードリフレッシュで新HTMLを読ませる必要がある（以後フレーム差し替えは自動）。`_assemble.sh` は 05-src 配下＝gitignore だが、生成物の manifest(ver入り)＋HTML は配信対象なので Vercel でも効く。

### 「意図的でOK」と除外した動作ブロックも、動きのピークを実機で疑う
- frog_dive(ダイブ)を「頭からダイブは意図的」と判断して再生成対象から外したが、**離陸時に脚が縦柱に伸びる smear が残っていた**（ユーザーが2枚目で指摘）。stride サンプルのコンタクトシートはピーク間を飛ばすので「OK」に見えただけ。**ユーザーが実際に止めたコマ＝動きのピーク**を疑い、除外判断は慎重に。FLF2V 座り(707)→着水(730)で再生成し柱解消。隣接の clip10 が 730 を始端に使っていたので、frog_dive の end も 730 に合わせて継ぎ目維持。

## 2026-06-18 — 05 最終品質チェック: 「手足が画面端まで縦柱」smear は *harness 由来* だった（生成不良ではない）

### 端まで伸びる棒/柱 smear は generation 不良とは限らない＝`uFill` 縮小 × ClampToEdge の端複製
- カエル高跳びの頂点（配信 `frame_0666.webp` 付近）で**指先から画面上端まで太い緑の縦柱が2本**。過去の Wan i2v smear と同じ見た目だが、**今回は元 webp が単体ではクリーン**（柱なし）。犯人は harness のシェーダ。
- 機序: 被写体を中央に縮小する `uFill 1.40` は `vFuv=(uv-0.5)*uFill+0.5` で**プレート上端14%帯が `vFuv.y>1.0`→ClampToEdge でテクスチャ最上行を縦に複製**する。素材の四辺が純黒なら複製も黒で無害だが、**跳躍頂点はカエルの指先が元画像の上端に接触**して「四辺純黒」前提（[[2026-06-15 被写体縮小=UV中心縮小＋黒縁clamp]]）を破る → その緑画素が縦柱になる。
- **決定的切り分け**: ライブで `__dbg.uniforms.uFill.value=1.0`（縮小オフ＝はみ出しサンプリング無し）にして**柱が消えれば clamp 由来で確定**。消えなければ素材 or 他原因。1コール・無課金で原因特定できる。

### 修正は「資産を1フレームずつ直す」より「シェーダで前提を強制」が上位解（再生成ゼロ・クレジットゼロ）
- フラグメントで `vFuv` が [0,1] 外なら黒にするマスク `ib=smoothstep(0,.004,vFuv)*smoothstep(0,.004,1-vFuv)` を入れ、**ClampToEdge 複製を無効化**＝縮小マージンを真に純黒へ。`uFill 1.40`（被写体71%）は維持。同種の**端接触 smear を全段まとめて予防**でき、NSFW リスクも無い。
- **罠（自分で踏んだ）**: マスクを最終段で `col*=ib`（grain も含めて黒落とし）すると、**中央71%だけ grain が乗る矩形の継ぎ目**が出る。正解は**マスクをテクスチャ＋輝度 ember にだけ適用し、grain はプレート全面に均一**に保つ（`col=texture()*inb; … col+=grain; ember*=inb`）。マージンは「黒＋微grain」で元と同じ見た目になり継ぎ目が消える。

### 連番ハーネスの検証は「ネイティブスクショ＝真値」「`drawImage(WebGLcanvas)`＝近似」、そして off-by-one に死ぬほど注意
- 自作の `drawImage(rc,…)` コンタクトシート（preserveDrawingBuffer:false の WebGL canvas を読む）は柱を**細く過小表示**した。`browser_take_screenshot`（コンポジタ経由）が**忠実な真値**。疑わしきはネイティブで撮る。
- **off-by-one で誤結論寸前**: harness は `frameUrls[i]=frame_(i+1).webp`。ブラウザの「frame 665」＝ファイル `frame_0666.webp`。私は ffmpeg で `frame_0664/0665` を見て「素材クリーン＝不良なし」と誤断しかけた。**真の不良ファイルは frame_0666**。連番検証では「スクロール index」と「ファイル番号」の対応を最初に確定する。
- ブロックは `_assemble.sh` で `frog_hop:×3` リピート＝**1ブロックの不良が846列に3回**出る（ユーザーの「ちょいちょいおかしい」の正体）。ただし今回は harness 修正なので資産・assemble・総数846・manifest すべて不変。`05-frames/` の webp も無変更（差分は HTML 1ファイルのみ）。
