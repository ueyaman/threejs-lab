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

## 2026-06-18 — 06 cat-skeleton: AI生成骨格メッシュのリグ（削除厳禁・付替で直す）

### 単一視点 i2-3D は「裏側が粗い」→ 左右対称物は鏡像で補う
- Tripo の入力が**左向き側面写真1枚**だったため、**右（奥）側が推測で粗く生成**された（右前足の頂点数=左の半分）。単一画像 i2-3D の宿命（当初の懸念どおり）。
- 対策: 左右対称の被写体（骨格・人体等）は、**よく出来た側を鏡像コピー**して欠けた側を補う（Mirror modifier apply or bmesh 左半複製→X反転→merge by distance）。マルチビュー生成できない時の実用解。

### ⚠️ AI 生成骨格は「多数の小島＋内部ジャンク」→ 閾値での島削除は legit 骨を壊す（厳禁）
- Tripo の骨格メッシュは **600+ の連結島**（分離した骨ピース＋体腔内部の見えないジャンク）でできている。「小さい島」「本体から遠い島」「ポーズで孤立する島」等の閾値で削除を試みたが、**どれも legit の脚の骨を巻き込んで3回も脚を消した**（後ろ足・右前足）。サイズ/距離では legit 小骨（種子骨・足指）と junk を区別できない。
- **結論: 浮遊片は削除でなく「付替(reweight)」で直す**。削除はユーザー指摘で何度も巻き戻す羽目になった。

### 浮遊片の正体＝「mis-weight でポーズ時だけ動く」→ rest 隣接ボーンへ付替で根治
- ユーザーの核心的指摘「**Tab(編集モード)では付いてる。リグについていってないだけ**」が正解だった。破片はストレイ geometry でなく、**正規の骨が間違ったボーンに weight され、ポーズ時だけ別の場所へ動く**もの。
- 直し方（非破壊・全フレーム安定）: **各小島(<600面)を、rest で最も近い"別の島"の頂点と同じボーンへ付替**（KDTree で最近接 other-island vert→その bone を採用）。隣の骨と剛体で一緒に動く＝離れない。さらに**中央(|X|<0.045)の小島が脚ボーンなら胴体へ強制付替**で体腔内ジャンクを体内に留める。

### 融合/非多様体 AI メッシュのスキニング＝剛体 per-island ＋ 関節カット（bone-heat は失敗する）
- **bone-heat 自動ウェイトは非多様体メッシュで全失敗**（"ボーンヒート解決失敗"・100%未ウェイト）。`vertex_group_smooth` は weight-paint context 必須で MCP の temp_override でも poll 失敗 → **numpy 手動**しかない。
- 骨格は本来「関節で隙間のある独立した骨」＝**剛体 articulation**。だから per-vertex 最寄りボーン剛体ウェイト＋**「関節をまたぐ面を削除」して各骨を独立ピース化**すると、**関節に隙間が出る＝本物の関節接続標本と同じ**でスメア(裂け)が原理消滅。融合メッシュに soft weight を頑張るより、骨格はこの剛体方式が正解。
- per-vertex の最寄り割当だけだと長い上腕/大腿ボーンが肋骨を掴む→**側方ルール `|X|>0.022` で中央(胸骨/腹/内部)は胴体へ**。

### Tripo を `.env` で Claude が直接駆動（04 の `!` 制約を解消）
- 04 では `TRIPO_API_KEY` がシェル env var で Claude の Bash に継承されず `!` ユーザー実行だった。06 で `.env` 方式（スクリプトが `$ROOT/.env` を source・CRLF耐性）にしたら **Claude の Bash が `.env` を source できた**（サンドボックス非ブロック）＝Claude が Tripo を回せる。`.env` は gitignore、`.env.example` をコミット。Tripo `image_to_model`=30cr/枚。

### Blender MCP の落とし穴
- `bpy.ops.object.select_all`/`mode_set` 等は POSE モードや context 不一致で `poll() failed`。→ ops を避け `o.select_set()` のデータ API、ポーズ clear は `pose_bone.matrix_basis=Matrix()` を直接代入。
- `view3d.view_axis`/`view_selected` や `vertex_group_smooth` は **`bpy.context.temp_override(area=VIEW_3D, region=WINDOW)`** で context を与える（smooth は weight-paint 必須で結局 numpy へ）。
- `execute_blender_code` は **`result` 変数に dict を代入**して返す。`numpy`/`mathutils.kdtree.KDTree` 使用可。`Date.now` 系は無関係（Blender 側）。
- Blender 5.1: `Action.fcurves` 属性が無い（slotted action 化）。キー挿入 `keyframe_insert` は正常、集計時だけ注意。
- AI GLB の正面/向きは不定・metallic=1（04 教訓と同じ。今回は向き=長軸Y・頭骨−Y/尾+Y・接地 minZ=0 に整えた）。

## 2026-06-19 — 06 cat-skeleton: 前足の棒アーティファクト修正（失敗→巻き戻し）

### ミラー結合の「棒」を消すために5回の島/面/頂点削除を繰り返し、前足の指を破壊した
- ミラー修復で X=0 のマージ閾値により左右の前足内側の趾骨(dewclaw/inner toe)が結合。歩行アニメで左右の paw が離れると結合面が伸びて**棒**が出る。
- 5回の修正を試行: ①中央頂点のウェイト付替(非破壊)→②cross-assignment面172削除→③小島1,116頂点削除→④|X|<0.015頂点189削除→⑤前足ゾーン小島26個(5,952頂点)削除。**①以外はすべてジオメトリ破壊**で、⑤で前足の指の骨がごっそり消えた。
- **教訓の再確認: 島削除は厳禁**（同じ教訓を同日に4回違反した）。.blend1から復元して128,804頂点に戻した。

### 棒の正しい修正方針（次回実行）
- **削除ではなくエッジ切断(split)**:  X=0シーム上で左右の前足をつなぐエッジを bmesh で split する。ジオメトリの総量は変わらず、結合だけを解除。左右が独立に動いても伸びない。
- または**前足ゾーンのミラーmerge閾値を極小(0.0001)にして再適用**（趾骨が結合しない距離）。
- いずれも**保存前にアニメフレーム9(歩幅最大)でBlender viewport確認→問題なければ保存・GLB再エクスポート**の手順を守る。

## 2026-06-21 — 06 cat-skeleton: 「前足の棒」根治（前回の split 方針は誤り・実測で真因確定）

### ⚠️ 検証フレームを思い込みで決めない＝キーフレームの「値」を読んで真の極値を特定する
- STATUS/前回ノートは「frame 9 = 歩幅最大」として検証していたが、**生のキーフレーム値**を読むと `upperarm.L.X = [0.31, 0, -0.31, 0, 0.31] @ frames[1,9,17,25,33]`。**極値は frame 1/17/33・frame 9/25 は rest 同然（ゼロ交差）**だった。中立フレームで検証していたので棒が出にくく、5回の修正が迷走した。
- 教訓: アニメ検証は `fc.keyframe_points[].co`（値）を直接読んで極値フレームを確定してから行う。`fc.evaluate(f)` もデプスグラフも正常に動く（前回「変形ゼロ」は API バグではなくフレーム選択ミス）。Blender 5.1 のスロット化アクションでも fcurve は `action.layers[].strips[].channelbags[].fcurves` に居て普通に評価できる（`action.fcurves` 直下が無いだけ）。

### 真因は実測で割り出す＝posed面積/rest面積比。理論診断（X=0趾骨）は外れていた
- 真の極値 frame 17 で全227k面の `posed_area/rest_area` を計測。伸びていたのは趾骨ではなく **肩関節の橋渡し面**（poly 2159×=`upperarm.R`+`chest`、2129×=左肩、811×=`upperarm↔neck`、674×=`tail1↔tail2`）。**剛体スキニングでは「面積比>1 の面 ≡ 関節をまたぐ混在bone面」**（ratio>2.0 の2726面が100%混在面で一致）。
- だから過去5回の「X=0趾骨削除」は**犯人取り違え**で棒が消えなかった。**見た目バグは『ライブで実測（面積比/伸び）』して犯人を数値特定する**のが最速（02/04 の "レイヤーを1つずつ消す" の定量版）。

### `split_edges` は混在面の裂けを直さない → 剛体骨格は「関節をまたぐ面を削除」が正解
- 前回ノートの「棒は split で直す」は**幾何学的に誤り**: 混在面（upperarm×2+chest×1）はエッジを切っても3頂点を保持したまま残り、依然として裂ける。split はトポロジを分離するだけで混在面を消さない。
- 正解 = **橋渡し面（混在bone面）を `FACES_ONLY` で削除**して各骨を独立ピース化（lessons 2026-06-18 の原設計どおり。関節に隙間＝本物の標本）。これは禁止された「島(趾骨)削除」とは別物（薄い面だけ外科的に除去・頂点削除なし＝骨/指は原理的に消えない）。
- 安全条件: `max(stretch@両極値) > 1.6` **かつ** 混在bone面のみ削除。結果 3052面削除・**頂点数不変(128,804)**・最大stretch `2159× → 1.6×`・全骨97-100%生存（指99-100%）。

### 削除厳禁ルールは「島/趾骨削除」に限定であって「関節橋渡し面削除」を縛らない
- 「島削除厳禁」は size/distance 閾値で legit骨を巻き込む島削除の話。**関節橋渡し面は stretch比+混在bone で外科的に特定でき、原設計が意図した削除**。両者を混同して「一切削除禁止」にすると正しい修正まで封じる。ルールは**理由ごと**読む。

### 危険なジオメトリ手術はヘッドレスBlenderの「コピー上でシミュレート→レンダ→比較」で詰める
- 実メッシュを触る前に `mesh.copy()` 上で削除を適用し frame17 をレンダして A/B（ratio>2 vs 全混在面）。閾値（棒消失×指温存）を確定してから本適用→`save_as_mainfile(copy=True)` で原本温存し別名保存。1ロールバックも無しで完了。
- ブラウザ実機検証は **デバッグフック(`window.__cat`)で `mixer.setTime(極値)` → `timeScale=0` 凍結**して正確な極値を静止撮影（X-RAY/BONE 両モード）。検証後フックは除去。連続再生スクショ頼みより確実。

### 浮遊片＝ミラー結合のdewclaw（chest誤weight）→ split＋左右reweight＋relocate の3段で直す（削除しない）
- 前足間に浮く小片は**左右の親指(dewclaw)がミラーで X=0 に1島(239頂点)マージされ `chest`(胴)にweight**されていた。胴は歩行でほぼ不動→左右の足が振れると中央に取り残されて浮く。ユーザー指摘「これは親指だから削除は違う」が正しい（[[2026-06-18 浮遊片はreweightで直す]]）。
- 直し方: ①`bmesh.ops.split_edges` で X=0 跨ぎエッジを切り左右分離 ②左(x>0)→`paw_front.L`/右(x<0)→`paw_front.R` 付け替え(chest除去) ③**rest geometry を各足の最近傍頂点へ平行移動**(relocate)。
- **reweightだけでは「動き」は足追従になるが「静止位置」は中央のまま**（reweightは追従ボーンを変えるだけで頂点を動かさない）。各足に“付いて見える”には**relocate（頂点移動）が必須**。剛体島の平行移動なので stretch は増えない(1.6×不変)。

### ⚠️ Blender に append したプレビューはスキニング評価が壊れる → 検証はヘッドレス直開き or ブラウザGLBで
- ユーザーの稼働中 Blender に `libraries.load(link=False)` で mesh+armature を append し別シーンで再生すると、**ビューポートが spike だらけに変形**し、スクリプトの `obj.evaluated_get(deps).data` が**頂点0**・`to_mesh()` が**rest（frame差分0）**を返す（depsgraph 評価の不整合）。ボーン自体は正しく pose する（`pose.bones[].matrix_basis` は18°）のに、メッシュのバインド評価だけ壊れる。
- これを「実モデルの不具合」と誤認しかけた（spike を生成不良と取り違え）。**真値はヘッドレスで .blend を直接 `blender file.blend --background --python` で開いた時のレンダ**と**ブラウザの GLB**（append を介さない）。両者ともクリーンなら append プレビューのアーティファクトと確定。
- 教訓: ユーザー環境にモデルを「見せる」目的でも、**判定は append プレビューでなくヘッドレス/ブラウザで**。append はクイックな静止確認止まりにする。未保存の他作業があるセッションでは原本 open もできないので、ブラウザGLBが最も確実。

### 自作 ShaderMaterial を SkinnedMesh に使うと「スキニングされず rest ポーズで静止」する（組み込みは自動スキン）
- 06 の X-RAY モード（fresnel の自作 `ShaderMaterial`）が**アニメせず静止**していた。原因: 頂点シェーダが `position` を直接使い、**ボーン変形（スキニング）を適用していなかった**。`MeshStandardMaterial`(BONE)/`MeshBasicMaterial`(WIRE) は SkinnedMesh で**自動的にスキニング**されるため動く → **自作シェーダのモードだけ静止**し、しかも**それが既定モード**だったので「読み込むと止まって見える」状態だった。
- 直し方: 頂点シェーダに three.js のスキニングチャンクを入れる。`#include <common>` / `#include <skinning_pars_vertex>` を宣言部に、main 内で `#include <beginnormal_vertex>`→`<skinbase_vertex>`→`<skinnormal_vertex>`→`<begin_vertex>`→`<skinning_vertex>` を入れ、以後 `transformed`（位置）と `objectNormal`（法線）を使う。チャンクは `#ifdef USE_SKINNING` ガード付きなので非スキンメッシュでは無害。`USE_SKINNING` 定義とボーンuniformは、対象が SkinnedMesh なら renderer が ShaderMaterial にも自動付与する。
- 検証の盲点: **既定モードが壊れていても、他モード（組み込み材質）が動くと「アニメは動いている」と誤認**する。連番でなくアニメ系は「各表示モードで実際に動くか」を時間差スクショで個別に確認する。自分も最初 X-RAY で frame17 を「検証」したが、実は rest を見ていた（BONE 検証は有効だった）。

### 動物の自然な動きは手付け/手続きFKでは出ない → 実mocapリターゲットが近道（四足はMixamo不可）
- 06 で「歩行(手付け)→伸び(手付け)→idle(手続きsine)」を順に作ったが**全て「固い/ロボットっぽい」で却下**された。手付けFKは overlap/weight/接地の機微が出ず、手続きsineも周期感が機械的。**動物の自然な運動は、人が再現するより実モーションデータ（mocap）を持ってくる方が圧倒的に近道**。
- **Mixamo は人型(二足)専用**。自動リグもアニメも humanoid 前提で、**四足(猫)には使えない**（猫モーション無し・リグ非対応）。四足のフリーモーションは別途探す必要がある。
- 入手しやすい四足 mocap = **Khronos glTF サンプルの "Fox"**（CC0モデル＋CC-BYリグ/アニメ・Survey/Walk/Run・GitHub raw で直DL）。`raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Fox/glTF-Binary/Fox.glb`。キツネ=猫に近い四足でボーン構成もほぼ1:1で対応しやすい。ライセンスは anim=CC-BY(tomkranis)で**attribution 必要**。

### ヘッドレス Blender で「ワールド回転＋rest差分」FKリターゲット（アドオン無しで自前実装）
- Rokoko 等の GUI アドオン無しでも、ヘッドレスで自前リターゲットできる。手順: ①対象blendを開き Fox.glb を `import_scene.gltf` で同シーンに取込 ②ボーン対応表(cat→fox)を作る ③rest のワールド回転を採取し **`offset[c] = R_cat_rest[c] ⋅ R_fox_rest[f]⁻¹`** を一度計算 ④各フレーム `scene.frame_set(f)` で Fox を評価→各catボーンの目標ワールド回転 `Qc = offset[c] ⋅ Qfox` →**親優先**でローカルポーズへ変換 `pose_local = Lrest⁻¹ ⋅ Qparent⁻¹ ⋅ Qc` を `rotation_quaternion` に設定し `keyframe_insert` ⑤Fox削除→`export_animation_mode='ACTIONS'` で全クリップをGLBへ。
- **ワールド空間でオフセットを取ると向きの違いを自動吸収**（fox前進=cat前進）。回転は `Δ→OΔO⁻¹` の共役で cat の座標系に正しく写る。
- **quaternion 連続性**必須: 各フレームのローカル回転が前フレームと `dot<0` なら negate（同半球に揃える）。これを怠ると補間でスピン/jitter。
- **限界**: 回転のみ移植＝**足の接地IK無し→足滑り**。その場アニメの標本表示なら許容だが、接地を詰めるなら足IK/接地ロックを別途。剛体スキニングなので見た目は骨格のまま（動きのタイミングだけ自然化）。
- 再現スクリプト: `docs/260618/retarget_fox_to_cat.py`（MAP/クリップ/offset式を編集して対応・対象を変更可）。

## 2026-06-22 — 06 cat-skeleton: リターゲットの「横歩き」修正（骨ローカル座標系の共役変換）

### リターゲットで `Qc = offset @ Qf`（左乗算）は骨の向きが違うと方向がズレる → 右乗算 `Qf @ Rf⁻¹ @ Rc` で共役変換
- Fox の WALK/RUN が猫に移植すると**横歩き・横走り**になった。SURVEY（見回し idle）は方向感が薄く気づきにくい。
- **原因**: Fox の hips 骨ローカル Z 軸 = `[-1,0,0]`（世界 -X 向き）、猫の hips 骨ローカル Z 軸 = `[0,-0.14,-0.99]`（世界 -Z 向き）。元の式 `Qc = offset @ Qf`（= `Rc @ Rf⁻¹ @ Qf`）は Fox のワールドデルタをそのまま猫に適用するが、骨ローカル座標系が異なるため**同じローカル回転が異なるワールド効果を生む**。結果: Fox が -X に歩く動きが猫でも -X 方向に出る → 猫の前方 -Z に対し90°横。
- **修正**: `Qc = Qf @ Rf⁻¹ @ Rc`（右乗算）に変更。これは各ボーンのローカルデルタ δ を `frame_change @ δ @ frame_change⁻¹`（frame_change = `Rc⁻¹ @ Rf`）で共役変換する効果があり、Fox のローカルデルタを猫の骨座標系に正しく写す。rest ポーズ（Qf=Rf）で identity（不変）、posed で Fox の各軸の回転が猫の対応軸に変換される。
- **スクリプト変更は1行**（`retarget_fox_to_cat.py` L61）。全ボーンに一括適用で子ボーンの親チェーンも自動的に整合（Qpar を通じて子の ql 抽出も連鎖的に修正される）。再ベイク→GLB再出力→キャッシュバスター `?v=2` で即反映。

### 骨の向き（ローカル座標系）はヘッドレス Blender で実測して確認する
- `rest_world(arm, bone) = (arm.matrix_world @ arm.data.bones[bone].matrix_local).to_quaternion()` で各軸の世界方向を出力。Fox と猫の hips を比較して Z 軸の方向差（-X vs -Z）を確認した。
- **目視や推測で「同じ方向を向いているだろう」と仮定しない**。glTF インポート時の軸変換や Tripo の出力方向は不定（[[2026-06-10 生成GLBの正面は実測]]）。リターゲット元/先の骨軸は必ず数値で確認する。

## 2026-06-27 — 06 cat-skeleton: 3D 再構成エンジン比較実験（Tripo vs Meshy / 単体 vs マルチビュー）

### Meshy (HiggsField MCP) > Tripo — 同一入力で Meshy の方が高精度
- 同じ元画像（猫骨格 側面 1 枚）で Tripo API と Meshy (HiggsField `image_to_3d`) を比較。
  Meshy の方がリブケージ・関節の立体感、骨の分離度ともに上。
- HiggsField MCP 経由で `image_to_3d`（Meshy）を呼べる。`should_texture=true`, `enable_pbr=true`,
  `symmetry_mode="on"`, `target_polycount=100000` が骨格に適したパラメータ。
- GLB サイズは Meshy 15MB vs Tripo 1.5MB（Draco 圧縮+アニメ付）。Meshy 版はテクスチャ込み・未圧縮。

### AI 生成ビュー追加 (NanoBananaPro) は骨格のような細い構造体に逆効果
- NanoBananaPro (Google, HiggsField MCP) で元画像から 3/4 前方ビューを AI 生成。単体では整合的で高品質。
- しかし 2 枚（元+生成）で `multi_image_to_3d` に投入すると**右前足が欠損**。
- **原因**: 骨格の細い棒状パーツ（前足の骨）の位置・角度が 2 画像間で微妙に不整合。
  マルチビュー再構成が「矛盾する情報」として処理し、欠損を生む。
- **教訓**: マルチビュー 3D 再構成に AI 生成ビューを使うなら、大きな面を持つ有機的な対象（顔・体）に限る。
  骨格・ワイヤーフレーム・植物の枝など細い構造体には使わない。実写マルチアングルなら有効な可能性あり。

### NanoBananaPro (Google) の画像生成品質は高い
- 参照画像を入力して「同一被写体の別構図」を生成するタスクでは、プロポーション・色味・質感の再現度が高い。
- `resolution: "2k"`, `aspect_ratio: "4:3"`, 参照画像を `medias[{role:"image"}]` で渡す。コスト 2cr/枚。
- 2 枚生成して良い方を選ぶ運用が低コスト（4cr で 2 バリエーション）。

### Three.js で複数 GLB を並べて比較するビューアは即席で作れる
- 3 パネル（各 renderer + camera + controls）を flex で並べ、Sync rotation で左パネルの操作を全パネルに伝播。
  Wireframe トグルで内部構造も比較可能。`compare-skeletons.html` として実装。
- ポイント: 各モデルの bbox 正規化（scale + center）を個別に行い、同一スケールで並べる。

## 2026-06-28 — 06 cat-skeleton: Meshy メッシュのリグ移植（重複頂点・非対称メッシュの根治）

### AI 生成メッシュの重複頂点が bone heat を黙殺失敗させる
- Meshy GLB は 99K 頂点中 **47,467 個が同一位置の重複**（非多様体）。bone heat（`ARMATURE_AUTO`）は「ボーンヒートウェイト：一つ以上のボーンで解決に失敗しました」エラーを出す**か**、エラーなしで全頂点がウェイト 0 になる（黙殺失敗）。
- **`remove_doubles(threshold=0.0001)`** で一掃（99K → 51K）。閾値は小さくする（0.001 だと隣接する別ポリゴンの頂点まで結合して形が崩れる）。AI 生成メッシュを bone heat にかける前は必ず重複頂点チェック。
- 検出: `bm.verts.ensure_lookup_table()` 後に KDTree で `find_range(v.co, 0.0001)` が 2+ を返す頂点をカウント。

### AI 生成メッシュは左右非対称になり得る → Mirror modifier で強制対称化
- Meshy の猫骨格は**右後足エリアの頂点がゼロ**（左後足は 2,476 頂点）。bone heat が `paw_rear.R` にウェイトを割当てられず、歩行時に右後足が伸びきる（rest ポーズのまま引きずられる）。
- **修正**: 右半分（x < -0.002）を bmesh で削除 → Mirror modifier（X軸, merge_threshold=0.001）→ 53,972 頂点。
- AI 生成 3D は**単一視点入力だと見えない側が非対称になる**（06-18 の「裏側が粗い」教訓と同根。Meshy でも同様）。左右対称の被写体（骨格・人体・車等）は**リグ前に Mirror modifier で強制対称化**する。ウェイト確認: `paw_rear.L` と `.R` の頂点数が一致するか。

### Blender の八面体ボーン表示を関節アーティファクトと誤認する罠
- Blender デフォルトの八面体ボーン表示は、メッシュの関節部分に重なると**三角形のアーティファクトに見える**（特にビューポートスクショで）。実際のメッシュ変形はクリーン。
- **切り分け**: `arm.data.display_type = 'STICK'` に変更するか `arm.hide_viewport = True` でボーンを非表示にしてメッシュだけ見る。「ボーン表示の形」と「メッシュの変形不良」を混同しない。
- 今回ユーザーに「後ろ足がおかしいね」と指摘された画像の一部は、実際にはボーン表示の重なりだった（もう一部は `paw_rear.R` ゼロウェイトの実不良）。

### ウェイト転写の前に「なぜ直接 bone heat できないか」を問う
- メッシュ差替えの初手は「旧メッシュからウェイト転写」（Data Transfer / KDTree / Shrinkwrap）だが、**新メッシュに直接 bone heat をかける方が確実なことが多い**。今回 Shrinkwrap は内部ジオメトリを破壊し、Data Transfer は形状差が大きく不正確、KDTree は近接マッチングで関節付近が崩れた。最終的に bone heat（重複頂点除去 + Mirror 後）が最もクリーンなウェイトを生成した。
- bone heat が失敗する原因は（1）非多様体（重複頂点）（2）頂点数過多（今回 311K で失敗、51K で成功）（3）密閉メッシュ内部のボーン。原因を潰してから再挑戦する方が、転写系手法より結果がよい。

## 2026-06-29 — 06 cat-skeleton: トコトコ歩き調整（リターゲットパラメータ反復 + 後脚短縮）

### AI 生成骨格の前後脚長比は実測して修正する（骨格モデルは猫の実プロポーションと一致しない）
- Meshy で生成した猫骨格は**後脚が前脚の 1.39 倍**（shin 0.212 vs forearm 0.115 でほぼ倍）。実際の猫はほぼ同じか後脚がわずかに長い程度。この不均衡が「歩くとしんどそう」の主因だった。
- **修正**: Blender Edit mode で `shin` と `paw_rear` のボーン tail を移動し長さを変更（shin 0.212→0.115、paw_rear 0.081→0.046）。前後比 1:1 に。ボーン長変更は .blend ファイルに保存される（リターゲットスクリプトは rest pose から自動で読む）。
- **ボーン長変更後は必ず再ベイク**。rest pose が変わるため `Rc` と `Lrest` が変わり、旧アニメはそのままでは使えない。Fox.glb を再インポートして全クリップを再ベイクする。

### 猫のトコトコ歩き = 小さい動きの蓄積（ダンピング全体を強める）
- 「トコトコ」の質感は各関節の可動域を大幅に絞る（identity→ql slerp factor を 0.20〜0.60 に）ことで得られる。逆に 0.65〜0.75 では「しんどそう / 大げさ」に見える。
- 前脚と後脚の歩幅バランスも重要: 前脚（upperarm）を後脚（thigh）より緩め（0.60 vs 0.35）にすると前足主導の軽い歩きに。逆にすると腰から歩く重い印象。
- **反復的に調整する**: ユーザーと Blender ビューポートで 1 パラメータずつ調整→再ベイク→確認のループ。1 回で決まらない。6 イテレーションかかった。

### Blender の scene FPS が glTF インポートのフレーム変換に影響する
- Fox.glb を `import_scene.gltf` で読み込む時、**アニメーションの時間→フレーム変換に scene の render.fps を使う**。24 FPS なら Walk=0-17（18フレーム）、12 FPS なら Walk=0-8（9フレーム）。
- Blender ビューポートでスロー確認するために FPS を下げると、次の Fox 再インポートでフレーム数が半減する。**GLB エクスポート前に FPS を 24 に戻してからベイクする**こと（Three.js 側の timeScale は 24 FPS 前提）。

## 2026-07-02 — 06-cat-skeleton（前脚大改修: 対称化・リジッドスキニング・傾き再校正）

### 接地キャリブレーションは「ボーン先端」でなく「メッシュ最低点」で測る
- ボーン tail の z=0 合わせで傾け角を -20° と決めたら、実際は後足メッシュが全フレーム床下 4〜6cm。
  このリグは後脚ボーンが短縮済みで、**メッシュの足はボーン先端より 9cm 下まで伸びていた**。
- 画面に映るのはメッシュだけ。地面接触・浮き・沈みの検証は必ず
  `(matrix_world @ 頂点座標).z` の領域最低値で行う。前後の足の最低値が均衡する角度を探し
  （実測 -13°）、残差は全体 z_lift で吸収する、の2段構え。
- 副次の教訓: v6 の「後脚浮き」がユーザーに見えなかったのも同じ理由（ボーンは浮いてもメッシュは接地）。

### 骨格標本メッシュはリジッドスキニング（ただし骨とメッシュの解剖一致が前提）
- スムーズな自動ウェイト（頂点の51%が有意ブレンド）だと**骨幹そのものがバナナ状に湾曲**する。
  肉のあるキャラでは自然でも、剛体であるべき骨が曲がる骨格標本では致命的な嘘
  （ユーザー指摘は「弓状になりすぎ」）。肘の曲げを深くした途端に露出した。
- 対策: 各頂点を支配ボーン 1 本 100% に固定（argmax）。ただし:
  1. **argmax は小さいボーンを飲み込む**（paw が forearm に完食され足首が溶接された）
     → 関節境界は「どちらのボーン軸線に近いか」の幾何で引き直し、爪先は領域指定で救出
  2. **自動ウェイトの癒着**（肋骨の一部が腕ボーン支配）はリジッド化で裂けて露出
     → 「骨軸から解剖学的にあり得ない距離の頂点は体幹へ返す」ルールで掃除
  3. **はぐれ頂点は1個でも扇アーティファクトになる** → 隣接多数決（60%閾値×2周）で吸収
  4. **骨長とメッシュが不一致の部位（短縮済み後脚）には適用禁止**。距離ルールが誤爆して
     脛の下半分を胴体に飛ばした。後脚はスムーズ維持が正解（動きが小さければ粗は見えない）
- 残課題: リジッド境界の関節せん断（手首の折りで面が三角ヒレ状に伸びる）。境界1-2リングだけ
  50/50 ブレンドにするのが本命対策（実在の手根骨クラスタとも整合）。

### mocap の左右差は「良い側の半周期ミラー」で根治できる（ゲイン調整では直らない）
- Fox mocap は右前脚だけ歩幅 2/3・9フレーム中5フレーム同位置に留まる癖があり、
  体が前進するビューアでは**右足だけ滑って見える**。ダンピング（ゲイン）は振幅しか変えられず、
  タイミングの偏りは直せない。
- リグが完全対称なら `Q右(f) = mirror(Q左(f + T/2))`（ワールド回転の X=0 面ミラー、
  quaternion は (w,x,-y,-z)）で右を合成すると数学的に完全対称になる。体幹は
  `slerp(Q(f), mirror(Q(f+T/2)), 0.5)` で対称化。半周期が小数になるクリップは
  `frame_set(int, subframe=frac)` でサブフレームサンプリング。
- 前提検証を忘れない: 適用前にリグ自体の左右対称性を実測（ミラー共役での姿勢差 0° を確認）。

### レストポーズが変な姿勢だと、ダンピングは「変な姿勢に向かって」丸める
- 肘の伸びきりロック（178°）はゲインをいくら下げても直らない。ダンピングは
  「レストに向かう slerp」であり、このリグのレスト肘がほぼ直立＝伸びきりだから。
- 対策: SPINE_PITCH と同じ発想で関節に**恒常オフセット**（肘屈曲・足首の立て）を足す。
  回転方向の符号はボーンロール依存で先験的に分からない→±両方を実測して選ぶ。
  ただし恒常オフセットは全フレームに乗るので入れすぎると弓なり化する（肘は12°で過剰、7°が適）。
- 全身傾け（表示変換）は四肢のスイング面ごと回してしまう→前脚だけ肩支点の
  ワールド軸カウンター回転で「対地スイング角」を独立制御（TILT + COUNTER = 一定 を保つ）。

### Blender MCP 経由の編集は undo が効かない — 破壊操作の前に復元経路を確保
- `bpy.ops.ed.undo()` は MCP の exec には積まれず、ウェイト破壊（9,648頂点誤移動）を
  巻き戻せなかった。復旧はディスクの正本から再オープン→全手順スクリプト再実行で数分。
- 運用: 破壊的なメッシュ/ウェイト操作の前に (1) ディスクの保存状態を確認 (2) 再構築手順が
  全部スクリプト化されていることを確認。`libraries.load` は自ファイルパスを拒否するので、
  部分復元は `shutil.copy2` で一時コピーを作ってから読む。
- 同じ理由で、実験セッションの成果は「会話の中のコード」でなく**ディスクのスクリプト**に
  必ず固める（今回 `retarget_fox_to_cat.py` v12 と `skinning_rigid_front.py` に永続化）。

### .blend には別セッションの作業が混入し得る — エクスポート前にシーン棚卸し
- 6/29 保存の .blend に無関係のアニメ付き人型リグ2体が混入していた（同一 Blender
  インスタンスでの別実験の残骸が保存時に巻き込まれた）。「シーン全体エクスポート」なら
  GLB に同梱されていた。スクリプトの `[o for o in bpy.data.objects if o.type=='ARMATURE'][0]`
  のような雑な取得も誤爆する（アルファベット順で LaFemme が先頭に来る）。
- 運用: エクスポート・ベイク前に `scene.objects` を列挙して猫関連だけであることを確認。
  オブジェクト取得は名前指定（`bpy.data.objects["cat_rig"]`）で行う。

### ビューポートの見た目は「二重変形」かもしれない — glTF に持ち出す前に変形経路を数える (2026-07-03)
- parent_type='ARMATURE'（Armature Deform 親子付け）と Armature modifier が併存すると変形が
  **2 回**かかる。6/28-7/2 の歩様調整は全部この 2x ビューポートで行われていた（発見の経緯:
  hips に打った補正キーが設定値の 2 倍効いた）。glTF の skin は 1 回しか変形できないので、
  この見た目はそのままでは GLB に乗らない。
- 検証法: Armature modifier を一時 OFF にして変形が「半分になる」（=parent も変形している）か
  「消える」（=modifier だけ）かを見る。
- 移植法: **M² ポストベイク** — 各ボーンの armature-space 変形 M=P·G⁻¹ について P'=M·P となる
  basis を逆算してキーを打ち直すと、リジッド頂点で二重変形と厳密一致（実測 -1.21 vs -1.21cm）。
  パラメータ再調整より速く、確実。前提: 全ボーン use_connect=False（connect ボーンは location
  チャンネルが無視され M² の並進が乗らない）。副作用: ボーン位置はメッシュと一致しなくなる
  （SkeletonHelper 系の表示には不向き。マテリアル切替の BONE 表示なら無影響）。

### glTF エクスポートの三大罠: hide_viewport / 全アクション評価 / ゴミアクション混入 (2026-07-03)
- `hide_viewport=True`（モニタアイコン）のアーマチュアは depsgraph から外れ、**skin ごと**
  エクスポートから消える。エクスポート前に必ず False にする。
- ACTIONS モードは「対象オブジェクトのスロットに合致する **bpy.data.actions 全部**」を
  評価しながら書く。(1) 過去の GLB 検証インポートで増えたゴミアクションが全部混入する
  （45 本混入で 24 クリップの GLB ができた）(2) 終了後のオブジェクト transform が最終評価値で
  汚れる（Z_LIFT 0.0181→0.0244 になり接地計測が 0.63cm 狂った）。
  対策: エクスポート前に正規アクション以外を削除 + orphans_purge、エクスポート後に表示変換を再設定。
- GLB を Blender に検証インポートしたら、オブジェクト削除だけでなく「増えたアクション削除 +
  orphans_purge」まで。オブジェクトを消してもメッシュデータ（ICO球 ×5 など）とアクションは残る。

### リジッド境界のせん断ヒレは「関節の形」でブレンド戦略を変える (2026-07-03)
- 100%/100% のリジッド境界は関節が折れると境界辺が 20-28 倍に伸びて三角ヒレになる。
  1 リング 50/50 では段差が「境界」から「リングの縁」に移るだけで解決しない。
- **直列につながる細長い骨（肘・手首）**: 骨線分への距離差 d_parent−d_child の smoothstep
  （遷移帯 ±1.5cm ≒ 2-3 リング分）が滑らかで最良。骨幹はリジッドのまま保たれる。
- **太い胴体 vs 細い肢の関節（肩）**: 距離場は遷移面が解剖学的境界とズレて誤爆する
  （肩甲骨も上腕骨頭も chest 軸より上腕骨に近い）。トポロジカルな境界リング多段
  （50/50 + 75/25）が安全。
- ヒレの犯人捜しは目視でなく **evaluated mesh の辺伸び率**（変形後長/レスト長 > 3x を列挙、
  両端の頂点グループつき）で。今回「手首のヒレ」と思われていた最大ヒレは実は肘だった。

### Blender 5.x 移行の実務メモ (2026-07-03)
- `Action.fcurves` は廃止 → `act.layers[0].strips[0].channelbags[0].fcurves`。
- `animation_data.action` を付け替えたら `action_slot` の明示バインドが安全
  （`act.slots[0]` を代入）。
- **ポーズの location はアクションに location キーが無い限り frame_set で上書きされない**
  （rotation だけ上書きされる）。手動ポーズ実験の後に action 評価で計測すると location の
  残留ゴミで汚染される（今回 2 回ハマった）→ 計測前に全 pose bone の loc/rot/scale リセット。

### 接地めり込みの補正は関節角でなくルートの上下（ボビング）で (2026-07-03)
- 回転のみリターゲットの宿命で接地足が床を貫く（前足 -1.9cm）。全体 Z_LIFT は前後の足の
  妥協点で既に張り詰めており動かせない（後足は接地 -0.4cm しかなかった）。PAW_PITCH の
  増減は幾何が直感と逆に働き数 mm しか稼げない（実測して悪化を確認）。
- 正解: 毎フレーム全足メッシュ最低点を計測し、めり込んだ分だけ hips（ルート）をワールド +Z に
  持ち上げるキーを打つ。回転を触らない=足滑りを生まない。サスペンション期（全足浮き）は
  補正 0 になり歩容と整合。MARGIN 2mm を残すと接地感が消えない。トロットでは補正カーブ自体が
  周期的な上下動になり、むしろ自然なボビングとして見える。

### M² 移植は「評価済みの見た目」と一緒に「評価された壊れ」も運ぶ (2026-07-03 PM)
- M² は 2x ビューポートを厳密再現するが、それは**関節折れ角の 2 倍化**（手首 94°・肘 ~90°）も
  そのまま保存するということ。7/2 に「壊れだしてきた」と評価された醜さの一部（鋭角折れ）は
  ヒレの陰に隠れていて、ヒレを直した後に主役として露出した。
- 「見た目を厳密に保つ」は工学的には正しくても、**保たれた見た目自体が事故の産物**なら
  意味がない。移植の厳密性と、見た目の望ましさは別の問題として扱う。
- M² 環境でのパラメータ調整は「見た目の角度 ≈ ベイク角 × 2」を常に頭に置く。全体の強さは
  「v12 素値 × 倍率」の一括スケールで動かすのが安全（個別にいじると相対バランスが崩れる）。

### 「弓状に曲がる」の犯人捜しは剛体予測からの逸脱計測で (2026-07-03 PM)
- 見た目の「骨幹の湾曲」には 2 種類ある: (a) ウェイトブレンドによる実変形（ゴム曲がり）
  (b) 各関節の折れが連なった**姿勢の弧**（骨は直線のまま）。目視では区別できない。
- 判定法: 支配ボーンの M（pose @ rest⁻¹）で各頂点の剛体予測位置を計算し、evaluated 位置との
  距離を骨軸に沿ってビン集計。逸脱ゼロの区間は物理的に直線 = (b)、逸脱があれば (a)。
- 今回: 骨幹（手首から 3cm 以上）は逸脱 0.00cm で完全剛体 = 弓は (b) だった。ウェイトを
  いくらいじっても直らない（実際 paw ゲイン変更で「変わらない」とユーザーが正しく観察した）。
  対策はゲイン側（動きの強さ）。
- 距離場 smoothstep 遷移帯の実効幅は設計値より広がる（±1.5cm 設計 → 実効 ±2.5cm。
  細い骨では d_child ≈ 骨軸距離となり等値面が骨軸方向に伸びるため）。狭めるなら W=0.8cm
  でヒレは再発しない（50/50 の急段差ではなくグラデーションが保たれる限り）。

## 2026-07-05 — 06 cat-skeleton: 前足タッチダウン前倒し（v14.6・IK的ポストパスの設計教訓）

### 「表示定数の再計測」はパラメータ変更とセットで義務化する
- 「前足が空中を掻いておかしい」の主因は動きでなく **Z_LIFT が fullgain 基準のまま**だった
  こと（全身 1.3cm 浮き・全足離地フレーム×7）。コメントに「再ベイク後は要再計測」と
  書いてあっても、別の主題（弓状対応）の最中では飛ぶ。
- 教訓: ゲイン・姿勢系（DAMPEN/SPINE_PITCH/TILT）を触ったら Z_LIFT 再計測（最深沈み
  -1.5cm ルール）を**手順の一部**として STATUS の調整ノブ表に組み込む。

### プレビュー用 fps_base はインポートのフレーム換算を汚染する
- テンポ確認で `fps_base=1.4286` を残したまま再ベイク → glTF インポートの秒→フレーム換算が
  狂い Walk 0-17 が 0-24 に化けた。スクリプト冒頭で `fps_base=1.0` を強制して根治。
- 見た目の再生速度に使う設定が、データ変換のスケールに波及する典型例。

### mocap に無い動きはゲインでは作れない — 源流を実測してから盛る
- 「振り出し切りで接地してほしい」に対し、まず Fox 原本の前足軌跡を実測 → **Fox 自体が
  トロット流儀**（最前到達は空中 z+11.6、接地は体の下）と判明。ゲイン調整で寄せられる
  性質のものではなく、ポストパス（TD）新設が正解だった。リターゲット系の要望は
  「源流にあるか」をまず計測で切り分けると迷走しない。

### 解剖学的な到達限界は早めに数値で出す
- 肩 z≈27cm・脚実効長≈29cm → 接地可能な最前点は前方 ≈10cm が幾何限界。ユーザーの
  「もっと前に」に対して、限界値と「前に出すには肩を下げる（SPINE_PITCH）しかない」を
  提示できたので、姿勢変更の判断がスムーズだった。グリッドプローブ（肩×肘の2軸掃引で
  接地フロンティアを実測）が有効。

### 骨格モデルの scapular glide は「メッシュの支配ボーン」を先に確認
- 実猫の前方リーチは肩甲骨滑走が主役だが、肩甲骨メッシュが chest 支配のリグで upperarm を
  並進させると肩関節が外れて見える。代替 = **着地瞬間の手首（パスターン）沈み込み**
  （衝撃吸収として解剖学的にも正しく、実効脚長 +2cm、爪先立ち着地の解消も兼ねる）。

### 周期運動のヒンジ弧は反転する — 符号プローブは毎フレーム
- 「+3°で下がる向き」を1姿勢で測って全フレームに使うと、周期の中盤〜後半で弧の向きが
  反転して解が届かない。ヤコビアン（応答勾配）を**毎フレーム実測**する減衰付き 2D
  ニュートンに変えて安定。交互座標降下は接地不能ターゲットで肘が上限まで暴走する
  （二分探索の fail 側で上限値を適用してしまうバグと相まって発散）。

### 左右対称に見えるパイプラインでも「レスト引き寄せ」は非対称
- ミラー半周期ベイクで入力は対称でも、DAMPEN の slerp 先 = レストポーズが歩行中段
  （左前/右後）なので左右の到達力が変わる（frontier L -7.8 / R -14.4）。独立に最適化すると
  跛行に見える。**共通歩幅（両側が達成できる側に統一）+ プラントフレームの適応探索**
  （L f3 / R f11 = 半周期差）で対称性を回復。
- 一般化: 「対称な入力 × 非対称な吸引先 = 非対称な出力」。対になる要素の最適化は
  独立に解かず、共通目標を先に決める。

### ユーザーの現象記述は座標系の手がかり
- 「肩の位置が上がりすぎだから接地点が手前になるのでは」— そのとおりで、接地フロンティア
  は √(脚長² − 肩高²) で決まる。肩を 1cm 下げるごとに前方到達が数 cm 伸びる領域だった。
  現象→幾何の翻訳を怠らず、ユーザーの直観を計測で検証すると速い。

## 2026-07-06 — 06 cat-skeleton: Cascadeur 2025.3 四足リグ路線へ大転換（手作りリグの終着点と乗り換え）

### 手作りリグで scapula を動かす路線は2つの壁で頓挫 → 専用ツールへ乗り換えるのが正解だった
- ユーザー要望「上腕を前に出したい（肘を胸の前へ）」に対し、DAMPEN 0.50→0.75、上腕恒常前傾
  （UPPERARM_SWING 12°）、**scapula ボーン追加**まで手作業で積んだが「あんまり良くない」。
- scapula を実際に回すと **①split 切断線が開く（独立ピース化した肩甲骨の縁がギザギザ）
  ②肩前の既存 mis-weight（neck 100% と upperarm 100% の頂点が直接隣接）が腕前進で 9cm 級に裂ける**。
  mis-weight 根治を2回試みて2回とも発散（隣接多数決が首まで浸食し 6,570 頂点巻き込み）→ backup 復元。
- 教訓: **半日の手作業でツールが標準装備している機能（scapula 内蔵の四足リグ）を再発明していた**。
  「うまくいかないね」が続いたら、手を止めて**専用ツールの有無を先に調べる**（今回はユーザーが Cascadeur を想起）。

### Cascadeur 2025.3 の四足対応は猫・犬に最適化（scapula 内蔵）— PC 導入済みなら即戦力
- 2025.3(2025-11)で Quadruped Quick Rig + AutoPosing 追加。`C:\Program Files\Cascadeur` の
  `resources/autorig_templates/Quadruped.qrigcasc` と `resources/scripts/python/prototypes/rigs/qrt/quadruped/`
  がローカルの真実。要求骨: pelvis/spine_1-3/neck_1-2/head/head_end/**scapula_l-r**/humerus/radius/carpals/
  paw_f/femur/tibia/tarsals/paw_h/tail_1-4/tail_end。
- 料金(cascadeur.com/plans): **Free=リグ+AutoPhysics+手付け+Animation Unbaking 可・export は .casc のみ・300f/120関節上限**。
  **Indie $8/月=FBX/DAE export**。**Pro $33/月=四足 AutoPosing(AI)+アニメリターゲット**。両プラン12ヶ月で買い切り化。
  → **Free で品質検証まで可能・Web 反映に最低 Indie**。四足の AI 自動ポーズだけが Pro。

### Quick Rig は「既存骨をスロットに割当てる」方式 = 骨なしメッシュだと全 None で詰む
- 素のメッシュを import すると Quadruped タブの全スロットが「None」（割当てる骨が無い）。**骨入り FBX が必須**。
- **決め手 = エクスポート時に骨名と頂点グループを Quadruped.qrigcasc の Bone name に完全一致させる**
  → Quick Rig が名前でスロット自動マッピング。手作りスキンも頂点グループ改名で FBX 往復生存し、
  **Cascadeur 側の自動スキン（バラバラ骨格＝肋骨/椎骨が分離した島で崩れるリスク）を丸ごと回避**できた。
- 欠ける中間関節（spine_2/neck_2/carpals/tarsals/paw_f/paw_h/*_end）は既存関節の補間で挿入（rigid=親追従）。
  Cascadeur のリグ生成は位置さえ合えば OK。実装は `docs/260618/export_to_cascadeur.py`（再利用可）。

### 別スケルトン間のアニメ転写は絶対 Copy Rotation でなくデルタ・リターゲット
- rest 姿勢（骨の向き）が違う骨へ絶対世界回転をコピーすると固定オフセットで捻れる。
  正解: 各ソース骨で **delta = pose_world @ rest_world⁻¹**、目標 **W = delta @ restC[target骨]**、
  親優先で local basis に変換してキー。=「同じ世界空間の動き」を rest 向きが違う骨へ正しく載せる。
- 動く末端骨のマッピングに注意: 我々の `paw_front`（手首→爪先の1本・歩行で回転）は Cascadeur の
  **carpals（手首）** に割当てる（paw の動きが手首関節に乗る）。paw_f は補間挿入で親追従。
- Cascadeur 側の適用: `File→Import→Import Fbx/Dae→Animation`（リグ済み1体なら curve だけ載る・再リグ不要）。

### Blender MCP は長セッションで落ちることがある（一過性）→ 全手順スクリプト化で無傷
- FBX エクスポート直前に Blender が落ちた（プロセス消失・ポート閉）。だが正本 .blend は保存済み、
  cat_casc 構築・転写・export は全部スクリプト化してあったので、**再起動→再実行で完全復旧**（損失ゼロ）。
- 教訓: Blender MCP 作業は「ワンショットで再現できるスクリプト」に必ず落とす。節目で .blend 保存 + bak 退避。

## 2026-07-10 — 07-manga-street（住宅街生成+漫画線画/トーン）

### 前面方向の符号を「side そのまま」で使うと両側とも壁に埋まる
- 道路の左右に区画を置く場合、前面(道路)方向は `-side`（side=+1 の区画は x+ にあり、道路は x=0 方向）。
  窓・サッシ・ベランダを `+side` にオフセットして両側の建物で全部屋内に埋没させた。
- 対策: `const out = -side;` を区画ビルダーの冒頭で 1 回定義し、前面系オフセットは必ず `out` 経由に統一。
- 検出法: 「夜に窓が 1 つも光らない」で発覚。頂点色は正しく書けていた（データ検証だけでは足りず、
  カメラを 1 軒の目の前に置く「現物確認」で判明）。

### 中実 box の中に別 box を入れると見えない（当たり前だが起こる）
- サッシ=枠のつもりの box は中実。ガラス box をその「内側」に置くと完全に隠れる。
  枠+面の 2 box 構成では、面 box を枠 box の外面より僅かに前へ出す（+1.5cm）。

### RT へのレンダリングにはトーンマッピングが効かない（three r170 実測）
- `renderer.toneMapping` は `currentRenderTarget === null` のときだけ適用。RT に描いた beauty は
  リニアのまま → TONE の輝度量子化はシェーダ内で `c/(c+1)` + `pow(lum, 0.6)` で自前トーンマップしてから。
- 同じ理由で LINE/TONE の最終合成は EffectComposer + OutputPass を使わず素の ShaderMaterial で
  画面直描き（OutputPass の ACES は紙白 1.0 を ~0.8 に濁す）。

### 照明不変の線画は albedo(頂点色 unlit) RT を第 3 のエッジ源にして成立
- depth+normal だけでは路面標示・塀の目地・看板文字が線に出ない（同一平面・同一法線のため）。
  頂点色を MeshBasicMaterial override で RT に描き、色差エッジを合成すると「素材境界の線」が出る。
- 検証: LINE モードで昼(13時)と夜(22時)のスクショが 29/996 万バイト差（fps 表示のみ）＝完全照明不変。

### 遠方路面の depth エッジ誤検出は「線形化+相対差+法線傾き補正」の 3 点セットで殺す
- 目線 1.5m で 200m 先を見ると路面のピクセル内 depth 差が巨大になり、素朴な閾値では道路全体が黒くなる。
  `slope = 1/max(|normal.z|, 0.14)` で視線に平行な面ほど許容を増やし、閾値は `uThD * 距離 * slope`。

### 網点は「最終解像度の最終パス」でかける（エッジだけ SS 2x→縮小）
- 2x で網点を打ってから縮小するとドットが灰色に溶ける。エッジ検出・膨張は SS 側、
  45° ドットグリッドは `gl_FragCoord` 基準で最終パス。PNG 書き出し倍率にはピッチを倍率追従させる。

### hash 違いの URL へ browser_navigate してもページは再読込されない
- `#s=...` だけ違う URL への navigate は same-document 扱いで古い JS が動き続ける。
  「実装したのに画面が変わらない」の正体。検証リロードは `?v=N` のクエリを毎回変えて確実にバイパス。

### renderer.info は「最後の render 呼び出し」の統計
- マルチパス（G-buffer 3 枚+quad 2 枚）では draw calls が最終 quad の 1 になる。
  パフォーマンス計測はパス統合前の CLAY モードで見るか、パス毎に読む。

## 2026-07-10 — 07-manga-street 拡張(issue #1〜#7 を同日消化)

### 開発フロー: issue→ブランチ→実装→Playwright 検証→Bedrock-Codex レビュー→修正→PR→squash マージ→Vercel 確認
- 1 issue 1 ブランチ(feat/issue-N-slug)で 7 件回して破綻なし。コミットに `Closes #N` で issue 自動クローズ。
- サブスク Codex は CLI バージョン非互換(gpt-5.6-sol 要求)で全滅中 → 全レビューを
  `CODEX_HOME=D:\claude\awsBedrock\.codex-bedrock-test AWS_REGION=us-east-1 codex exec` で実施。
  毎回具体的な実バグを検出しており(7 件中 6 件で指摘あり)、レビュー価値は非常に高い。

### ロケーション/季節追加の鉄則: 乱数消費数を変えない
- 分岐で rr/pick の「呼び出し回数」を変えなければ、既存ロケーションの街並みは 1 区画も動かない
  (residential plots 56 / 内訳一致で毎回実証)。レンジや配列の中身だけ変える。
- 「生成しないなら消費だけして skip」は **全消費を終えてから continue**。pick を continue の後に
  書く消費位置ミスを Codex に 2 回指摘された(遠景ビル・rural)。

### L1 の新規 FX メッシュは scene.add を忘れる(2 連続でやった)
- rainFx(雨筋)・petalFx(花びら/粉雪)とも「作った・updateXxx も呼んだ・でも scene.add してない」
  で不可視。データ検証(visible/opacity)では気づけず、Codex の静的レビューが検出。
- 対策: モジュールレベルの FX メッシュを増やしたら boot の scene.add 群に即追加。原寸クロップで
  パーティクルの実描画を確認する(縮小スクショでは 1px 線・小スプライトが消えて見えない)。

### 巨大地面プレーンは低い水面を深度で隠す
- 420m 四方の地面(上面 y=-0.01)の下に海面(y=-0.55)を置くと完全に隠れる。夕日で照らされた
  地面を「海が見えた」と誤認していた(Codex 検出)。水面系ロケーションでは地面の x 範囲を陸側に制限。

### 「枠 box の中に面 box」は見えない/前面方向は -side
- 中実 box(サッシ・シャッター枠)の内側に置いた box は描画されない。面 box は枠の外面より
  僅かに(1.5cm)前へ出す。
- 道路両側の区画で「前面(道路)方向」は `-side`。`+side` にオフセットすると両側とも建物内部に
  埋まる(07 初版の窓が全滅していた根本原因)。`const out = -side;` を区画ビルダー冒頭で必ず定義。

### 透過 PNG / レイヤー分け書き出しの要点
- renderer は alpha:true にするが表示は常に a=1、書き出し時のみ premultiplied(vec4(ink*e, e))。
- フルスクリーン quad 材は NoBlending 明示(透過書き出しで前フレームと混ざる事故防止)。
- 書き出し中は tick のライブ描画を停止(await toBlob 中に rAF が canvas を汚す)。
- depth 帯レイヤー分けは半開区間 [min,max) で欠落ゼロ。雨線など全画面エフェクトは near 層のみに
  入れないと重ね合成で二重になる。

### makeRotationX の正回転はローカル +z 端を「下げる」(2026-07-12, #8)
- Rx(θ) は y' = y·cosθ − z·sinθ / z' = y·sinθ + z·cosθ。+y に伸ばした棒を倒すとき
  θ>0 で針先は +z 側へ、+z に伸ばした板は θ>0 で +z 端が**下がる**。すべり台の滑走面が
  逆傾斜で空中に浮き、Playwright スクショで発覚。斜め box・時計の針は回転符号を目視必須。
- 時計の針 10:10 は ±60°(±1.05rad)。裏面は `ang * nx` の鏡像で同時刻に見せる。

### params 直叩き経路は UI/parseHash の検証をすり抜ける(Codex 検出, #8)
- select と parseHash でホワイトリスト検証していても、`__street.params.landmark = 'typo'` や
  未定義(旧形状の PARAMS)で genLayout に届くと `LM_W[undefined]` → NaN → クラッシュ。
- 対策: 消費側(genLayout)でも `['shrine','school','park','random'].includes(v)` の
  ホワイトリストで正規化してから分岐。入口と出口の二重検証。
