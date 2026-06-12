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
├── assets/                  # 画像素材（一部 .gitignore 対象。下記参照）
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

- **`04-emergent-portrait.html`** の素材は**生成AI製**（画像: nano banana pro、3D化: Tripo3D）
  なのでリポジトリに同梱する。ただし重い中間素材（原寸PNG・無圧縮GLB）は `.gitignore` し、
  **最適化済みの配信用**（`04-portrait.glb` = Draco 圧縮 1.75MB / `04-backdrop.webp` = 78KB）
  だけをコミットしている。

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
| 04 | `04-emergent-portrait.html` | 浮上する肖像: スクロールでグリッチの嵐とともに写真の人物が消え、同じ場所に3D肖像が浮上（生成AI→Tripo3D／写真頭部への投影アンカー／人物なし背景へスワップ／キー1-4で質感切替: 石膏・ワイヤー・点群・版画） | ✅ 完成 |

---

## 次にやること

- [x] OrbitControls など追加ライブラリの導入パターンを確立（`02` で `three/addons/` を importmap 追加）
- [x] `03-mona-lisa-warp` 追加（頂点バネ物理によるマウスドラッグ歪み／中村勇吾オマージュ）
- [x] `04-emergent-portrait` 追加（生成AI画像 → Tripo3D → スクロールで2D→3D遷移）
- [ ] `04` Phase 2: Seedance で backdrop を image-to-video 化（まばたき・呼吸・髪の微動）し動画レイヤーを組み込む
- [ ] `05-` 次の実験テーマを決めて追加（パーティクル分解 / シェーダー波形 など）
- [ ] `index.html` のサムネイルを実際のキャプチャ画像に差し替え（任意）
- [ ] `02` 改良案: 高さマップ用のぼかしを表示テクスチャと分離 / 等高線オーバーレイ / スクロール連動の立ち上がり
- [ ] `03` 改良案: SEG_X を上げる場合は `pos.array` 直接アクセスに切替（getX/setX のコスト回避）
