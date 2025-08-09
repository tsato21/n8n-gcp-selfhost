# n8n PR通知ワークフロー セットアップガイド

## 1. Slack App の作成

### 1-1. アプリ作成
1. https://api.slack.com/apps にアクセス
2. 「Create New App」→「From scratch」を選択
3. App Name を入力（例: `GitHub通知`）
4. 投稿先の Slack ワークスペースを選択
5. 「Create App」をクリック

### 1-2. Bot User の有効化
1. 左メニューの「App Home」をクリック
2. 「App Display Name」セクションの「Edit」をクリック
3. Display Name（例: `GitHub通知`）と Default Username（例: `github-notify`）を入力
4. 「Save」をクリック

### 1-3. 権限（OAuth Scopes）の設定
1. 左メニューの「OAuth & Permissions」をクリック
2. 「Scopes」セクションまでスクロール
3. 「Bot Token Scopes」の「Add an OAuth Scope」をクリック
4. `chat:write` を追加

### 1-4. ワークスペースへのインストール
1. 同ページ上部の「Install to Workspace」をクリック
2. 権限を確認して「許可する」をクリック
3. **Bot User OAuth Token**（`xoxb-` で始まる文字列）が表示されるのでコピー

### 1-5. Bot をチャンネルに招待
1. Slack で投稿先チャンネルを開く
2. メッセージ欄に `/invite @GitHub通知`（App Display Name）と入力して送信

### 1-6. チャンネル ID の確認
1. チャンネル名をクリック → チャンネル詳細を開く
2. 最下部に表示される「チャンネルID」（`C` で始まる英数字）をコピー

### 1-7. n8n への登録
1. n8n の Credentials → Add credential → **Slack API**
2. 「Access Token」に `xoxb-...` トークンを貼り付け
3. 保存

---

## 2. GitHub Webhook の設定

### 2-1. Webhook の追加
1. 対象リポジトリの GitHub ページを開く
2. **Settings** → 左メニューの **Webhooks** → **Add webhook**

### 2-2. Webhook の設定項目

| 項目 | 値 |
|---|---|
| Payload URL | `https://<your-n8n-domain>/webhook/github-pr-webhook` |
| Content type | `application/json` |
| Secret | （任意。空でもOK） |

### 2-3. イベントの選択
1. 「Let me select individual events.」を選択
2. **Pull requests** にのみチェックを入れる（他はすべて外す）
3. 「Active」にチェックが入っていることを確認
4. 「Add webhook」をクリック

### 2-4. 注意点
- Payload URL は `/webhook-test/...`（テスト用）ではなく `/webhook/...`（本番用）を設定すること
- n8n 側のワークフローを **Activate（有効化）** しておかないと 404 になる
- Cloud Run の最小インスタンス数を 1 にしておくと Webhook の取りこぼしを防げる（`--min-instances=1`）

---

## 3. AI API Key の取得

使用する LLM に応じてどちらかを設定してください。

### 3-A. Google Gemini（無料枠あり・おすすめ）

#### API Key の取得
1. https://aistudio.google.com/apikey にアクセス
2. Google アカウントでログイン
3. 「Create API Key」をクリック
4. プロジェクトを選択（なければ新規作成）
5. 生成された API Key をコピー

#### n8n での使い方
- HTTP Request ノードで直接 Gemini API を呼び出す
- URL: `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=YOUR_API_KEY`
- Method: POST
- Body:
```json
{
  "contents": [
    {
      "parts": [
        {
          "text": "ここにプロンプトとPR情報を入れる"
        }
      ]
    }
  ]
}
```

#### 料金
- Gemini 2.0 Flash: 無料枠あり（1分あたり15リクエスト、1日1500リクエスト）
- PR通知用途であれば無料枠で十分

---

### 3-B. Anthropic Claude（有料）

#### API Key の取得
1. https://console.anthropic.com にアクセス
2. アカウント作成またはログイン
3. **Plans & Billing** でクレジットを購入（最低 $5）
4. **API Keys** → 「Create Key」をクリック
5. 名前を入力して作成
6. `sk-ant-api03-...` で始まるキーをコピー（この画面を閉じると二度と表示されないので注意）

#### n8n での使い方（HTTP Request ノード）
- URL: `https://api.anthropic.com/v1/messages`
- Method: POST
- Headers:
  - `x-api-key`: APIキー
  - `anthropic-version`: `2023-06-01`
  - `content-type`: `application/json`
- Body:
```json
{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 1024,
  "messages": [
    {
      "role": "user",
      "content": "ここにプロンプトとPR情報を入れる"
    }
  ]
}
```

#### 料金
- Claude Sonnet: 入力 $3 / 100万トークン、出力 $15 / 100万トークン
- PR通知1回あたりのコストは数円程度

---

## 4. 最終チェックリスト

- [ ] Slack App が作成され、Bot がチャンネルに招待されている
- [ ] Slack の Bot Token が n8n に登録されている
- [ ] チャンネル ID が Slack ノードに設定されている
- [ ] GitHub Webhook が `/webhook/...`（本番URL）で登録されている
- [ ] GitHub Webhook のイベントが Pull requests のみになっている
- [ ] AI の API Key が取得済みで n8n のノードに設定されている
- [ ] n8n ワークフローが **Activate（有効化）** されている
- [ ] Cloud Run の最小インスタンス数が 1 に設定されている（推奨）
