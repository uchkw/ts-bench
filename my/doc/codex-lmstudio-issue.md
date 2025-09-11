Codex CLI × LM Studio の既知問題と回避策

概要
- 現状、Codex CLI（`codex exec`）を LM Studio の OpenAI 互換サーバー（/v1 エンドポイント）に接続して評価を実行すると、LM Studio 側で API 仕様の不整合が発生し、期待どおり動作しないケースが確認されています。
- そのため、当面は本リポのランナー（`my/tools/run-codex.sh`）で `provider=lmstudio` を指定した実行を禁止しています。代わりに `provider=ollama` を使用してください。

現象（LM Studio サーバーログ抜粋）
- ウォームアップ（/v1/chat/completions）は成功するが、その後に繰り返し以下のエラーが発生：

  ```
  [Server Error] {
    "error": {
      "message": "Invalid type for 'input': expected string, but got array.",
      "type": "invalid_request_error",
      "param": "input",
      "code": "invalid_type"
    }
  }
  ```

- これは Codex がリポジトリ解析等の過程で `/v1/embeddings` を呼ぶ際に `input` が配列（string[]）で送られるのに対し、LM Studio 側が文字列（string）のみを期待しているために起きるエラーと推定されます。
- さらに、LM Studio に対して `--oss` を使用すると、Ollama 固有の `/api/*` エンドポイント（例: `/api/tags`）を叩いてしまい、次のようなエラーが発生します：

  ```
  Unexpected endpoint or method. (GET /api/tags)
  ```

結論（なぜ禁止にしているか）
- LM Studio は `/v1/chat/completions` の互換性はある程度ありますが、Codex CLI の実行フローに含まれる `/v1/embeddings` のリクエスト形式（`input` が配列）に未対応なバージョンが存在します。
- `--oss` は Ollama 用の便宜フラグであり、LM Studio には適用できません。付けても解決しません。
- 上記理由から、本リポジトリのランナーでは `provider=lmstudio` を一時的にブロックしています。

推奨回避策（当面の運用）
- Ollama の利用：`provider=ollama` を指定し、Codex を `--oss` モードで起動します。
  - ウォームアップは `/api/version` `/api/tags` を使用。
  - 実本体は OpenAI 互換 `/v1/chat/completions` で通信（`CODEX_OSS_BASE_URL`）。
  - 例：

    ```bash
    ./my/tools/run-codex.sh gpt-oss:20b  beta ollama --exercise two-fer
    ./my/tools/run-codex.sh gpt-oss:120b beta ollama --exercise two-fer --timeout 1200
    ```

- LM Studio のモデル再ダウンロード／アップデート：
  - LM Studio 側の実装やモデルバンドルが更新され、`/v1/embeddings` の `input` に配列を許容するようになれば、本問題は解消される可能性があります。

（参考）一時的な技術的回避（採用見送り）
- `/v1/embeddings` に対して `input: string[]` が来た場合にサロゲートで文字列へ正規化するローカルプロキシを挟むことで、LM Studio へ透過的に中継する回避が可能です。ただし、本リポジトリでは保守容易性の観点から採用していません（コードは撤去済み）。必要なら別途提供可能です。

スクリプト側の扱い
- `my/tools/run-codex.sh` は、`provider=lmstudio` をデフォルトではブロックし、警告を出して終了します。
- 一時回避として、`--enable-proxy-for-lmstudio` オプションを付けた場合のみ、ローカル互換プロキシを起動して実行できます。
  - 例：

    ```bash
    ./my/tools/run-codex.sh gpt-oss-20b beta lmstudio --exercise two-fer --timeout 900 --enable-proxy-for-lmstudio
    ```

  - プロキシは `127.0.0.1:61234` で待ち受け、`/v1/embeddings` の `input` が配列の場合に文字列へ正規化して LM Studio に中継します。
  - 実行中は `OPENAI_BASE_URL=http://127.0.0.1:61234/v1` に自動で切替わり、終了時にプロキシは停止されます。

今後について
- LM Studio 側の OpenAI 互換実装（特に `/v1/embeddings` の `input` 仕様）や Codex CLI の設定オプションの変化をウォッチし、互換性が取れ次第、`provider=lmstudio` の禁止を解除予定です。
