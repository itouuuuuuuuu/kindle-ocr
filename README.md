# Kindle OCRスクリプト実行環境構築ガイド

このKindle OCRスクリプトは、**Kindleアプリの画面を自動でスクリーンショット撮影し、OCR（光学文字認識）でテキスト化してGoogle Docsにアップロードする自動化システム**です。

## 最終的に生成される成果物

### 1. **Google Docsドキュメント** 📄
- **場所**: 指定したGoogle Driveフォルダ内
- **内容**: OCRで抽出されたテキスト全文
- **ファイル名**: 抽出テキストの最初の20文字（設定可能）+ オプションでタイムスタンプ
- **形式**: 編集可能なGoogle Docsドキュメント

### 2. **PDFファイル** 📖
- **場所**: デスクトップの一時フォルダ
- **内容**: 全スクリーンショットを結合したPDF
- **ファイル名**: `kindle_output.pdf`（設定可能）
- **用途**: 元画像の保存・アーカイブ

### 3. **テキストファイル** 📝
- **場所**: デスクトップの一時フォルダ
- **内容**: OCRで抽出された生テキスト
- **ファイル名**: `ocr_output.txt`（設定可能）
- **エンコーディング**: UTF-8

### 4. **Google Docs URL** 🔗
- **場所**: `google_doc_url.txt`ファイル
- **内容**: 作成されたGoogle DocsのURL
- **用途**: 直接アクセス用

## 1. 前提条件の確認

### システム要件
- **macOS** (AppleScript使用のため)
- **Python 3.8以上**
- **インターネット接続** (Google API使用)
- **Google アカウント** (Google Cloud Platform使用)
- **direnv** (環境変数管理)

```bash
# Python バージョン確認
python3 --version

# Homebrewインストール確認（未インストールの場合）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# direnvインストール
brew install direnv

# シェル設定（zshの場合）
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
source ~/.zshrc
```

## 2. Python環境とライブラリのセットアップ

### 必要ライブラリのインストール

```bash
# プロジェクトディレクトリに移動
cd /path/to/your/kindle-ocr-project  # kindle_ocr_automation.scptがあるディレクトリ

# 仮想環境作成（推奨）
python3 -m venv kindle_ocr_env
source kindle_ocr_env/bin/activate

# 必要ライブラリインストール
pip install --upgrade pip
pip install google-cloud-vision
pip install google-api-python-client
pip install google-auth
pip install google-auth-oauthlib
pip install google-auth-httplib2
pip install img2pdf
```

### img2pdfのシステムインストール
```bash
# Homebrewでimg2pdfインストール
brew install img2pdf

# インストール確認
which img2pdf
img2pdf --version
```

## 3. Google Cloud Platform (GCP) セットアップ

### 3.1 Google Cloud CLI インストールと認証

```bash
# Google Cloud CLI インストール
brew install google-cloud-sdk

# シェル設定の更新（zshの場合）
echo 'source /opt/homebrew/share/google-cloud-sdk/path.zsh.inc' >> ~/.zshrc
echo 'source /opt/homebrew/share/google-cloud-sdk/completion.zsh.inc' >> ~/.zshrc
source ~/.zshrc

# 認証（ブラウザが開きます）
gcloud auth login
```

### 3.2 プロジェクトの作成と設定

#### 方法1: 新規プロジェクト作成（推奨）
```bash
# 一意なプロジェクトIDを生成して作成
PROJECT_ID="kindle-ocr-$(date +%Y%m%d)-$(whoami | tr '.' '-')"
gcloud projects create $PROJECT_ID --name="Kindle OCR Project"

# 作成したプロジェクトを設定
gcloud config set project $PROJECT_ID

# プロジェクトIDを確認・保存
echo "作成されたプロジェクトID: $PROJECT_ID"
echo $PROJECT_ID > project_id.txt
```

#### 方法2: 既存プロジェクト使用
```bash
# 利用可能なプロジェクト一覧を表示
gcloud projects list

# 既存プロジェクトを設定（プロジェクトIDを実際の値に置き換え）
gcloud config set project YOUR_EXISTING_PROJECT_ID
```

### 3.3 課金設定の確認

**重要**: Google Cloud Vision APIは有料サービスです。

```bash
# 課金アカウントの確認
gcloud billing accounts list

# プロジェクトの課金設定確認
gcloud billing projects describe $(gcloud config get-value project)
```

**課金アカウントが未設定の場合:**
1. [Google Cloud Console](https://console.cloud.google.com/billing) にアクセス
2. 課金アカウントを作成
3. プロジェクトにリンク

### 3.4 必要なAPIの有効化

```bash
# 現在のプロジェクトIDを確認
gcloud config get-value project

# 必要なAPIを有効化
gcloud services enable vision.googleapis.com
gcloud services enable drive.googleapis.com
gcloud services enable docs.googleapis.com

# 有効化されたAPIの確認
gcloud services list --enabled --filter="name:(vision OR drive OR docs)"
```

### 3.5 サービスアカウント作成とキーファイル配置

```bash
# 現在のプロジェクトIDを取得
PROJECT_ID=$(gcloud config get-value project)

# サービスアカウント作成
gcloud iam service-accounts create kindle-ocr-service \
    --display-name="Kindle OCR Service Account" \
    --description="Service account for Kindle OCR automation"

# プロジェクトディレクトリに移動（重要）
cd /path/to/your/kindle-ocr-project  # kindle_ocr_automation.scptがあるディレクトリ

# サービスアカウントキーをプロジェクトディレクトリに生成
gcloud iam service-accounts keys create ./kindle-ocr-service-account.json \
    --iam-account=kindle-ocr-service@${PROJECT_ID}.iam.gserviceaccount.com

# キーファイルの権限設定
chmod 600 ./kindle-ocr-service-account.json

# 作成確認
echo "サービスアカウント: kindle-ocr-service@${PROJECT_ID}.iam.gserviceaccount.com"
echo "キーファイル: $(pwd)/kindle-ocr-service-account.json"
ls -la kindle-ocr-service-account.json
```

## 4. Google Drive設定

### 4.1 アップロード先フォルダ作成

1. **Google Drive**にアクセス: https://drive.google.com/
2. **新規フォルダ作成**: `Kindle_OCR_Output` (任意の名前)
3. **フォルダを右クリック** → **共有**
4. **サービスアカウントのメールアドレス**を追加:
   ```bash
   # サービスアカウントのメールアドレスを表示
   PROJECT_ID=$(gcloud config get-value project)
   echo "kindle-ocr-service@${PROJECT_ID}.iam.gserviceaccount.com"
   ```
5. **権限**: 編集者
6. **フォルダIDを取得**: URLの`/folders/`以降の文字列

```
例: https://drive.google.com/drive/folders/1ABC123DEF456GHI789
フォルダID: 1ABC123DEF456GHI789
```

## 5. 設定ファイルの準備

### 5.1 .envrcファイルの作成

```bash
# プロジェクトディレクトリで.envrcファイルを作成
cat > .envrc << 'EOF'
#!/bin/bash

# プロジェクト基本設定
export KINDLE_OCR_PROJECT_ROOT="$(pwd)"
export GOOGLE_APPLICATION_CREDENTIALS="${KINDLE_OCR_PROJECT_ROOT}/kindle-ocr-service-account.json"

# Google Cloud設定（実際の値に置き換えてください）
export GOOGLE_CLOUD_PROJECT="YOUR_PROJECT_ID"
export KINDLE_OCR_DRIVE_FOLDER_ID="YOUR_DRIVE_FOLDER_ID"

# AppleScript設定
export KINDLE_OCR_PAGES="200"
export KINDLE_OCR_KEY_CODE="32"
export KINDLE_OCR_CAPTURE_RECT="50,100,1500,850"
export KINDLE_OCR_SCREENSHOT_DELAY="0.3"
export KINDLE_OCR_PAGE_DELAY="0.2"

# Python OCR設定
export KINDLE_OCR_DOC_NAME_PREFIX="Kindle_OCR_Output"
export KINDLE_OCR_DOC_NAME_LENGTH="20"
export KINDLE_OCR_ADD_TIMESTAMP="false"
export KINDLE_OCR_CREATE_PDF="true"
export KINDLE_OCR_PDF_NAME="kindle_output.pdf"
export KINDLE_OCR_TEXT_NAME="ocr_output.txt"
export KINDLE_OCR_SERVICE_ACCOUNT_FILE="kindle-ocr-service-account.json"

# Python仮想環境の自動アクティベーション
if [[ -d "${KINDLE_OCR_PROJECT_ROOT}/kindle_ocr_env" ]]; then
    source "${KINDLE_OCR_PROJECT_ROOT}/kindle_ocr_env/bin/activate"
fi

echo "Kindle OCR環境変数が設定されました"
echo "プロジェクトルート: ${KINDLE_OCR_PROJECT_ROOT}"
echo "Google Cloud プロジェクト: ${GOOGLE_CLOUD_PROJECT}"
EOF

# direnvを許可
direnv allow

# 設定確認
direnv status
```

### 5.2 環境変数の設定

```bash
# 実際の値を設定（以下の値を実際の値に置き換え）
PROJECT_ID=$(gcloud config get-value project)
DRIVE_FOLDER_ID="YOUR_ACTUAL_DRIVE_FOLDER_ID"  # 実際のフォルダIDに置き換え

# .envrcファイルを更新
sed -i '' "s/YOUR_PROJECT_ID/${PROJECT_ID}/g" .envrc
sed -i '' "s/YOUR_DRIVE_FOLDER_ID/${DRIVE_FOLDER_ID}/g" .envrc

# 設定を再読み込み
direnv reload

# 環境変数確認
echo "プロジェクトID: $GOOGLE_CLOUD_PROJECT"
echo "認証ファイル: $GOOGLE_APPLICATION_CREDENTIALS"
echo "DriveフォルダID: $KINDLE_OCR_DRIVE_FOLDER_ID"
```

### 5.3 環境変数一覧

| 環境変数名 | 説明 | デフォルト値 | 必須 |
|-----------|------|-------------|------|
| `GOOGLE_CLOUD_PROJECT` | Google CloudプロジェクトID | - | ✅ |
| `KINDLE_OCR_DRIVE_FOLDER_ID` | Google DriveフォルダID | - | ✅ |
| `GOOGLE_APPLICATION_CREDENTIALS` | 認証ファイルパス | `./kindle-ocr-service-account.json` | ✅ |
| `KINDLE_OCR_PAGES` | スクリーンショット数 | `200` | - |
| `KINDLE_OCR_KEY_CODE` | ページめくりキーコード | `28` (左矢印) | - |
| `KINDLE_OCR_CAPTURE_RECT` | キャプチャ範囲 | `50,100,1500,850` | - |
| `KINDLE_OCR_SCREENSHOT_DELAY` | スクリーンショット間隔(秒) | `0.3` | - |
| `KINDLE_OCR_PAGE_DELAY` | ページめくり間隔(秒) | `0.2` | - |
| `KINDLE_OCR_DOC_NAME_PREFIX` | ドキュメント名プレフィックス | `Kindle_OCR_Output` | - |
| `KINDLE_OCR_DOC_NAME_LENGTH` | ドキュメント名文字数 | `20` | - |
| `KINDLE_OCR_ADD_TIMESTAMP` | タイムスタンプ追加 | `false` | - |
| `KINDLE_OCR_CREATE_PDF` | PDF作成 | `true` | - |
| `KINDLE_OCR_PDF_NAME` | PDFファイル名 | `kindle_output.pdf` | - |
| `KINDLE_OCR_TEXT_NAME` | テキストファイル名 | `ocr_output.txt` | - |

## 6. 権限とセキュリティ設定

### 6.1 macOS権限設定

1. **システム設定** → **プライバシーとセキュリティ**
2. **プライバシー**タブで以下を設定:

**画面収録**:
- Script Editor
- Terminal (必要に応じて)

**アクセシビリティ**:
- Script Editor
- System Events

### 6.2 Kindleアプリ設定

```bash
# Amazon Kindleアプリインストール確認
ls /Applications/ | grep -i kindle

# 未インストールの場合、Mac App Storeからインストール
open "macappstore://apps.apple.com/app/kindle/id405399194"
```

## 7. 動作テスト

### 7.1 環境確認スクリプト

```bash
# 環境確認スクリプトを作成
cat > test_environment.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

def test_environment():
    print("=== Kindle OCR 環境テスト ===")

    # 1. 必須環境変数確認
    required_vars = [
        'GOOGLE_CLOUD_PROJECT',
        'KINDLE_OCR_DRIVE_FOLDER_ID',
        'GOOGLE_APPLICATION_CREDENTIALS'
    ]

    for var in required_vars:
        value = os.environ.get(var)
        if value:
            print(f"✅ {var}: {value}")
        else:
            print(f"❌ {var}: 未設定")
            return False

    # 2. オプション環境変数確認
    optional_vars = [
        'KINDLE_OCR_PAGES',
        'KINDLE_OCR_CAPTURE_RECT',
        'KINDLE_OCR_DOC_NAME_PREFIX'
    ]

    print("\n--- オプション設定 ---")
    for var in optional_vars:
        value = os.environ.get(var, 'デフォルト値使用')
        print(f"📋 {var}: {value}")

    # 3. 認証ファイル存在確認
    credentials_path = Path(os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'))
    if credentials_path.exists():
        print(f"✅ 認証ファイル: 存在 ({credentials_path})")
    else:
        print(f"❌ 認証ファイル: 見つからない ({credentials_path})")
        return False

    # 4. AppleScriptファイル確認
    script_path = Path.cwd() / 'kindle_ocr_automation.scpt'
    if script_path.exists():
        print("✅ AppleScriptファイル: 存在")
    else:
        print("❌ AppleScriptファイル: 見つからない")
        return False

    # 5. Google Cloud Vision API テスト
    try:
        from google.cloud import vision_v1
        client = vision_v1.ImageAnnotatorClient()
        print("✅ Vision API: 接続成功")
    except Exception as e:
        print(f"❌ Vision API: エラー - {e}")
        return False

    # 6. Google Drive API テスト
    try:
        from googleapiclient.discovery import build
        from google.oauth2 import service_account

        credentials = service_account.Credentials.from_service_account_file(
            str(credentials_path),
            scopes=['https://www.googleapis.com/auth/drive.file']
        )
        service = build('drive', 'v3', credentials=credentials)
        print("✅ Drive API: 接続成功")
    except Exception as e:
        print(f"❌ Drive API: エラー - {e}")
        return False

    # 7. img2pdf確認
    import subprocess
    try:
        result = subprocess.run(['img2pdf', '--version'], capture_output=True, text=True)
        print("✅ img2pdf: インストール済み")
    except FileNotFoundError:
        print("❌ img2pdf: 見つからない")
        return False

    print("\n🎉 すべてのテストが成功しました！")
    return True

if __name__ == "__main__":
    success = test_environment()
    sys.exit(0 if success else 1)
EOF

# テスト実行
python3 test_environment.py
```

### 7.2 スクリーンショットテスト

```bash
# テスト用AppleScriptを作成
cat > test_screenshot.scpt << 'EOF'
set testPath to (POSIX path of (path to desktop folder)) & "test_screenshot.png"
do shell script "screencapture -R 50,100,1500,850 " & quoted form of testPath
display dialog "テストスクリーンショットが作成されました: " & testPath buttons {"OK"} default button "OK"
EOF

# テスト実行
osascript test_screenshot.scpt
```

## 8. 最終確認

### ファイル構成の確認

```bash
# プロジェクトディレクトリの構成確認
ls -la

# 期待される構成:
# ├── .envrc                           # 環境変数設定（新規）
# ├── .gitignore
# ├── README.md
# ├── kindle_ocr_automation.scpt
# ├── kindle-ocr-service-account.json  # 認証ファイル
# ├── kindle_ocr_env/                  # 仮想環境
# └── test_environment.py              # テストスクリプト
```

### 環境変数確認

```bash
# direnv環境確認
direnv status

# 重要な環境変数確認
echo "=== 環境変数確認 ==="
echo "プロジェクトルート: $KINDLE_OCR_PROJECT_ROOT"
echo "プロジェクトID: $GOOGLE_CLOUD_PROJECT"
echo "認証ファイル: $GOOGLE_APPLICATION_CREDENTIALS"
echo "DriveフォルダID: $KINDLE_OCR_DRIVE_FOLDER_ID"
echo "スクリーンショット数: $KINDLE_OCR_PAGES"
echo "キャプチャ範囲: $KINDLE_OCR_CAPTURE_RECT"
echo "====================="
```

## 9. トラブルシューティング

### よくある問題と解決方法

**1. 認証ファイルが見つからない**
```bash
# 認証ファイルの確認
ls -la kindle-ocr-service-account.json

# 再作成が必要な場合
PROJECT_ID=$(gcloud config get-value project)
gcloud iam service-accounts keys create ./kindle-ocr-service-account.json \
    --iam-account=kindle-ocr-service@${PROJECT_ID}.iam.gserviceaccount.com
```

**2. プロジェクトIDエラー**
```bash
# プロジェクトIDの確認
gcloud projects list
gcloud config get-value project

# プロジェクトの再設定
gcloud config set project YOUR_ACTUAL_PROJECT_ID
```

**3. 課金設定エラー**
```bash
# 課金設定の確認
gcloud billing projects describe $(gcloud config get-value project)

# 課金アカウントのリンク（必要に応じて）
gcloud billing projects link $(gcloud config get-value project) --billing-account=BILLING_ACCOUNT_ID
```

**4. API有効化エラー**
```bash
# APIの状態確認
gcloud services list --available --filter="name:(vision OR drive OR docs)"
gcloud services list --enabled --filter="name:(vision OR drive OR docs)"

# APIの再有効化
gcloud services enable vision.googleapis.com --project=$(gcloud config get-value project)
gcloud services enable drive.googleapis.com --project=$(gcloud config get-value project)
gcloud services enable docs.googleapis.com --project=$(gcloud config get-value project)
```

**5. 権限エラー**
```bash
# サービスアカウントの権限確認
gcloud projects get-iam-policy $(gcloud config get-value project)

# 必要に応じて権限付与
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
    --member="serviceAccount:kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com" \
    --role="roles/editor"
```

**6. Python仮想環境の問題**
```bash
# 仮想環境の再作成
deactivate  # 現在の仮想環境を終了
rm -rf kindle_ocr_env
python3 -m venv kindle_ocr_env
source kindle_ocr_env/bin/activate
pip install --upgrade pip
pip install google-cloud-vision google-api-python-client google-auth google-auth-oauthlib google-auth-httplib2 img2pdf
```

**7. macOS権限の問題**
```bash
# Script Editorの権限確認
# システム設定 → プライバシーとセキュリティ → プライバシー → 画面収録
# システム設定 → プライバシーとセキュリティ → プライバシー → アクセシビリティ

# 権限をリセットする場合
sudo tccutil reset ScreenCapture
sudo tccutil reset Accessibility
```

**8. Google Drive フォルダIDの確認**
```bash
# フォルダIDが正しく設定されているか確認
# Google DriveのフォルダURLから取得:
# https://drive.google.com/drive/folders/1ABC123DEF456GHI789
# フォルダID: 1ABC123DEF456GHI789

# AppleScriptファイル内の設定確認
grep "DRIVE_FOLDER_ID" kindle_ocr_automation.scpt
```

## 10. セキュリティ考慮事項

### 認証情報の保護
```bash
# サービスアカウントキーの権限設定
chmod 600 ./kindle-ocr-service-account.json

# .gitignoreで認証情報を除外（既に設定済み）
grep "kindle-ocr-service-account.json" .gitignore
```

### 定期的なメンテナンス
```bash
# サービスアカウントキーの一覧表示
gcloud iam service-accounts keys list \
    --iam-account=kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com

# 古いキーの削除（90日後など）
# gcloud iam service-accounts keys delete KEY_ID \
#     --iam-account=kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com

# プロジェクトの使用量確認
gcloud logging read "resource.type=api" --limit=10 --project=$(gcloud config get-value project)
```

## 11. 実行方法

### スクリプトの実行
```bash
# 1. プロジェクトディレクトリに移動（direnvが自動で環境変数を設定）
cd /path/to/your/kindle-ocr-project

# 2. 環境変数が設定されていることを確認
echo "DriveフォルダID: $KINDLE_OCR_DRIVE_FOLDER_ID"

# 3. Kindleアプリで読みたい本を開く
# 4. 読み始めたいページを表示
# 5. AppleScriptを実行

# Script Editorから実行
open kindle_ocr_automation.scpt

# コマンドラインから実行
osascript kindle_ocr_automation.scpt
```

### 実行前のチェックリスト
- [ ] プロジェクトディレクトリにいる（`direnv status`で確認）
- [ ] 環境変数が設定されている（`echo $KINDLE_OCR_DRIVE_FOLDER_ID`で確認）
- [ ] Kindleアプリが起動している
- [ ] 読み取りたい本が開かれている
- [ ] 開始ページが表示されている
- [ ] Google Driveフォルダが共有設定されている

## 12. カスタマイズ

### 設定のカスタマイズ
`.envrc`ファイルを編集して設定をカスタマイズ：

```bash
# .envrcファイルを編集
nano .envrc

# 主要な設定項目:
# export KINDLE_OCR_PAGES="200"                    # スクリーンショット数
# export KINDLE_OCR_CAPTURE_RECT="50,100,1500,850" # キャプチャ範囲
# export KINDLE_OCR_SCREENSHOT_DELAY="0.3"         # スクリーンショット間隔
# export KINDLE_OCR_PAGE_DELAY="0.2"               # ページめくり間隔

# 設定変更後は再読み込み
direnv reload
```

### よく使用するカスタマイズ例

#### 1. 高速処理設定
```bash
# .envrcに追加
export KINDLE_OCR_PAGES="50"                # 少ないページ数でテスト
export KINDLE_OCR_SCREENSHOT_DELAY="0.1"    # 高速スクリーンショット
export KINDLE_OCR_PAGE_DELAY="0.1"          # 高速ページめくり
export KINDLE_OCR_CREATE_PDF="false"        # PDF作成をスキップ
```

#### 2. 高品質処理設定
```bash
# .envrcに追加
export KINDLE_OCR_SCREENSHOT_DELAY="0.5"    # 安定したスクリーンショット
export KINDLE_OCR_PAGE_DELAY="0.3"          # 安定したページめくり
export KINDLE_OCR_ADD_TIMESTAMP="true"      # タイムスタンプ付きファイル名
```

#### 3. カスタムキャプチャ範囲
```bash
# 異なる画面サイズ・解像度に対応
export KINDLE_OCR_CAPTURE_RECT="100,150,1400,800"  # 大きめの範囲
export KINDLE_OCR_CAPTURE_RECT="30,80,1200,700"    # 小さめの範囲
```

#### 4. 右から左読み設定（漫画など）
```bash
# .envrcに追加
export KINDLE_OCR_KEY_CODE="29"  # 右矢印キー（通常は28=左矢印）
```

### 環境別設定の管理

#### 開発環境用設定
```bash
# .envrc.development として保存
cp .envrc .envrc.development

# 開発用設定を編集
cat >> .envrc.development << 'EOF'
# 開発環境用設定
export KINDLE_OCR_PAGES="10"
export KINDLE_OCR_DOC_NAME_PREFIX="TEST_Kindle_OCR"
export KINDLE_OCR_CREATE_PDF="false"
EOF

# 開発環境使用時
cp .envrc.development .envrc
direnv reload
```

#### 本番環境用設定
```bash
# .envrc.production として保存
cp .envrc .envrc.production

# 本番用設定を編集
cat >> .envrc.production << 'EOF'
# 本番環境用設定
export KINDLE_OCR_PAGES="500"
export KINDLE_OCR_ADD_TIMESTAMP="true"
export KINDLE_OCR_CREATE_PDF="true"
EOF

# 本番環境使用時
cp .envrc.production .envrc
direnv reload
```

### 使用量とコスト管理

#### APIコスト監視
```bash
# Google Cloud Vision APIの使用量確認
gcloud logging read "resource.type=api AND protoPayload.serviceName=vision.googleapis.com" \
    --limit=50 --project=$GOOGLE_CLOUD_PROJECT --format="table(timestamp,protoPayload.methodName)"

# 課金情報の確認
gcloud billing budgets list --billing-account=$(gcloud billing accounts list --format="value(name)" --limit=1)
```

#### コスト削減設定
```bash
# .envrcに追加（コスト重視）
export KINDLE_OCR_PAGES="100"               # ページ数制限
export KINDLE_OCR_CREATE_PDF="false"        # PDF作成無効
export KINDLE_OCR_DOC_NAME_LENGTH="10"      # 短いファイル名
```

### トラブルシューティング用設定

#### デバッグモード
```bash
# .envrcに追加
export KINDLE_OCR_DEBUG="true"
export KINDLE_OCR_VERBOSE="true"
export KINDLE_OCR_KEEP_TEMP_FILES="true"    # 一時ファイルを保持
```

#### テスト用最小設定
```bash
# .envrc.test として保存
cat > .envrc.test << 'EOF'
#!/bin/bash
export KINDLE_OCR_PROJECT_ROOT="$(pwd)"
export GOOGLE_APPLICATION_CREDENTIALS="${KINDLE_OCR_PROJECT_ROOT}/kindle-ocr-service-account.json"
export GOOGLE_CLOUD_PROJECT="YOUR_PROJECT_ID"
export KINDLE_OCR_DRIVE_FOLDER_ID="YOUR_DRIVE_FOLDER_ID"
export KINDLE_OCR_PAGES="3"
export KINDLE_OCR_CREATE_PDF="false"
export KINDLE_OCR_DOC_NAME_PREFIX="TEST"
EOF

# テスト実行時
cp .envrc.test .envrc
direnv reload
```

### 設定の検証

#### 設定値確認スクリプト
```bash
# 設定確認用スクリプト作成
cat > check_config.sh << 'EOF'
#!/bin/bash
echo "=== Kindle OCR 設定確認 ==="
echo "プロジェクトルート: $KINDLE_OCR_PROJECT_ROOT"
echo "プロジェクトID: $GOOGLE_CLOUD_PROJECT"
echo "DriveフォルダID: $KINDLE_OCR_DRIVE_FOLDER_ID"
echo "スクリーンショット数: $KINDLE_OCR_PAGES"
echo "キャプチャ範囲: $KINDLE_OCR_CAPTURE_RECT"
echo "スクリーンショット間隔: $KINDLE_OCR_SCREENSHOT_DELAY秒"
echo "ページめくり間隔: $KINDLE_OCR_PAGE_DELAY秒"
echo "PDF作成: $KINDLE_OCR_CREATE_PDF"
echo "タイムスタンプ追加: $KINDLE_OCR_ADD_TIMESTAMP"
echo "=========================="
EOF

chmod +x check_config.sh
./check_config.sh
```

### 設定のバックアップと復元

#### 設定バックアップ
```bash
# 現在の設定をバックアップ
cp .envrc .envrc.backup.$(date +%Y%m%d_%H%M%S)

# バックアップ一覧確認
ls -la .envrc.backup.*
```

#### 設定復元
```bash
# 最新のバックアップから復元
latest_backup=$(ls -t .envrc.backup.* | head -1)
cp "$latest_backup" .envrc
direnv reload
echo "設定を復元しました: $latest_backup"
```
