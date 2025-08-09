# n8n 料金・ホスティングまとめ

## 1. n8n Cloud（公式クラウド）
- **Starter**: \$24/月（2,500回まで）  
- **Pro**: \$60/月（10,000回まで）  
- **長所**: サーバー管理不要・すぐ利用可能  
- **短所**: 実行回数に上限あり、大量利用は割高  

## 2. セルフホスト（コミュニティ版）

運用前提（公開/非公開）でコスト構造が変わる。

### 2-1. 非公開アクセス（IAP/ローカル）
- 概要: インターネットに公開せず、IAPトンネルやローカルからだけアクセス。
- コストの傾向: VM（例: e2‑micro, 30GB）＋少量の送信トラフィックのみ。Google Cloud Free Tier（無料枠）に収まりやすい。
- 注意: Webhook 等で外部サービスから直接受信は不可（別途プロキシやトンネルが必要）。

### 2-2. 公開アクセス（独自ドメイン/HTTPS）
- 概要: 独自ドメインで常時公開（例: Traefik + Let’s Encrypt）。
- コストの傾向:
  - 外部IPv4: インターネットからアクセス可能なIPアドレス。常時公開が必須。Free Tier対象のe2-microに紐づく**使用中**の外部IPv4は無料。※Free Tier外のインスタンスや追加IP、未使用IPは課金対象
  - 送信トラフィック（Egress）: 無料枠（例: 約1GB/月）超過分が従量課金。
  - 付帯サービス: Cloud Build/Secret Manager/Cloud Logging は利用量に応じて課金。
- 留意点
  - 小規模は SQLite 永続ボリュームで十分。本格運用は外部DB（PostgreSQL）推奨。

※ Google Cloud Free Tier（Free tier eligible products）とは
- 公式: https://cloud.google.com/free
- 概要: Google Cloud の恒常的な無料枠（90日間の Free Trial とは別）。各プロダクトに月間の無料利用枠が定義され、枠内は $0、超過は通常料金。
- 代表例: Compute Engine の e2‑micro（対象リージョン）、30GB の標準永続ディスク、少量の送信トラフィック（Egress）など。
- 適用条件: 対象リソース/リージョン/マシンタイプに限定（例: US リージョンでの e2‑micro と 30GB 標準ディスク）。
- 補足: 無料枠は同一課金アカウント内で共有。条件や金額は変更されうるため最新の公式情報を参照。

## 3. セルフホスト（Businessプラン）
- **€667/月（年契約）〜、実行回数制限あり**  
- エンタープライズ機能（SSO, Git連携など）が利用可能  
- インフラ費用に加え、実行回数ベースで課金される  

---

## 拡張性（Cloud と セルフホストの違い）
- **Cloud**: コンテナ/OS へのパッケージ追加や任意バイナリの持ち込みは不可。`Execute Command` ノードは利用不可のため、ネイティブ依存（例: PDF 変換用の LibreOffice/Chromium など）は原則外部 API 連携で対応。 
  - バイナリ: コンテナ内で実行するコマンドや実行ファイルのこと（例: `ffmpeg`, `libreoffice`）。  
  - 代表的な追加パッケージ例  
    - 文書/PDF 変換: LibreOffice, Pandoc, Ghostscript  
    - PDF OCR/最適化: ocrmypdf（+ Tesseract 言語データ）, poppler-utils（pdftotext 等）, qpdf  
    - HTML→PDF/ブラウザ: Chromium（+ フォント）, wkhtmltopdf, WeasyPrint   
- **セルフホスト（Community/Business 共通）**: Docker イメージ拡張で OS パッケージやフォント・バイナリを追加可能。`Execute Command` ノードやコミュニティ/カスタムノードの導入ができ、ネイティブ依存の処理を内製化しやすい。Business はガバナンス/SSO/Git 等が加わるが、拡張性そのものは Community と同等（自前運用前提）。  

## 用途別おすすめ

| 利用方法 | 適したケース |
| --- | --- |
| **Cloud** | 手軽に始めたい個人・小規模チーム |
| **セルフホスト（非公開/IAP）** | 個人利用・検証・学習、閉域で十分なケース |
| **セルフホスト（公開/独自ドメイン）** | 外部からの利用・Webhook受信が必要 |
| **セルフホスト（Businessプラン）** | SSOや高度機能（Git/監査など）が必要な組織 |

---
