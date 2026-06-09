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
├── index.html              # 実験一覧（カード形式ポータル）
├── 01-rotating-cube.html   # 基本: 回転するキューブ
├── 02-photo-terrain.html   # 画像地形化: 明暗を高さにした3Dレリーフ
├── assets/                 # 画像素材（.gitignore 対象。下記参照）
└── README.md               # このファイル
```

### 画像素材と .gitignore

`02-photo-terrain.html` はローカルでは `assets/02-portrait.jpg` を初期画像として読み込むが、
これは Adobe Stock 等のライセンス素材を **公開リポジトリで再配布しない**ため `.gitignore` 済み。
公開版（Vercel）では初期画像が 404 になり、自動で **プロシージャル生成の地形**にフォールバックする。
誰でも手元の画像を**ドラッグ&ドロップ**すれば地形化できるので、ツールとして成立する。

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

---

## 次にやること

- [x] OrbitControls など追加ライブラリの導入パターンを確立（`02` で `three/addons/` を importmap 追加）
- [ ] `03-` 次の実験テーマを決めて追加（パーティクル分解 / シェーダー波形 / 物理など）
- [ ] `index.html` のサムネイルを実際のキャプチャ画像に差し替え（任意）
- [ ] `02` 改良案: 高さマップ用のぼかしを表示テクスチャと分離 / 等高線オーバーレイ / スクロール連動の立ち上がり
