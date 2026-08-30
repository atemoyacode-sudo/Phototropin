# Pome Vision

macOSでスクリーンショットを撮ると、画像内の日本語・英語をローカルのVisionでOCRし、localhostのLM Studioへ渡して、回答を画面左下へ自動表示する独立プロトタイプです。macOS 26以降では、今流れているシステム音声も端末内で文字起こしし、リスニング問題や動画の内容について質問できます。

普段の利用にターミナル操作は不要です。`.app`を一度起動しておけば、通常どおり `⌘⇧4` などでスクリーンショットを撮るだけです。

## できること

- macOS標準のスクリーンショット保存先を1秒間隔で監視
- 日本語名・英語名などの新しいスクリーンショットを自動検出
- Vision `VNRecognizeTextRequest` による `ja-JP` / `en-US` OCR
- LM StudioのLocal Serverが公開するモデルの選択
- 「高速化の詳細」を開いた場合だけ、OpenAI互換APIの通常Draft Modelを任意指定
- 回答を全デスクトップの左下へ20秒間ポップアップ表示
- ポップアップから回答のコピー・手動クローズ
- メニューバーからモデルや自動検出を設定
- macOSが明暗に合わせて自動反転するテンプレート型の柘榴メニューバーアイコンとカラーアプリアイコン
- `⌃⌥⌘4` またはボタンから範囲撮影→回答
- 範囲撮影を始めると設定パネルと既存の回答カードを自動で閉じ、裏に隠れていた領域も選択可能
- OCRに回答すべき質問がない場合は、回答欄と左下カードに「これは何？ 内容を説明」を表示
- 「認識した問題」と「回答」はクリックで展開できる折りたたみ表示
- OCRが0文字の写真や風景でも「これは何？ 内容を説明」から画像対応LM Studioモデルへ画像を直接渡して説明
- ScreenCaptureKitで今流れているシステム音声を最大90秒取得（macOS 26以降）
- SpeechTranscriberによる英語／日本語のオンデバイス文字起こし
- 録音中は全デスクトップ右上に「停止して回答」を常時表示し、詳細を展開すると経過時間・質問・ライブ文字起こしを確認可能
- 確定した発話区間を改行で保持し、複数話者らしい内容はLM Studioの選択モデルが最小人数の`話者A / 話者B`形式へ推定整理
- 音声単体への自由質問、または直前のスクリーンショットOCRと組み合わせたリスニング問題への回答
- 音声ファイルは保存せず、認識バッファは停止後に破棄
- 画像内の命令文を信頼しないプロンプト境界
- GUIを通さず画像を検証できるCLI

添付例なら、期待される回答は `4 over` です。`get over the shock` で「ショックから立ち直る／乗り越える」という意味になります。

## 必要なもの

- macOS 14以降（システム音声の文字起こしはmacOS 26以降）
- Xcode 26系のSwift toolchain（Swift 6.2以降）
- Xcodeで作成したlogin keychain内の有効な `Apple Development` 署名証明書（無料のPersonal Teamでもローカル利用可能）
- [LM Studio](https://lmstudio.ai/) と、回答に使うローカル言語モデル（文字のない画像説明には画像入力対応モデル）

LM Studioでモデルをダウンロードし、Developer画面のLocal Serverを開始します。CLIを使う場合の例:

```sh
lms server start
lms ps
```

LM Studioの既定ポートは1234です。アプリはネイティブの `GET /api/v1/models` からLLMだけを選択肢にし、生成にはOpenAI互換の `POST /v1/chat/completions` を使います。接続先はHTTPの `127.0.0.1` / `localhost` / `::1` のみに制限します。画像とOCR本文を外部APIへ送らず、ツールやMCPも要求しません。LM Studio側でAPI認証を有効にした構成には現時点で対応していません。選択したローカルモデル自体の品質はモデルごとに異なります。

モデル欄の小さな「高速化の詳細」を展開すると、別の互換小型モデルを通常のDraft Modelとして指定できます。指定時だけOpenAI互換リクエストへ `draft_model` を付け、既定の「LM Studio側の設定」では何も上書きしません。MTPとDSparkは回答リクエストではなくモデル読込時のランタイム機能です。現在の公開REST APIから安全に切り替えられないため、このアプリはLM Studio側でMTP/DSparkを有効にして読み込んだ状態をそのまま利用し、LM Studioの非公開設定ファイルは編集しません。

## 使い方

1. LM Studioを起動し、利用するモデルを用意してLocal Serverを開始します（既定 `http://localhost:1234`）。
2. `dist/Pome Vision.app` をダブルクリックします。
3. メニューバーのアイコンからLM Studioモデルを一度選びます。
4. `⌘⇧4` など、普段の方法で問題をスクリーンショットします。
5. OCRと回答生成が終わると、画面左下へ回答カードが現れます。

回答カードは20秒後に自動で消えます。カード上のボタンでコピーまたはすぐに閉じることもできます。

OCRが質問でない場合は、「これは何？ 内容を説明」を押すと、ページの種類、重要な内容、OCRの曖昧さを別プロンプトで説明します。OCRで文字を1文字も検出できない写真や風景でも同じボタンを表示し、`vision`対応モデルへ縮小した画像を直接渡して内容を説明します。画像非対応モデルでは、対応モデルを選ぶようエラーを表示します。

### 今流れている音声に質問する

1. メニューバーで「今流れている音声」の言語（英語／日本語）を選びます。
2. 必要なら「話者は何を主張していますか？」などの質問を入力します。空欄でスクリーンショットOCRがある場合は、音声を根拠に画面の問題へ回答します。
3. 必要に応じて「複数話者を対話として整理（推定）」を切り替え、「音声を聞く」を押します。通常パネルは閉じ、全デスクトップ右上に小さな録音コントローラーが表示されます。
4. 再生後は録音コントローラーの「停止して回答」を押します。メニューバーを開き直す必要はありません。「詳細」から質問とライブ文字起こしを展開でき、90秒で自動停止します。
5. 文字起こしと回答が表示されます。質問を書き換え「この音声に質問」を押すと、同じ文字起こしへ再質問できます。

初回は「画面とシステムオーディオ録音」と「音声認識」の許可が必要です。音声認識モデルが未導入の場合、初回だけmacOSが言語アセットをダウンロードします。

SpeechTranscriberは声紋による話者IDを返さないため、`話者A / 話者B`は発話区間、呼びかけ、質問と応答の文脈からLM Studioの選択モデルが推定します。成立する最小人数を優先し、画面と回答にも「推定」と明記します。厳密な話者ダイアライゼーションではありません。

## 開発時のビルド

### 初回だけ必要なXcode署名設定

GitHubではソースだけを公開し、配布用バイナリへ作者の署名を付けません。利用者は自分のMacで、初回だけ次の操作を行います。

1. Xcodeを起動し、`Xcode > Settings… > Accounts`を開きます。
2. `+`から自分のApple Accountへサインインします。無料アカウントの場合は`Personal Team`として表示されます。
3. AccountまたはTeamを選び、`Manage Certificates…`を開きます。
4. `+`から`Apple Development`を1枚作成して閉じます。

秘密鍵はそのMacのlogin keychainだけに保存され、GitHubやPome Visionへ送信されません。Xcodeでプロジェクトを開く操作、Bundle ID登録、Developer ID、公証はローカル利用には不要です。

リポジトリを取得した後は次のコマンドで署名済みアプリを作れます。

```sh
git clone https://github.com/atemoyacode-sudo/Pome-Vision.git
cd Pome-Vision
./scripts/build-app.sh
open "dist/Pome Vision.app"
```

有効なApple Development証明書が1枚なら自動選択されます。複数ある場合だけ、後述のフィンガープリント指定が必要です。

### 開発用コマンド

```sh
swift test
swift run PomeVision
```

通常の`.app`を作る場合:

```sh
./scripts/build-app.sh
open "dist/Pome Vision.app"
```

スクリプトは `dist/Pome Vision.app` と `dist/Pome Vision.zip` を生成し、Apple Development署名、指定要件、ZIP整合性を確認します。有効なApple Development証明書がない場合はビルドを停止し、ad-hoc署名へはフォールバックしません。

証明書が1つなら初回に自動選択し、公開フィンガープリントだけをGit除外済みの `Support/Signing.local` へ固定します。以後は必ず同じ証明書を使い、証明書が見つからなければ停止します。初回から複数ある場合は、次のように証明書の40桁SHA-1フィンガープリントをその実行に渡します。

```sh
POME_VISION_SIGNING_IDENTITY_HASH=0123456789ABCDEF0123456789ABCDEF01234567 \
  ./scripts/build-app.sh
```

秘密鍵や `.p12` / `.cer` はリポジトリへ保存しません。ルートの`.gitignore`が、秘密鍵、証明書、App Store Connectキー、ローカル署名設定、`.env`、キーチェーン、ビルド成果物をGit対象から外します。ソースを公開しても、作者や利用者の署名情報は含まれません。
証明書を更新するときだけ `Support/Signing.local` を削除し、次回ビルドで新しい有1件を固定し直します。この切り替え時は画面収録の再許可が必要になる場合があります。

公開前には次の検査を実行します。

```sh
./scripts/check-public-safety.sh
```

この検査はGit公開候補だけを対象に、証明書・秘密鍵・ローカル設定が除外されていることと、ホームディレクトリ、メールアドレス、現在の証明書フィンガープリント、Team IDが混入していないことを確認します。GitHub上でも`Pome Vision checks`ワークフローが秘密情報を使わず同じ検査と`swift test`を実行します。

初回の安定署名版に切り替えた後だけ、古いad-hoc版の「画面収録」許可をシステム設定から外し、新しい `.app` を起動して再許可してください。以後は同じBundle IDと同じ証明書を使い続けることで、再ビルドごとの許可切れを防ぎます。

初回はスクリーンショット保存先（通常はデスクトップ）へのアクセス確認が表示される場合があります。標準スクリーンショットの保存先がクリップボードだけに設定されている場合、自動監視では検出できないため、アプリの「範囲を撮影して回答」を使ってください。

## 開発者向けCLI検証

```sh
swift run pome-vision-cli /path/to/problem.png
swift run pome-vision-cli --ocr-only /path/to/problem.png
swift run pome-vision-cli --text "Video - Example title"
swift run pome-vision-cli --describe-text "Video - Example title"
swift run pome-vision-cli --describe-image /path/to/photo.png image-capable-model-id
swift run pome-vision-cli --dialogue-text $'Hello.\nHi. Nice to meet you.'
```

CLIはOCRやモデル応答を切り分けるための開発用です。`--text`は画像を使わず任意のOCR文を渡し、「これは何？」ボタン対象の判定まで表示します。`--describe-text`はOCRだけを使う説明生成、`--describe-image`は画像対応モデルへ画像そのものを渡す説明生成、`--dialogue-text`は複数発話を推定対話として整理する経路を検証します。通常利用では実行する必要はありません。モデル名を省略すると、LM Studioの `/api/v1/models` が返したLLM一覧の先頭を使います。

## 構成

- `Sources/ScreenshotAnswerCore/` — OCR、プロンプト、LM Studio OpenAI互換クライアント、処理パイプライン。AppKit UIから独立して再利用する中心API
- `Sources/ScreenshotAnswerApp/` — メニューバー設定、Pome Visionブランドマーク、保存先監視、範囲撮影、左下回答オーバーレイ、ScreenCaptureKitシステム音声、SpeechTranscriber、クリップボード
- `Support/AppIcon.svg` — Finder用カラーアプリアイコンの編集可能なSVG原本
- `Sources/ScreenshotAnswerCLI/` — 1画像を処理する検証用CLI
- `Tests/` — 読み順、localhost制約、プロンプト境界、パイプラインの回帰テスト
- `scripts/build-app.sh` — login keychainのApple Development証明書を厳密に選択し、ad-hoc署名を禁止するローカルビルド
- `scripts/check-public-safety.sh` — Git公開候補へ個人パス・メール・署名識別子・credential形式が混入していないことを検査

## 現在の制約

- 自動検出は、対応画像拡張子かつ既知のスクリーンショット名で保存された新規ファイルが対象です。OS言語によって名前が異なる場合は `ScreenshotFileClassifier` に接頭辞を追加してください。
- 通常の問題回答はOCRを使います。「これは何？ 内容を説明」では画像を最大1600px・JPEGへ縮小し、OpenAI互換の `image_url` data URLとして選択したローカルLM Studioモデルへ直接渡します。図・数式・細部の説明精度はモデルによって異なります。
- システム音声は選択した英語または日本語として認識します。複数言語が頻繁に入れ替わる音声やDRM保護コンテンツは正確に取得できない場合があります。
- Draft Modelはメインモデルと語彙互換である必要があり、組み合わせによっては速くならないか、LM Studioが要求を拒否します。MTP/DSparkの切替はLM Studio側で行ってください。
- `swift test`やCLIのOCR成功は、標準撮影監視・権限ダイアログ・左下ポップアップまで含むGUI動作の証明ではありません。最終確認は実際の`.app`起動後に行ってください。
