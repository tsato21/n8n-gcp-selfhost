# デプロイ時の課題報告

## Dockerfile.n8n のビルド失敗

### 事象
Cloud Build の Step #4 (Deploy to VM) にて `docker compose build --pull n8n` が `exit code: 127` で失敗。

```
failed to solve: process "/bin/sh -c set -eux; apk add --no-cache ..." did not complete successfully: exit code: 127
```

### 原因
`Dockerfile.n8n` が Alpine ベースの `apk` コマンドを使用していたが、`docker.n8n.io/n8nio/n8n:latest` の最新イメージが Debian ベースに変更されており、`apk` コマンドが存在しなかった。

### 対処
OCR 等の追加パッケージが不要だったため、`Dockerfile.n8n` を最小構成に簡略化した。

```dockerfile
FROM docker.n8n.io/n8nio/n8n:latest
```

### 再発防止
- `latest` タグを使用せず、特定バージョン（例: `2.11.2`）を指定する
- n8n のベースイメージ変更はリリースノートで確認する

---

## Traefik が Docker API に接続できない

### 事象
Traefik コンテナが Docker プロバイダー経由でコンテナ情報を取得しようとするが、以下のエラーが発生し続けた。

```
ERR Failed to retrieve information of the docker client and server host
error="Error response from daemon: client version 1.24 is too old.
Minimum supported API version is 1.40, please upgrade your client to a newer version"
providerName=docker
```

その結果、n8n のルーティングが確立されず、Let's Encrypt 証明書も取得されなかった。ブラウザでは `NET::ERR_CERT_AUTHORITY_INVALID` として表示された。

### 原因
| 項目 | 値 |
|---|---|
| Traefik が使用する Docker API バージョン | 1.24（Traefik 内部にハードコード） |
| VM の Docker デーモン（26〜29系）が要求する最低バージョン | 1.40 |

Traefik v2.10・v3.3 ともに、Docker プロバイダーの初回接続時に API version 1.24 を使用する。Docker 26 以降はこのバージョンでの接続を拒否するようになったため、互換性が失われた。

`DOCKER_API_VERSION=1.47` 環境変数を設定しても Traefik は無視した（Traefik の Docker クライアント初期化が環境変数を参照しないため）。

### 対処
Docker プロバイダーを廃止し、静的ファイルプロバイダーに切り替えた。

**変更前（docker-compose.yml）**
```yaml
command:
  - "--providers.docker=true"
  - "--providers.docker.exposedbydefault=false"
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

**変更後（docker-compose.yml）**
```yaml
command:
  - "--providers.file.filename=/etc/traefik/routes.yml"
volumes:
  - ./traefik-routes.yml:/etc/traefik/routes.yml:ro
```

n8n のルーティング・ミドルウェア設定をすべて `cicd/traefik-routes.yml` に静的定義することで、Docker API への依存を完全に排除した。

### 再発防止
- 新規 VM 構築時は Docker バージョンと Traefik の互換性を事前確認する
- Docker プロバイダーは使用しない（静的ファイルプロバイダーを標準とする）

---

## Traefik v3 が bcrypt ハッシュの `$` を環境変数として展開し Basic 認証が通らない

### 事象
`htpasswd -nB` で生成した正しいパスワードを入力しても Basic 認証が通らない。Traefik のログに以下の警告が繰り返し出力されていた。

```
level=warning msg="The \"BGddjM0saTZdyfqK8ipH2O\" variable is not set. Defaulting to a blank string."
```

### 原因
Traefik v3 のファイルプロバイダーは、読み込むファイル（`usersFile` で指定した htpasswd ファイルを含む）に対して環境変数展開を行う。bcrypt ハッシュ（例: `$2y$05$BGddjM0...`）内の `$BGddjM0...` が未定義の環境変数として解釈され空文字に置換されるため、ハッシュが破壊されて認証が常に失敗する。

### 対処
htpasswd ファイルに書き込む際、`$` を `$$` にエスケープするよう `cicd/cloudbuild.yaml` を修正した。Traefik は `$$` を読み込み時に `$` に変換するため、正しい bcrypt ハッシュとして検証される。

**変更前（cloudbuild.yaml）**
```bash
grep '^BASIC_AUTH_USERS=' .env | sed 's/^BASIC_AUTH_USERS=//' > /opt/n8n/htpasswd
```

**変更後（cloudbuild.yaml）**
```bash
grep '^BASIC_AUTH_USERS=' .env | sed 's/^BASIC_AUTH_USERS=//' | sed 's/\$/\$\$/g' > /opt/n8n/htpasswd
```

### 再発防止
- htpasswd ファイルを Traefik v3 の `usersFile` で使用する場合は、`$` を `$$` にエスケープして書き込む
- Traefik ログの `variable is not set` 警告は htpasswd ハッシュ破壊のサインとして認識する

---

## n8n 初回ロード時に静的アセットが 429 Too Many Requests で読み込めず画面が真っ白

### 事象
Basic 認証は通過するが n8n の画面が真っ白になる。ブラウザの開発者コンソールに大量の 429 エラーが表示されていた。

```
GET https://auto-workflow.tiger-tiger.dev/assets/xxx.js net::ERR_ABORTED 429 (Too Many Requests)
```

### 原因
Traefik のレートリミットミドルウェア（`average: 10, burst: 20 req/s`）を静的アセット用ルーター（`n8n-ui-other`）にも適用していた。n8n は初回ロード時に数十〜百件以上の JS/CSS ファイルを同時リクエストするため、設定値を大幅に超えてレートリミットに引っかかり、アセットが読み込めなかった。

### 対処
`cicd/traefik-routes.yml` の `n8n-ui-other`（静的アセット用ルーター）からレートリミットミドルウェアを削除した。HTML リクエスト用ルーター（`n8n-ui-html`）には引き続き適用している。

**変更前（traefik-routes.yml）**
```yaml
n8n-ui-other:
  middlewares:
    - n8n-headers
    - n8n-ratelimit
```

**変更後（traefik-routes.yml）**
```yaml
n8n-ui-other:
  middlewares:
    - n8n-headers
```

### 再発防止
- レートリミットは静的アセットには適用しない
- ログイン画面（HTML）や API エンドポイントに絞って適用する
