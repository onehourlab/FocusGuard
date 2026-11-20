# Focus Guard

アプリを開く前に「何のために・何分・なぜ今」を文章で申請し、端末内のAIとルールが審査してから、申告した時間だけ使えるようにする iPhone 用スクリーンタイム管理アプリです。
目的は使用時間を減らすことそのものより、無意識に開く習慣を「目的を持って使う」行動に変えることです。

- 外部AI API（OpenAI・Anthropic など）は使いません。通信も行いません。AIは Apple の **Foundation Models（オンデバイス）** だけを使い、非対応端末ではルール判定だけで審査します。
- データは端末内（App Group の JSON ファイル）だけに保存します。ログインは不要です。

> **現在の状態**：Windows 上で作成したため、**Xcode でのビルド・テスト・実機での動作確認はまだ行っていません**。
> Windows で確認できたのは、`scripts/static_check.py` による構文と設定の検査だけです。
> 型のエラーやテストの失敗は、GitHub Actions（macOS）で初めて分かります（下の「Windows からの開発の流れ」参照）。

---

## 1. iOS の制約と、それに合わせた設計

| 仕様 | iOS の制約 | 採用した方式 |
|---|---|---|
| 制限したアプリを開いたら申請させる | 他アプリの起動は止められない。ブロック画面（Shield）には**文字入力欄を置けない** | Shield に「利用を申請する」ボタンを置き、押すと対象を保存して通知を出す。通知をタップすると Focus Guard の申請画面が開く |
| 申告した時間だけ使える | `DeviceActivitySchedule` の監視間隔は**最短15分** | 2つの方法で再び制限する：① 解除後の**使用時間しきい値イベント**（1分ごと。許可時間に達したら即再制限）② 使わなかった場合の**期限**（`max(許可時間+1分, 15分)`）|
| 実際の使用時間 | 使用時間のデータは**レポート拡張の中でしか読めない**（本体へ持ち出せない） | ① 画面表示は DeviceActivityReport 拡張で行う ② 解除中の使用分数は、しきい値イベントから1分単位で記録する（取れた範囲だけ。取れない場合は「計測データなし」と表示） |
| 緊急時は確実に解除 | — | 緊急解除は AI・通信・待ち時間なし。種類を1つ選ぶとその場で解除し、記録だけ残す |
| 電話・健康・安全のアプリ | 「電話」アプリと緊急SOSはもともと制限を受けない | 「常に許可するアプリ」を選べる（制限対象から自動で除外） |
| オンデバイスAI | Foundation Models は iOS 26 以降・Apple Intelligence 対応端末のみ | 対応端末ではAIが文章を読み取り、非対応端末・失敗・12秒以上かかった場合はルール判定だけで審査する |

### App Store で公開するために必要なこと
1. **Apple Developer Program**（年額）への登録
2. **Family Controls の配布用権限の申請**：開発中は権限なしでも自分の端末で試せますが、TestFlight と App Store 配布には Apple の承認が必要です。
   [Family Controls 配布用の申請ページ](https://developer.apple.com/contact/request/family-controls-distribution) から、**本体と4つの拡張それぞれの Bundle ID** について申請します。
3. App Store 審査用のプライバシー説明（データは端末内のみ・外部送信なし）とスクリーンショット

---

## 2. 構成

```
FocusGuard/
├── project.yml                      … XcodeGen 設定（Bundle ID・App Group・Team はここだけで変更）
├── Packages/FocusGuardKit/          … UI に依存しない共通ロジック（Mac で `swift test` できる）
│   ├── Sources/FocusGuardKit/
│   │   ├── Models.swift             … 対象・ルール・申請・審査結果・セッション・緊急解除の型
│   │   ├── TextAnalysis.swift       … 文章の正規化・意味のまとまり（概念）・類似度
│   │   ├── ReviewEngine.swift       … 審査（5つの基準 → 承認／再質問／不承認）
│   │   ├── Ledger.swift             … 記録の追加・セッション開始/終了・緊急解除（全変更はここを通す）
│   │   ├── Analytics.swift          … 日次・週次の集計、基準値、目標、振り返り
│   │   └── FocusStore.swift         … App Group の JSON 保存（プロセス間の排他つき）
│   └── Tests/                       … XCTest（審査・類似判定・記録・集計）
├── Shared/                          … 本体と拡張で共通の Screen Time 処理（制限の反映・監視・通知）
├── FocusGuard/                      … 本体アプリ（SwiftUI）
│   ├── App/                         … 起動・AppModel（画面からの操作の窓口）
│   ├── Services/OnDeviceAIReviewer.swift … Foundation Models による読み取り
│   └── Screens/                     … ホーム・申請・緊急解除・レポート・履歴・設定・対象の編集
├── FocusGuardMonitor/               … DeviceActivity 監視拡張（使用時間・期限で再制限）
├── FocusGuardShield/                … ブロック画面の見た目
├── FocusGuardShieldAction/          … ブロック画面のボタン操作
├── FocusGuardReport/                … 実際の使用時間のレポート表示
├── scripts/static_check.py          … Windows でできる静的チェック
└── .github/workflows/               … build.yml（自動テスト・ビルド）/ testflight.yml（iPhone 配信）
```

制限の状態は「保存データ → `ShieldController.reconcile`」で毎回決め直します。本体・監視拡張のどちらから呼んでも同じ結果になるため、片方が動かなかった場合も、次にどちらかが動いた時点で正しい状態に戻ります。

---

## 3. 審査の仕組み（AI承認制）

AIは**文章の読み取りだけ**を担当し、承認・不承認の最終判断は `ReviewEngine` の決まった規則で行います。同じ入力には必ず同じ結果を返し、5つの基準ごとに理由を表示します。

| 基準 | 判定の内容 |
|---|---|
| 目的の具体性 | 誰に・何を・どうするか。あいまいな語（「なんとなく」「暇」など）だけの場合は質問する。「なぜ今」も確認する |
| 終了条件 | 「2本見たら終わり」「返信したら閉じる」など。返信・検索・購入のように行動自体に区切りがあれば満たす |
| 時間の妥当性 | 目的ごとの目安を大きく超えると理由を質問する |
| 過去の利用との関係 | 同じ文章のコピー、同じ目的の繰り返し（標準は3回使ったあと）、延長の繰り返し、使い切った直後の再申請 |
| あなたのルール | 1回の上限・1日の上限・目的別の上限・時間帯ルール・文章のルール |

- **結果の決め方**：上限などの数値ルール違反は不承認（「残り5分なら申請できます」と提案）。それ以外の不足はまず**再質問**し、標準で2回まで説明を受けても不足なら不承認。
- **娯楽は不承認の理由にならない**：分類が「娯楽」でも、終了条件があれば承認します。娯楽を制限したい場合は、本人が時間帯ルールなどで決めます。
- **AIの誤判定への対策**：AIが「ルールに反する」と指摘しても、本人が書いたルール文と一致しない指摘は採用しません。一致した場合もまず質問にします。

### 同じ目的の判定（機能C）
文章を正規化（全角/半角・カタカナ/ひらがな・記号）し、「返信・視聴・調べもの…」（何をするか）と「友人・メッセージ・学習…」（何について）の概念を取り出して比べます。
例：「友達からのDMに返信するため5分」「Instagramでメッセージを返すため5分」「友達に返信するため5分」は同じ目的になります（テストで確認する例）。
同じ目的で3回使ったあとに申請すると「本日はすでに同じ目的で3回利用しています。今回はどのような新しい用事がありますか？」と質問し、新しい用事が書かれれば承認します。集計は日付が変わるとリセットされ、記録は400日残ります。

---

## 4. Windows からの開発の流れ

Mac が無くても、次の流れで開発できます。

1. **Windows**：コードを書く → `python scripts/static_check.py` で構文と設定を確認
   （初回のみ `pip install tree-sitter-language-pack pyyaml`）
2. **GitHub に push** → `build.yml` が macOS 上で `swift test`（審査ロジックのテスト）と、アプリ＋拡張のビルドを自動で実行。結果は GitHub の「Actions」タブで見られます
3. **iPhone で試す** → `testflight.yml` を手動で実行すると TestFlight に配信され、iPhone の TestFlight アプリから入れられます

GitHub Actions の macOS の実行時間は、非公開リポジトリだと無料枠の消費が速い（Linux の10倍で数える）ので、必要なときだけ push するのがおすすめです。

### iPhone で試す（TestFlight）の準備
1. Apple Developer Program に登録し、[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) で App Group（例：`group.<あなたのドメイン>.focusguard`）を作る
2. App Store Connect で新しいアプリを作る（Bundle ID は `project.yml` の `APP_BUNDLE_ID` と同じに）
3. App Store Connect の「ユーザーとアクセス → 統合 → App Store Connect API」でキーを作る（役割：App Manager）
4. GitHub リポジトリの Settings → Secrets and variables → Actions に登録：
   - Secrets：`ASC_KEY_ID`・`ASC_ISSUER_ID`・`ASC_KEY_P8`（.p8 ファイルの中身）・`TEAM_ID`
   - Variables：`APP_BUNDLE_ID`・`APP_GROUP_ID`
5. Family Controls 配布用権限の承認を待つ（上の「App Store で公開するために必要なこと」参照）
6. Actions タブで `testflight` を実行

### Mac がある場合
```bash
brew install xcodegen
xcodegen generate
open FocusGuard.xcodeproj
```
`project.yml` の `DEVELOPMENT_TEAM` を設定して実機で実行します（Screen Time API はシミュレータでは正しく動きません）。

---

## 5. 実機で確認が必要な点

コードは用意していますが、次の点は iPhone で確かめる必要があります。

- [ ] ブロック画面 → 通知 → 申請画面へ移る流れが自然か（通知の許可が必要）
- [ ] 使用時間しきい値イベントが、解除した時点から正しく数えられるか（iOS 17.4 以降は `includesPastActivity: false` を指定）
- [ ] 期限（最短15分）での再制限
- [ ] Foundation Models の日本語での判定の質と応答時間（12秒で打ち切り、ルール判定に切り替え）
- [ ] レポート拡張の表示（昨日との比較・1週間の推移）
- [ ] 「常に許可するアプリ」がカテゴリ指定の制限からも外れるか
