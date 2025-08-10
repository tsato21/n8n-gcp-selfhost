# トラブルシューティング概要

実装中に発生した問題、その原因、対策などの概要

---

## サービスアカウントで OS Login 経由の SSH ができない
- 問題概要:
  - Cloud Build のサービスアカウント（SA）で、IAP + OS Login 経由の SSH/SCP を実行できない（Permission denied で失敗）。
- 発生原因:
  - 人間ユーザーでは OS Login により SSH が通る一方、SA では Ubuntu 最小イメージ側の PAM 設定不足や SA の扱いの差により公開鍵認証が通らず失敗していた。
- 実施した対策:
  - 必要ロールを SA に付与（例: `roles/compute.osAdminLogin`、`roles/iap.tunnelResourceAccessor`）。
  - 成り代わり許可（`roles/iam.serviceAccountUser`、`roles/iam.serviceAccountTokenCreator`）。
  - 必要 API の有効化（`oslogin.googleapis.com`、`iamcredentials.googleapis.com`）。
  - VM メタデータに `enable-oslogin=TRUE` を設定し、IAP 経由で詳細ログ（`--verbosity=debug` / `-- -vvv`）で検証。
- 結果:
  - SA の OS Login 経由 SSH は未解決。
  - 現状は代替手段（VM メタデータに公開鍵、秘密鍵は Secret Manager 管理）で Cloud Build から接続する運用に切替え。
- 補足:
  - OS Login: IAM の権限で VM への SSH 可否を管理する仕組み。ローカルユーザー管理を減らせる。
  - IAP（Identity-Aware Proxy）: Google のプロキシ経由で安全に VM へ入る仕組み。22番ポートを全世界へ開けずに済む。
  - サービスアカウント（SA）: 人間ではないアカウント。CI/CD などが使う。
  - 成り代わり（Impersonate）: ある SA が別の SA の権限で操作することを許可する設定。
  - PAM: Linux の認証モジュール。ここでの未設定は「正しい鍵でも認証段階で弾かれる」原因になり得る。

---
## Basic認証が成功しても認証用のモーダルが表示され続ける①
- 問題概要:
  - 正しい認証情報を入力しても認証ダイアログ（モーダル）が何度も表示され続ける。
- 原因: UI 用ルーターが広くマッチすることで API（`/rest`・`/webhook`）に BasicAuth が混入、あるいは HTML 以外の静的アセットにも BasicAuth がかかり並行 401 が多発すること。
- 対策: BasicAuth を「HTML リクエストに限定」し、非 HTML を認証なしで配信。API は最優先ルーターで常に BasicAuth 対象外。
- 結果: 初回アクセスで 401 になるのは HTML 1 件に収束し、二重モーダルが解消。API は常に UI ルーターより先に評価され、`WWW-Authenticate: Basic` が混入しない。
- 補足:
  - BasicAuth で保護できるのは UI(HTML) の入口のみ。API と Webhook のアクセス制御は別途実装が必要。

---

## Basic認証が成功しても認証用のモーダルが表示され続ける②
- 問題概要:
  - 正しい認証情報を入力しても認証ダイアログ（モーダル）が何度も表示され続ける。
- 発生原因（推測）:
  - `basicauth.users` を labels に直接埋め込む、または環境変数経由で展開させる実装だと、`$` が特殊文字として扱われやすく、以下のいずれかが起きる:
    - compose の変数展開で `$2y` 等が未定義変数とみなされ空文字化/分断。
    - YAML/シェルのクォート不足でエスケープが崩れ、Traefik 側で不正フォーマットと判定。
- 実施した対策:
  - labels の `basicauth.users` 利用をやめ、`usersfile` を採用。
  - `.env` に `BASIC_AUTH_USERS="username:$2y$..."` を1行で保持し、Cloud Build で VM 上に安全にファイル化
  - Traefik は `usersfile=/etc/traefik/htpasswd` を参照し、ホストの `/opt/n8n/htpasswd` を read-only マウントする。
- 結果:
  - `$` を含む bcrypt ハッシュが安全に扱えるようになり、Traefik 起動と BasicAuth の安定動作を確認。

---

## Cloud Build 中のエラー対応と権限の最小化
- 問題概要:
  - ビルド中に 各ステップが失敗するケースがあり、権限不足や API 未有効が原因で止まることがある。
- 発生原因:
  - 必要な IAM ロールが不足、または対象の Google API が未有効のままで、コマンドが権限エラーになる。
- 実施した対策:
  - Cloud Build のログから不足している権限や API を特定し、`terraform/main.tf` に追記 → `terraform apply` → 再実行。
  - 実装完了後、不要な権限がないかを再点検し、最小権限に戻す（付けすぎ防止）。
- 結果:
  - 「不足 → 追加 → 反映 → 見直し」のサイクルを回すことで、必要最小限の権限でビルドとデプロイが可能な状態に整理できた。
- 補足:
  - Cloud Build: Google のビルド/デプロイの自動実行サービス。
  - IAM ロール: 何ができるかを定義した権限セット。足りないとコマンドが失敗、過剰だとリスク増。
  - API 有効化: GCP では使うサービスごとに API を有効化する必要がある（例: Secret Manager、OS Login など）。
  - 最小権限の原則: 必要な作業に必要な権限だけを付与する考え方。

---

## Chromeで危険サイト警告

- 問題概要
  - Chrome でアクセスすると赤色の警告画面が表示され、閲覧がブロックされる（Safari では問題なし）。
- 考えられる原因（仮説）
  - Safe Browsing の正式リスト登録ではなく、Chrome のヒューリスティック判定による即時ブロックの可能性。
  - 新規ドメインかつコンテンツが少なく、ログイン画面のみの構成や外部スクリプトの多用、不要なリダイレクトがフィッシング類似と見なされた可能性。
- 実際の原因（判明）
  - サブドメイン名に `n8n` を含めていた（例: `n8n.example.com`）ことが主因と判断。Chrome のヒューリスティックで「ツール名 + ログイン画面のみ」の組み合わせが誤検知を誘発したと推定。
- 実施した対策
  - 他ブラウザでの挙動確認 => Safari では問題なかった。
  - [Safe Browsing 透明性レポート](https://transparencyreport.google.com/safe-browsing/search?hl=ja)で当該サイトを検索 => ブロック登録なしを確認。
  - Google Search Console に登録し、「セキュリティの問題」を確認 => 警告なし。
  - `.dev` ドメインを購入し、再デプロイ => 問題解消されず。
  - サブドメインを一般的な名称（例: `automation.example.com` / `workflow.example.com`）へ変更 => **問題解決**。
- 結果
  - サブドメイン名の変更により、Chrome の赤色警告は解消。
- 補足:
  - ヒューリスティック: 完全な証拠ではなく、パターン認識に基づいた即時の警告判断


---
## ブラウザで `Your connection is not private` と表示される

- 問題概要:
  -  DNS設定のIPアドレスを `34.83.112.240` から `34.83.218.209` に変えたあと、サイトにアクセスすると、ブラウザで「Your connection is not private」/ `net::ERR_CERT_AUTHORITY_INVALID`と表示。
    - 証明書の Subject/Issuer が「TRAEFIK DEFAULT CERT」。
    - DNS Checkerでは新IPアドレスで反映されている。
- 発生原因:
  - DNS 更新直後は Let’s Encrypt 側のリゾルバに旧 IP が残ることがある。Traefik は `acme.json` の状態に基づきバックオフ再試行し、即座に反映されない。
- 実施した対策:
  - VM で `cd /opt/n8n/cicd && sudo docker compose restart traefik` を実行し、ACME を再トリガー。
- 結果:
  - 上記問題解決し、サイトへのアクセス成功。
- 補足:
  - ACME: 自動証明書管理プロトコル。認証局（例: Let’s Encrypt）とサーバが HTTP‑01／TLS‑ALPN‑01／DNS‑01 のいずれかでドメイン所有を検証し、証明書の発行・更新を自動化する。Traefik は `--certificatesresolvers.<name>.acme.*` で有効化し、状態を `acme.json` に保存する（TLS‑ALPN‑01は443直結が必要、HTTP‑01は80番、DNS‑01はDNSプロバイダAPIでTXTレコード）。
