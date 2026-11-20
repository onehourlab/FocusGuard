# Focus Guard Web 版

Apple Developer Program に登録しなくても、iPhone の Safari と「ショートカット」アプリだけで使える版です。
審査のルール（目的の具体性・終了条件・時間・同じ目的の繰り返し・本人ルール）は iOS 版と同じものを JavaScript に移植しています（`src/engine.js`、テストは `test/`）。

## iOS 版との違い

| | Web 版 | iOS 版 |
|---|---|---|
| 制限の方法 | ショートカットの自動化で、アプリを開くたびにこの画面へ移動 | Screen Time API でアプリそのものをブロック |
| 時間切れ | **次に開いたとき**から再び申請が必要（使用中には閉じない） | 許可時間に達した時点で再びブロック |
| 使用時間 | 許可した時間（早めに終えた場合はそこまで）で数える | iOS が計測した実際の使用時間 |
| 審査 | ルール判定のみ（このブラウザ内・通信なし） | ルール判定＋オンデバイスAI |
| データ | このブラウザの中（Safari） | 端末内（App Group） |

## 使い方

1. iPhone の Safari で公開URL（GitHub Pages）を開く
2. 「制限するアプリ」を登録する
3. 画面の「ショートカットの設定」の手順で、許可用ショートカット `FocusGuard許可` と、アプリごとの自動化を作る

## 開発（Windows）

```bash
cd web
npm test
```

```bash
cd web
npm start
```

`npm start` で http://localhost:5178 が開きます。外部ライブラリは使っていないため `npm install` は不要です。
