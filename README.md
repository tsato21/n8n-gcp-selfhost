# n8n GCP Self-host

## 1. n8nとは
n8n は OSS のワークフロー自動化ツール。
- ワークフロー自動化: 複数のサービス間でのデータ連携や処理を自動化する仕組み
 - クラウド版とセルフホストの違いは[こちら](doc/n8n-pricing-and-hosting.md)を参照。

## 2. 当該リポジトリについて
- GCP のリソースで n8n をセルフホスト（コミュニティ版）
  - [doc/n8n-pricing-and-hosting.md](doc/n8n-pricing-and-hosting.md) > `2-2. 公開アクセス`で構築
- Terraform で GCP 環境を構築
- デプロイは Cloud Build（タグ push で自動）→ VM に SSH → `cicd/docker-compose.yml` 起動
- アーキテクチャー概要: [doc/architecture.mmd](doc/architecture.mmd) 
- セキュリティ対策概要: [doc/security-measurement.md](doc/security-measurement.md) 
- トラブルシューティング概要: [doc/troubleshooting.md](doc/troubleshooting.md) 

## 3. 事前準備（詳細）
3.1 GCP プロジェクト作成と課金有効化
- GCP コンソールで新規プロジェクトを作成
- 請求（Billing）を有効化

3.2 開発ツールの準備
必要ツールの概要：
  - **gcloud**: Google Cloudのコマンドラインツール
  - **Terraform**: インフラをコードで管理するツール
  - **httpd**: Basic認証用パスワードハッシュ生成に使用

手順（macOS ターミナル）
1. gcloud をインストール: `brew install --cask google-cloud-sdk`
2. gcloud を初期化: `gcloud init`
3. ADC 認証を有効化: `gcloud auth application-default login`
4. Terraform をインストール: `brew install terraform`
5. `httpd` をインストール: `brew install httpd`

3.3 Terraform 実行者の IAM 権限
以下いずれかを自身のアカウントに付与
- シンプル: プロジェクトの Owner（推奨はしないが簡単）
- 最小構成の例（推奨）:
  - `roles/resourcemanager.projectIamAdmin`（プロジェクト IAM 付与のため）
  - `roles/compute.admin`
  - `roles/iam.serviceAccountAdmin`
  - `roles/secretmanager.admin`
  - `roles/cloudbuild.editor`

3.4 GitHub と Cloud Build の連携
- Cloud Build > トリガー > リポジトリ接続 > 当該リポジトリとCloud Buildを接続

3.5 Basic 認証の準備
- 目的: n8n UIへのアクセス時に Basic 認証を実装しているため
1. パスワードハッシュを生成: 
  - 例) `htpasswd -nbB admin 's3cr3t!'` => `admin:$2y$05$Qkz0Ck...`
2. 生成された値をメモで控えておく。(※後述の作業で使用する)

3.6 Cloud Build 用 SSH キーの作成・配置
- 目的: Cloud Build から VM へ IAP 越しに SSH するための鍵を事前生成

1. Terraform ディレクトリへ移動
   - `cd terraform`

2. SSH 鍵ペアを生成（パスフレーズなし推奨）
   - `ssh-keygen -t rsa -b 4096 -C "cloudbuild-sa" -f cloudbuild-ssh-key -N ''`
   - 生成物と保存場所:
     - 秘密鍵: `terraform/cloudbuild-ssh-key`
     - 公開鍵: `terraform/cloudbuild-ssh-key.pub`

※公開鍵は、VM のメタデータに登録し、秘密鍵: Secret Manager に格納する。

※鍵は定期的にローテーションが必要。ローテーション時は、既存の`terraform/cloudbuild-ssh-key*` を削除した上で、上記コマンドを実行。

## 4. 環境構築

4.1 GCP 環境（Terraform）

| 手順 | 初回 | 2回目以降 |
|---|---|---|
| tfvars 作成/編集 | `cp terraform/example.tfvars terraform/xxx.tfvars` で作成し、環境値を設定 | 変更がある場合のみ編集 |
| 作業ディレクトリへ移動 | `cd terraform` | 同左 |
| 初期化 | `terraform init` | 原則不要（プロバイダ更新時は再実行） |
| 差分確認 | `terraform plan -var-file=xxx.tfvars`（任意） | コマンドは同左。実行推奨。 |
| API 先行有効化 | `terraform apply -target=google_project_service.services -var-file=xxx.tfvars -auto-approve`**（反映まで数分待機）** | 新しい API を追加した場合のみ同様に実行 |
| 全体適用 | `terraform apply -var-file=xxx.tfvars -auto-approve` | `terraform apply -var-file=xxx.tfvars -auto-approve` |
| Outputs 確認 | `vm_ip` をメモ（後続の DNS 設定で使用） | 必要に応じて確認 |
| Rootディレクトリに戻る | `cd ..` | 同左 |

4.2 DNS 設定（初回のみ）

1. 任意の DNS プロバイダでドメイン取得
2. Aレコード追加（`<subdomain>.<domain>`、`vm_ip`を設定）
3. [DNS Checker](https://dnschecker.org/) 等で伝搬確認

## 5. デプロイ
1. デプロイ（タグ push）
- 例（macOS ターミナル）
  ```bash
  git tag v1.0.0 && git push origin v1.0.0
  ```

2. 動作確認
- `https://<subdomain>.<domain_name>` にアクセス
- Basic 認証 → n8n画面に遷移 → （初回のみ） サインアップ

3. 2FA(二要素認証)の有効化（初回のみ）
- 手順: n8n UI → Profile → Two‑Factor Authentication → QR を認証アプリ（Google Authenticator/1Password/Authy 等）で登録 → 6桁コード入力 → バックアップコード保存。

## 6. n8n コンテナの拡張
- ワークフローで追加ユーティリティを利用するため、公式 n8n イメージを一部拡張。
- 詳細は「[doc/n8n-pricing-and-hosting.md](doc/n8n-pricing-and-hosting.md)」を参照。

## 7. 参考文献
- [How to Deploy n8n on Google Cloud Free Tier | Complete n8n Self-Hosting Tutorial](https://www.youtube.com/watch?v=NNTbwOCPUww&t)
  - `docker-compose.yml`と`cloudbuild.yaml`は、この動画のサンプルコードを参考にして作成。
- [n8n公式ドキュメント](https://n8n.io/)
