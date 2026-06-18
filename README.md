# Three.js Lab

Three.jsを使ったビジュアル実験のプレイグラウンド。

**公開URL:** https://threejs-lab-ashen.vercel.app/

---

## 目的

- Three.jsの機能を気軽に実験・プロトタイプする場
- 実験ごとに独立したHTMLファイルとして管理
- GitHub push → Vercel自動デプロイで即公開

---

## 構成

```
threejs-lab/
├── index.html               # 実験一覧（カード形式ポータル）
├── 01-rotating-cube.html    # 基本: 回転するキューブ
├── 02-photo-terrain.html    # 画像地形化: 明暗を高さにした3Dレリーフ
├── 03-mona-lisa-warp.html   # 画像ワープ: マウスで引きずる頂点バネ物理
├── 04-emergent-portrait.html # 浮上する肖像: スクロールで2D写真→3D肖像
├── 05-emergent-life.html    # 生命の輪: スクロールで卵→ヒト→魚→卵を巡る連番スクラブ
├── assets/                  # 画像素材・フレーム連番（一部 .gitignore 対象。下記参照）
└── README.md                # このファイル
```

### 画像素材と .gitignore

画像のライセンスで扱いを分けている:

- **`02-photo-terrain.html`** の初期画像 `assets/02-portrait.jpg` は Adobe Stock 等の
  ライセンス素材なので **公開リポジトリで再配布しない**ため `.gitignore` 済み。公開版
  （Vercel）では 404 になり、自動で **プロシージャル生成の地形**にフォールバックする。
- **`03-mona-lisa-warp.html`** の初期画像 `assets/03-mona-lisa.jpg` は
  **パブリックドメイン**（Wikimedia Commons / Leonardo da Vinci, C2RMF retouched）なので
  リポジトリに**同梱**し、公開版でもそのまま表示する。

どちらも手元の画像を**ドラッグ&ドロップ**で差し替えられるので、ツールとして成立する。

- **`04-emergent-portrait.html`** の素材は**生成AI製**（画像: nano banana pro、3D化: Tripo3D、
  動画: Seedance 2.0 i2v）なのでリポジトリに同梱する。ただし重い中間素材（原寸PNG・無圧縮GLB・
  生成直後のmp4）は `.gitignore` し、**最適化済みの配信用**（`04-portrait.glb` = Draco 圧縮 1.75MB /
  `04-backdrop.webp` = 78KB / 動画 `04-backdrop.mp4` 327KB + `04-backdrop-empty.mp4` 501KB +
  `04-backdrop-scream.mp4` 1.30MB / ベイクAO `04-portrait-ao.webp` 108KB）だけをコミットしている。
- **`05-emergent-life.html`** の素材も**生成AI製**（キーフレーム: nano banana pro、モーフ遷移:
  Seedance 2.0 FLF2V、各生命段のアクション: Seedance i2v＋一部ローカル ComfyUI / Wan2.2 i2v）。
  配信用は**スクラブ用の連番フレーム** `assets/05-frames/*.webp`（846枚・約17MB）＋
  `assets/05-frames/manifest.json` だけをコミットする。重い中間素材 — 生成 mp4・クリップ連番
  （`assets/05-src/`）とキーフレーム原寸PNG（`docs/260614/keyframes/`・`docs/260615/keyframes/`）—
  は `.gitignore` 済み。manifest が 404 の環境ではプロシージャルな卵→胎児モーフに自動フォールバック
  する（ライセンスフリーで成立）。

### ファイル命名規則

```
NN-kebab-case-title.html
```

例: `02-particle-system.html`, `03-shader-wave.html`

---

## 技術スタック

- **Three.js** (CDN / importmap) `https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js`
- ビルドツールなし。ローカルは HTTP サーバー経由で閲覧（下記「ローカルで動かす」）
- GitHub → Vercel 自動デプロイ

> ⚠️ `file://` での直開きは不可。importmap の CDN モジュール読み込みと、`02` の canvas
> ピクセル取得（同一オリジン制約）が `file://` では失敗するため、必ずローカルサーバー経由で開く。

---

## ローカルで動かす

```bash
# プロジェクト直下で HTTP サーバーを起動（Windows は py ランチャー）
py -m http.server 8000
#   → ブラウザで http://127.0.0.1:8000/ を開く（index.html の一覧から各実験へ）
#   停止は Ctrl+C
```

- `02-photo-terrain.html` はローカルの `assets/02-portrait.jpg`（`.gitignore` 済み・原寸）を
  初期表示する。別の画像を試すときは画面に**ドラッグ&ドロップ**するだけ。
- 初期画像が無い環境（clone 直後・公開版）では自動でプロシージャル地形にフォールバックする。

---

## 開発ワークフロー

```bash
# 1. 新しい実験ファイルを作成
#    例: 02-particle-system.html

# 2. index.html のカード一覧に追記

# 3. デプロイ
git add .
git commit -m "Add: 実験タイトル"
git push
# → Vercel が自動ビルド＆デプロイ
```

---

## 実験一覧

| # | ファイル | 内容 | 状態 |
|---|---|---|---|
| 01 | `01-rotating-cube.html` | 回転するキューブ（基本ライティング） | ✅ 完成 |
| 02 | `02-photo-terrain.html` | 画像地形化（明暗→高さのレリーフ／マウス追従ライト／OrbitControls／画像D&D） | ✅ 完成 |
| 03 | `03-mona-lisa-warp.html` | 画像をマウスで引きずって歪ませる頂点バネ物理（中村勇吾 tha オマージュ／グリッド可視化／画像D&D） | ✅ 完成 |
| 04 | `04-emergent-portrait.html` | 浮上する肖像: スクロールでグリッチの嵐とともに写真の人物が消え、同じ場所に3D肖像が浮上（生成AI→Tripo3D／写真頭部への投影アンカー／人物なし背景へスワップ／キー1-4で質感切替: 石膏・ワイヤー・点群・版画／背景は Seedance i2v の「生きた写真」: 瞬き・呼吸・窓の光芒、嵐の中で人物が声なき絶叫へ変貌する10秒テイクオーバー付き） | ✅ 完成 |
| 05 | `05-emergent-life.html` | 生命の輪: スクロールで 卵→桑実胚→胚→胎芽→赤ん坊→子供→大人→哺乳類→爬虫類→両生類→魚→卵 を一巡する手描きセル調の連番スクラブ（846フレーム webp・窓ロードで VRAM 固定／個体発生↔系統発生の反復／**人間アークは自意識の目覚めの物語**: 赤ん坊が泣く→子供が両手を上げて跳び→跳んだポーズのまま大人へ成長→きょろきょろ見渡し→ハッと気づき身を隠し→胎児のように丸まって座り込む／**動物アーク**: ゴリラが胸を叩き伸びをして寝転ぶ→トカゲが舌を出しカサカサ這う→カエルが高く跳ねて頭から水面にダイブ（波紋）→魚が泳ぐ→卵へ還る／純2D・どの画面比でも見切れない contain 収納／スクロール連動の薄い色グレードで 暖→冷→暖 と色でも輪を閉じる・赤い生命コアが通奏低音） | ✅ 完成 |

---

## 次にやること

- [x] OrbitControls など追加ライブラリの導入パターンを確立（`02` で `three/addons/` を importmap 追加）
- [x] `03-mona-lisa-warp` 追加（頂点バネ物理によるマウスドラッグ歪み／中村勇吾オマージュ）
- [x] `04-emergent-portrait` 追加（生成AI画像 → Tripo3D → スクロールで2D→3D遷移）
- [x] `04` Phase 2: Seedance で backdrop を image-to-video 化（まばたき・呼吸・髪の微動＋empty room の光芒）し VideoTexture で組み込み
- [x] `05-emergent-life` 追加（手塚調の生命循環ループ：卵→桑実胚→胚→胎芽→赤ん坊→子供→大人→哺乳類→爬虫類→両生類→魚→卵 で色とともに閉じる輪。11モーフ＋アクション＝846フレーム webp・窓ロード・純2D・contain・スクロール連動の薄い色グレード。人間アークは自意識の目覚め(子供の歓喜のジャンプ→大人→羞恥で座り込む)、動物アークは ゴリラ胸叩き→寝転ぶ→トカゲ→カエル高ジャンプ＆頭からダイブ(波紋)→魚 で卵へ還る。全アクション/モーフをローカル ComfyUI/Wan2.2 i2v＋firstlast で 0cr 生成）
- [x] `05` smear クリーンアップ＋磨き込み（2026-06-17）: ローカル Wan i2v の手足smear（動きピークで腕/尾/脚が画面端まで棒・柱化・×3ループで反復）を **Seedance 2.0 FLF2V** で動物7クリップ再生成（frog_hop / gorilla_chest / gorilla_lie / lizard / clip8 / clip10 / frog_dive）。フレームの**キャッシュバスター**（manifest `ver`＋URLの`?v=`）実装でフレーム差し替えが自動反映。デバッグ用パラメータパネル削除（値は調整済みで固定）。詳細 `docs/260617/STATUS.md` / `tasks/lessons.md`
- [ ] **`05` を commit / push**（ユーザー明示時のみ → Vercel 自動公開）
- [ ] `index.html` のサムネイルを実際のキャプチャ画像に差し替え（任意）
- [ ] （任意）`05` 下部キャプションの `846 real frames (windowed)` タグ削除（情報表示のため現状残置）
- [ ] `02` 改良案: 高さマップ用のぼかしを表示テクスチャと分離 / 等高線オーバーレイ / スクロール連動の立ち上がり
- [ ] `03` 改良案: SEG_X を上げる場合は `pos.array` 直接アクセスに切替（getX/setX のコスト回避）
