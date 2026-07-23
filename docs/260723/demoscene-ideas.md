# Demoscene Series — 実験 10〜17 アイデア集（Opus × Fable 統合版）

**作成**: 2026-07-23（同日、Opus 単独版を Fable 再調査との統合版に改訂）
**背景**: 08 Metaball Field / 09 Flow Field が「スクリーンセーバー的」で漂う系だったため、メガデモらしい速度・衝撃・リズムのある表現に振る。
**経緯**: 同一プロンプトの調査・発想を Opus 4.6 と Fable 5 で各 1 回実施。ユーザー判断は「Opus 版が劣っているわけではない。両方採用」→ 重複を畳んで 8 案に統合（比較検証の記録は末尾）。
**共通制約**: 単一 HTML / Three.js 0.170.0 CDN importmap / ビルドなし

---

## 実施順序（暫定）

| # | タイトル | 核となる表現 | 由来 | 状態 |
|---|---------|-------------|------|------|
| 10 | Neon Tunnel Rush | ビートシンク SDF トンネル高速突破 | 両版の本命が合流 | 公開（2026-07-23・調整継続中） |
| 11 | Kaleido Overdrive | 万華鏡フラクタル・リズム急変 | 両版で独立提案→統合 | 次に着手 |
| 12 | Beat Sphere | ユーザー楽曲 D&D + FFT 反応幾何体 | Opus | 待ち |
| 13 | Geometry Storm | SDF 幾何体の高速モーフ＋爆発 | Opus | 待ち |
| 14 | Cube Storm | InstancedMesh 5万個の隊列変形 | Fable | 待ち |
| 15 | Type Assault | キネティック・タイポグラフィ弾幕 | Fable | 待ち |
| 16 | Fractal Dive | フラクタル無限ズーム | Opus | 待ち |
| 17 | Oldschool Megamix | 古典エフェクト・メドレー（フィナーレ） | Fable | 待ち |

**順序の意図**: 10 でビートクロック基盤（自前シーケンサ）を確立し 11 以降で流用。シェーダー系（10/11）→ メッシュ系（12〜14）→ タイポ（15）→ 上級シェーダー（16）と交互に振り、17 はそれまでの技法を総動員する歴史オマージュのフィナーレ。順序は各実験の完了時に見直してよい。

---

## 設計方針（統合時の決定）

1. **ビート同期は 2 方式を使い分ける**（平均化しない）:
   - **10 など演出主導の実験** = WebAudio で曲を**自前生成**し、シーケンサのクロックそのもので絵を駆動（Fable 調査の提案）。同期ズレが原理的に起きず、音源ファイル 0 個でライセンス素材を gitignore する本リポジトリ方針とも整合。
   - **12 Beat Sphere** = ユーザーが楽曲を D&D → FFT 解析（Opus 調査の提案）。「毎回違う体験」がコンセプトの本体なので FFT が正解。
2. **音の自動再生制限** → 初回クリック必須を「PRESS START」オーバーレイとして演出に転化。内部ビートクロックは無音でも常時走らせ、ミュート時も絵は同期し続ける。
3. **リポジトリの実績と伸びしろ**（Fable 調査のコードベース棚卸しより）:
   - 実績済み: フルスクリーン SDF レイマーチング + smooth min（08）、EffectComposer + ShaderPass（04）
   - 全 9 実験で未経験: **音**・**前進するカメラ**・**ハードカット切替**・**タイポグラフィ** → 本シリーズの主戦場

---

## 10: Neon Tunnel Rush — ビートシンク・レイマーチングトンネル

*Opus「Warp Tunnel」+ Fable「Neon Tunnel Rush」の合体版。両モデルの本命が一致した。*

### コンセプト
自前生成の 130BPM テクノに完全同期して、ネオン SDF トンネルを高速フライスルー。8 小節ごとにトンネル形態がハードカットで切り替わる（円形→六角格子→星形断面→KIFS フラクタル廊下→ワイヤーフレーム峡谷）。速度感・打撃感・切替の快感がメガデモの核。

### 見た目
- 暗闇の中をネオンリングが向かってくる。壁面はフレネル反射でメタリックに光る
- キックの瞬間に FOV パンチ + 色収差スパイク + フラッシュで画面が「殴られる」
- スネアでグリッチスライス。加速区間と溜め区間の緩急
- 8 小節ごとのハードカットで断面形状・色・空間構造が急変

### 技術的な核
- 全画面クアッド + `ShaderMaterial` フラグメントシェーダーのみ（08 の直系発展）
- トンネル SDF: `length(p.xy) - r(p.z, time)`（r を time / セクションで変調→断面変形）
- 蛇行: `p.xy -= path(z)`、無限構造: `mod(p, c) - c/2` のドメインリピート
- リング反復: `fract(p.z - time * speed)`
- Xor 流グロー: レイマーチのステップ距離をそのまま発光に使う（少行数でネオンが出る）
- WebAudio 自前シーケンサ（kick=サイン波ピッチスイープ、hat=ノイズ、bass=saw）が `uBeat`（キック後の減衰 0-1）/ `uBar` / `uSection` uniform を供給
- ポストプロセスはシェーダー内で完結（クロマティックアベレーション = RGB チャネル別 UV オフセット + グリッチ + ビネット）

### インタラクション
- クリック: 音 ON（PRESS START オーバーレイ）
- マウス X: トンネル内の視点オフセット / マウス Y: 速度変化
- 内部クロックは常時走行（無音でも絵は同期）

### 08/09 との差別化
「漂う」→「突き進む」。前進カメラ・打撃感・ハードカット・音同期はすべて Lab 初。アセット 0 個（動画背景すら不要）で git 的にも最クリーン。

### 実装難易度
★★★☆☆ — トンネル単体なら ★★☆（Shadertoy 移植圏）。シーケンサ統合とセクション構成で +1。全プロシージャルなので単一 HTML で完全に現実的。負荷はステップ数と解像度スケールで制御（08 で通った道）。

---

## 11: Kaleido Overdrive — 万華鏡フラクタル・ズーム

*Opus「Kaleidoscope Engine」+ Fable「Kaleido Overdrive」の統合。両版で独立に提案された。*

### コンセプト
画面全体が万華鏡。無限に吸い込まれる万華鏡 + KIFS フラクタル。ビートで対称数（3→6→8→12）・色相・回転方向・ズーム方向が急変し、模様の密度と複雑さがエスカレート。

### 見た目
- 結晶的な幾何学模様が絶え間なく中心へ落下 / 爆発
- ビート瞬間の反転フラッシュとセグメント数チェンジが「キマる」
- 色は時間で回転するパレット。パターンが「割れる」瞬間にグリッチ

### 技術的な核
- 2D フラグメントシェーダーのみ（レイマーチ不要で 8 案中最軽量）
- 万華鏡フォールド: `angle = mod(a, seg); angle = abs(angle - seg*0.5);`（極座標で 1 ウェッジに畳んで鏡映）
- ウェッジ内に `fbm` ノイズ + SDF パターン → 対称コピー
- log ズーム + ping-pong レンダーターゲットのフィードバックでトレイル
- RGB チャネルごとに微妙に異なる対称数 N → 虹色の縁取り（安価な色収差）
- ビートクロックは 10 の機構を流用

### スクリーンセーバー回帰リスクへの対策（Opus 版の注意点を継承）
- 対称数の切り替えは滑らかにせず**バキッと**（ハードカット）
- グリッチ / フラッシュ / 反転を要所に入れてリズムを出す

### 08/09 との差別化
09 の有機ノイズ模様に対し、厳密な幾何学対称 + リズム急変。「個体が動く」のではなく「空間全体がパターンとして変容する」。モバイルでも余裕で 60fps。

### 実装難易度
★★☆☆☆ — フォールドは数行。8 案中最も低リスク。見た目のインパクト対実装コストが最良。

---

## 12: Beat Sphere — 音楽駆動のパルスする幾何体（Opus 案）

### コンセプト
正二十面体が音楽のビートに合わせて爆発的に変形する。低音でスパイク、中音で回転加速、高音でワイヤーフレーム分裂。ユーザーが音楽ファイルを D&D で投入 — **毎回違う体験になることが本体**なので、FFT 解析方式を採る。

### 見た目
- 暗闇に浮かぶメタリック球体。静寂時は滑らかな球
- ビートが来ると頂点が法線方向に突き出してウニのように変形
- 同時にブルームが爆発的に明るくなる。キックで RGB チャネルがズレるグリッチ

### 技術的な核
- `IcosahedronGeometry(1, 5)` の頂点を simplex noise × audioLevel で法線方向に変位
- Web Audio API `AnalyserNode` → FFT バンド分割（低/中/高）→ uniform 3 本
- ビート検出: 低周波の `current > average * 1.5` で `beatPulse` → カメラシェイク + ブルーム強度パルス
- 精度が要るなら web-audio-beat-detector ライブラリも選択肢（Fable 調査より補強）
- `material.wireframe` トグルで高音時にワイヤー表示（モーフ追従する）

### インタラクション
- 音楽ファイル D&D（`<input type="file">` フォールバック）
- デフォルト音源は内蔵しない代わりに、10 の自前シーケンサを無音デモモードとして流用可
- PRESS START パターンは 10 と共通

### 08/09 との差別化
自律的に漂う無主体の運動 → 音楽という外部入力に「叩かれる」リアクティブな運動。

### 実装難易度
★★★☆☆ — FFT 取得は定型的。ビート検出のチューニングがやや手間。

---

## 13: Geometry Storm — SDF 幾何体の高速モーフ＋爆発（Opus 案）

### コンセプト
SDF で定義された幾何学プリミティブ（球→立方体→トーラス→八面体→メビウス帯…）が高速でモーフィングし、変形の瞬間にパーティクルが爆発的に飛散する。メガデモの「形状ショーケース」現代版。

### 見た目
- 画面中央に光沢のある幾何体が浮かぶ
- 2-3 秒ごとに次の形状へ爆発的に変形
- 変形中は表面が砕け散り、粒子が飛び、新しい形が凝集する
- 背景は dark + subtle grid

### 技術的な核
- レイマーチングで SDF シーン描画（08 の延長）
- `mix(sdfA(p), sdfB(p), smoothstep(t))` で形状間モーフ
- 変形の「中間状態」で smooth min の閾値を広げ → 形が溶ける
- 変形完了時にパーティクルバースト（Three.js Points で別レイヤー）
- カメラはゆっくり周回 + 変形時にズームイン

### SDF プリミティブ候補
球 `sdSphere` / 立方体 `sdBox` / トーラス `sdTorus` / 八面体 `sdOctahedron` / カプセル `sdCapsule` / 六角柱 `sdHexPrism` / メビウス帯（パラメトリック）

### 08 との差別化
08 はメタボールの「融合」が主題。こちらは「次から次へ形が変わる」速度感。1 つの形に留まらない。パーティクル爆発が衝撃を加える。

### 実装難易度
★★★☆☆ — SDF モーフは 08 の知見が活きる。パーティクルバーストとの同期がやや手間。

---

## 14: Cube Storm — インスタンス群の隊列変形（Fable 案）

### コンセプト
5 万個のキューブ群が波→螺旋→トンネル→文字ロゴへとビートで瞬時に再構成され、カメラが群れの中を突き抜ける。

### 見た目
- 群体が一斉に隊列を組み替える「ドンッ」という快感
- ライト + 影 + フレネル発光で Three.js らしい立体感

### 技術的な核
- `InstancedMesh` + 頂点シェーダーで formation A→B を uniform mix モーフ
- 各 formation は起動時にコード生成した attribute（波・螺旋・トンネル・ロゴ点群）
- カメラは Catmull-Rom スプラインを高速走行
- ビートで mix 目標を切替（10 のクロック機構を流用）

### 08/09 との差別化
08（SDF 面）・09（2D 点）と違う「実体メッシュの大群」。シーングラフ・ライティングという Three.js 本来の強みを使う唯一の案。

### 実装難易度
★★★★☆ — 技術は素直だが、formation デザインとモーフの絵作りに調整反復が要る。

---

## 15: Type Assault — キネティック・タイポグラフィ弾幕（Fable 案）

### コンセプト
巨大な単語（実験タイトル・"THREE.JS LAB"・デモ定番の GREETINGS 等）が 3D 空間に撃ち込まれ、カメラが文字の隙間を疾走する。意味とリズムの結合はデモ文化の中核（greetings / scrolltext）。

### 見た目
- 奥から飛来した文字がカメラすれすれを通過
- ビートで次の語がスタンプされ、旧語はグリッチ崩壊
- 下部に古典 sin スクローラのリボン

### 技術的な核
- 欧文: `TextGeometry`（helvetiker JSON を CDN から）
- 日本語: フォント容量問題（TTF 数 MB 級）があるため **canvas テクスチャ板が前提**
- motion trail: AfterimagePass か手書きフィードバック
- ShaderPass で RGB シフト（04 の ShaderPass 実績の経路）
- 高品質が欲しければ troika-three-text（SDF、TTF 直読み）も選択肢

### 08/09 との差別化
Lab 初の「読める」要素。抽象形状ではなく言語がモチーフ。

### 実装難易度
★★★☆☆ — 文字の配置・カメラパスの絵作り調整に時間がかかる。

---

## 16: Fractal Dive — フラクタル無限ズーム（Opus 案）

### コンセプト
Mandelbrot / Julia 集合へ自動で無限ズームし続ける。ズーム速度は加速→減速を繰り返し、「穴」に吸い込まれる瞬間にカメラシェイクとグリッチ。カラーパレットが時間で回転。

### 見た目
- 宇宙的な色彩のフラクタル構造が、画面中央の「穴」に向かって吸い込まれるように拡大し続ける
- self-similar な構造が現れるたびに色が変わり、スケール感覚が破壊される

### 技術的な核
- 全画面フラグメントシェーダーで `z = z² + c` の反復回数を計算 → カラーマッピング
- ズーム: `scale *= 1.001` 毎フレーム / 中心は事前計算した「面白いポイント」（Misiurewicz 点）へ順次移動
- 倍精度問題: float の限界（〜10^15 倍）でノイズ → 2 つの float で 1 つの double を表現するエミュレーション / perturbation theory

### 段階的実装
1. MVP: 浅いズーム + パレット回転（float 精度で十分）
2. 拡張: 倍精度エミュレーション → 深いズーム
3. 応用: Julia の c をマウスで操作

### 08/09 との差別化
有限空間内の運動 → 無限のスケール変化。自己相似性はメガデモの定番。

### 実装難易度
★★☆☆☆（浅いズーム MVP）/ ★★★★☆（深いズーム倍精度）

---

## 17: Oldschool Megamix — 古典デモエフェクト・メドレー（Fable 案・フィナーレ）

### コンセプト
プラズマ→コッパーバー→ロトズーマー→ツイスター→ドットトンネル→スターフィールド、と 8 小節ごとに古典エフェクトを高速メドレー、ラストは全部同時。1990 年代 Amiga デモへのオマージュ。シリーズ最終回として、それまでに作った技法（ビートクロック・グリッチ・スクローラ）を総動員する。

### 見た目
- レトロパレット + CRT 質感（スキャンライン・にじみ）
- ハードカットとフラッシュで切替。下部スクローラが常時流れる

### 技術的な核
- 1 枚のフラグメントシェーダーに scene index uniform で全エフェクト同居（各 20〜40 行の古典数式）
- スクロールテキストは canvas テクスチャ
- 参考実装は seancode.com/demofx / sizecoding.org に全部ある

### 差別化と注意
「切替の快感」が主役で 08/09 の対極。1 エフェクトずつ独立して書けるので進捗が刻める＝制作リスク最小のメガデモ。ただし見た目の新規性は低め（再現ネタ）なので「歴史メドレー」という文脈付けが命。

### 実装難易度
★★☆☆☆〜★★★☆☆ — 個々は簡単、数があるだけ。

---

## 共通で使う技法メモ

### WebAudio 自前シーケンサ（10/11/14 等の駆動源・Fable 調査）
```js
// 130BPM、lookahead 100ms で先読みスケジュール
const BPM = 130, spb = 60 / BPM;
let nextNote = 0;
function tick() {
  while (nextNote < ctx.currentTime + 0.1) {
    scheduleKick(nextNote);        // sin ピッチスイープ
    beatTimes.push(nextNote);
    nextNote += spb;
  }
}
// 描画側: uBeat = exp(-(now - lastBeatTime) * 6.0)  ← キック後の減衰 0-1
```
- kick = サイン波ピッチスイープ / hat = ノイズ / bass = saw
- 音は初回クリック必須（自動再生制限）→ PRESS START オーバーレイに転化
- 無音でも内部クロックは走らせ、絵の同期は維持

### FFT ビート検出（12 用・Opus 調査）
```js
const analyser = audioCtx.createAnalyser();
analyser.fftSize = 256;
const data = new Uint8Array(analyser.frequencyBinCount);
// 低周波帯 (0-10) の平均を取り、直近平均の 1.5 倍超えでビート
```

### クロマティックアベレーション（シェーダー内完結）
```glsl
vec3 ca(sampler2D tex, vec2 uv, float amount) {
    return vec3(
        texture2D(tex, uv + vec2(amount, 0.0)).r,
        texture2D(tex, uv).g,
        texture2D(tex, uv - vec2(amount, 0.0)).b
    );
}
```

### 万華鏡フォールド（11 用）
```glsl
float a = atan(uv.y, uv.x);
float seg = 6.28318 / float(N);
a = mod(a, seg);
a = abs(a - seg * 0.5);   // 1 ウェッジに畳んで鏡映
```

### SDF プリミティブ / 演算（iquilezles.org 準拠）
- `sdSphere(p, r)` = `length(p) - r`
- `sdBox(p, b)` = `length(max(abs(p)-b, 0.0))`
- `sdTorus(p, t)` = `length(vec2(length(p.xz)-t.x, p.y)) - t.y`
- トンネル = `r - length(p.xy)` + `p.xy -= path(z)` 蛇行
- ドメインリピート = `mod(p, c) - c/2`
- `opSmoothUnion(d1, d2, k)` = 08 で使用済み
- Xor 流グロー = レイマーチのステップ距離をそのまま発光に加算

### カラーパレット（cosine gradient）
```glsl
vec3 palette(float t) {
    vec3 a = vec3(0.5); vec3 b = vec3(0.5);
    vec3 c = vec3(1.0); vec3 d = vec3(0.0, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}
```

---

## 比較検証記録（Opus 4.6 vs Fable 5・2026-07-23）

メインモデルを Opus 4.6 → Fable 5 に切り替えたタイミングで、同一プロンプトの調査・発想を再実行して差を検証した。

### 実験条件
- プロンプトは一言一句同一。Fable 側のみ末尾に 2 行追記（新規エージェントで会話文脈を持たないため「リポジトリの 08/09 を読んでよい」「過去のアイデア資料に依存しない」）
- 条件差の注記: Opus 回はフォーク（会話文脈を継承）、Fable 回は新規エージェント。差の一部はこの条件差に由来する可能性がある
- 汚染防止のため、Fable 回の実行中は Opus 版ドキュメントをリポジトリ外へ一時退避した
- advisor はこの会話では利用不可だったため、両回とも advisor 検証は含まれない

### 結果の対応

| 系統 | Opus 版 | Fable 版 |
|---|---|---|
| トンネル疾走 | Warp Tunnel（本命） | Neon Tunnel Rush（本命・音同期を統合） |
| 万華鏡 | Kaleidoscope Engine | Kaleido Overdrive |
| 音反応 | Beat Sphere（単体案） | 独立案なし（トンネルに吸収） |
| SDF モーフ | Geometry Storm | — |
| フラクタルズーム | Fractal Dive | —（万華鏡に KIFS として部分吸収） |
| タイポグラフィ | — | Type Assault |
| 古典メドレー | — | Oldschool Megamix |
| メッシュ群体 | — | Cube Storm |

### 質的な違い
1. **調査の起点**: Opus は Web 調査中心。Fable はまずリポジトリの実績/未経験を棚卸し（音・前進カメラ・ハードカット・タイポが未経験）してから差分駆動で発想
2. **ビートシンクの設計判断**: Opus = FFT 解析（チューニングが手間と自認）。Fable = 曲の自前生成 + クロック駆動（同期原理的に完璧・アセット 0・gitignore 方針と整合）
3. **時間構成への踏み込み**: Opus = 単体エフェクトのカタログ。Fable = 8 小節切替・緩急・PRESS START・スクローラなど「1 本のデモとしての時間設計」
4. **技術系統の幅**: Opus はほぼ全案フラグメントシェーダー系。Fable は InstancedMesh・タイポなどシーングラフ系も含む
5. **出典**: Opus 5 件（Codrops / Shadertoy 中心）。Fable 17 件（pouët / Demozoo / Revision 2025 結果 / Xor 2025 記事 / LYGIA / bytebeat など一次寄り）
6. **コスト**: Opus 183k tokens / 16 tools / 203 秒。Fable 99k tokens / 18 tools / 326 秒

### 裁定
ユーザー判断（2026-07-23）: **優劣ではなく相補**。Opus 版は単体エフェクトとしての具体性と即実装可能なカタログ性、Fable 版は文脈駆動の構成設計と音方式の転換に強み。**両方採用**し本統合版を作成。ビート同期方式のみ対立したため「10=自前生成 / 12=FFT」と実験ごとに使い分けて解決（平均化しない）。

---

## 参考資料（両版統合）

### SDF / レイマーチング
- [Inigo Quilez — SDF/raymarching 正典](https://iquilezles.org/) / [SDF プリミティブ集](https://iquilezles.org/articles/distfunctions/)
- [Raymarching Material 101](https://blog.anaili.fr/articles/raymarching-material) — Three.js で SDF レイマーチング
- [srtuss 系トンネル (Shadertoy)](https://www.shadertoy.com/view/4d2yRm) / [Kali — Fractal Land 派生](https://www.shadertoy.com/view/ltyXR1)
- [Xor — Turbulence (GM Shaders, 2025)](https://mini.gmshaders.com/p/turbulence) / [Raymarching](https://mini.gmshaders.com/p/gm-shaders-mini-raymarching-1351092)
- 08-metaball-field.html — SDF レイマーチング、smooth min の実装実績

### オーディオ
- [Codrops — 3D Audio Visualizer with Three.js, GSAP & Web Audio API (2025-06)](https://tympanus.net/codrops/2025/06/18/coding-a-3d-audio-visualizer-with-three-js-gsap-web-audio-api/)
- [Codrops — Audio-Reactive Particles in Three.js (2023)](https://tympanus.net/codrops/2023/12/19/creating-audio-reactive-visuals-with-dynamic-particles-in-three-js/)
- [greggman/html5bytebeat](https://github.com/greggman/html5bytebeat) / [Bytebeat composer](https://dollchan.net/bytebeat/)

### 万華鏡 / ポストプロセス / タイポ
- [LYGIA — kaleidoscope](https://lygia.xyz/space/kaleidoscope) / [Daniel Ilett — Crazy Kaleidoscopes](https://danielilett.com/2020-02-19-tut3-8-crazy-kaleidoscopes/)
- [pmndrs/postprocessing (Glitch / ChromaticAberration)](https://github.com/pmndrs/postprocessing)
- [Codrops — Kinetic Typography with Three.js (2020)](https://tympanus.net/codrops/2020/06/02/kinetic-typography-with-three-js/)
- [troika-three-text](https://protectwise.github.io/troika/troika-three-text/)

### デモシーン文化 / 古典エフェクト
- [Revision 2025 results (pouët)](https://www.pouet.net/party_results.php?which=1550&when=2025&font=1) / [Demozoo — Revision 2025](https://demozoo.org/parties/5222/)
- [オールドスクール・エフェクト集 (seancode)](https://seancode.com/demofx/) / [sizecoding.org 疑似コード集](http://www.sizecoding.org/wiki/Design_Tips_and_Demoscene_effects_with_pseudo_code) / [mkhj/Demoscene-effects (WebGL)](https://github.com/mkhj/Demoscene-effects)
