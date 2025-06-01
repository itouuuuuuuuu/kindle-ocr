# Kindle OCRスクリプト実行環境構築ガイド

## 1. 前提条件の確認

### システム要件
- **macOS** (AppleScript使用のため)
- **Python 3.8以上**
- **インターネット接続** (Google API使用)

```bash
# Python バージョン確認
python3 --version

# Homebrewインストール確認（未インストールの場合）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## 2. Python環境とライブラリのセットアップ

### 必要ライブラリのインストール

```bash
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

### 3.1 GCPプロジェクト作成

1. **Google Cloud Console**にアクセス: https://console.cloud.google.com/
2. **新しいプロジェクトを作成**
   - プロジェクト名: `kindle-ocr-project` (任意)
   - プロジェクトIDをメモ

### 3.2 必要なAPIの有効化

```bash
# Google Cloud CLI インストール（未インストールの場合）
brew install google-cloud-sdk

# 認証
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# 必要なAPIを有効化
gcloud services enable vision.googleapis.com
gcloud services enable drive.googleapis.com
gcloud services enable docs.googleapis.com
```

または、**Cloud Console**で手動有効化:
1. **APIとサービス** → **ライブラリ**
2. 以下を検索して有効化:
   - Cloud Vision API
   - Google Drive API
   - Google Docs API

### 3.3 サービスアカウント作成

```bash
# サービスアカウント作成
gcloud iam service-accounts create kindle-ocr-service \
    --display-name="Kindle OCR Service Account"

# サービスアカウントキー生成
gcloud iam service-accounts keys create ~/kindle-ocr-service-account.json \
    --iam-account=kindle-ocr-service@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

**手動作成の場合:**
1. **IAMと管理** → **サービスアカウント**
2. **サービスアカウントを作成**
3. 名前: `kindle-ocr-service`
4. **キーを作成** → **JSON形式**でダウンロード

## 4. Google Drive設定

### 4.1 アップロード先フォルダ作成

1. **Google Drive**にアクセス: https://drive.google.com/
2. **新規フォルダ作成**: `Kindle_OCR_Output` (任意の名前)
3. **フォルダを右クリック** → **共有**
4. **サービスアカウントのメールアドレス**を追加:
   ```
   kindle-ocr-service@YOUR_PROJECT_ID.iam.gserviceaccount.com
   ```
5. **権限**: 編集者
6. **フォルダIDを取得**: URLの`/folders/`以降の文字列

```
例: https://drive.google.com/drive/folders/1ABC123DEF456GHI789
フォルダID: 1ABC123DEF456GHI789
```

## 5. 設定ファイルの準備

### 5.1 設定値の更新

AppleScriptコード内の以下の値を実際の値に置き換え:

```python
# Pythonスクリプト内の設定値
SERVICE_ACCOUNT_FILE = '/Users/YOUR_USERNAME/kindle-ocr-service-account.json'  # 実際のパス
DRIVE_FOLDER_ID = '1ABC123DEF456GHI789'  # 実際のフォルダID
```

### 5.2 環境変数設定（オプション）

```bash
# ~/.zshrc または ~/.bash_profile に追加
export GOOGLE_APPLICATION_CREDENTIALS="/Users/YOUR_USERNAME/kindle-ocr-service-account.json"
export KINDLE_OCR_FOLDER_ID="1ABC123DEF456GHI789"

# 設定を反映
source ~/.zshrc
```

## 6. 権限とセキュリティ設定

### 6.1 macOS権限設定

1. **システム環境設定** → **セキュリティとプライバシー**
2. **プライバシー**タブ
3. **画面収録**に以下を追加:
   - Script Editor
   - Terminal (必要に応じて)
4. **アクセシビリティ**に以下を追加:
   - Script Editor
   - System Events

### 6.2 Kindleアプリ設定

```bash
# Amazon Kindleアプリインストール確認
ls /Applications/ | grep -i kindle

# 未インストールの場合、Mac App Storeからインストール
```

## 7. 動作テスト

### 7.1 個別コンポーネントテスト

```bash
# Google Cloud Vision API テスト
python3 -c "
from google.cloud import vision_v1
import os
os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = '/path/to/your/service-account.json'
client = vision_v1.ImageAnnotatorClient()
print('Vision API: OK')
"

# Google Drive API テスト
python3 -c "
from googleapiclient.discovery import build
from google.oauth2 import service_account
credentials = service_account.Credentials.from_service_account_file('/path/to/your/service-account.json')
service = build('drive', 'v3', credentials=credentials)
print('Drive API: OK')
"
```

### 7.2 スクリーンショットテスト

```applescript
-- 簡単なテストスクリプト
set testPath to (POSIX path of (path to desktop folder)) & "test_screenshot.png"
do shell script "screencapture -R 50,100,1500,850 " & quoted form of testPath
display dialog "テストスクリーンショットが作成されました: " & testPath
```

## 8. トラブルシューティング

### よくある問題と解決方法

**1. 権限エラー**
```bash
# サービスアカウントの権限確認
gcloud projects get-iam-policy YOUR_PROJECT_ID
```

**2. API制限エラー**
```bash
# API使用量確認
gcloud logging read "resource.type=api" --limit=10
```

**3. パッケージインストールエラー**
```bash
# 仮想環境の再作成
deactivate
rm -rf kindle_ocr_env
python3 -m venv kindle_ocr_env
source kindle_ocr_env/bin/activate
```

## 9. セキュリティ考慮事項

### 認証情報の保護
```bash
# サービスアカウントキーの権限設定
chmod 600 ~/kindle-ocr-service-account.json

# 環境変数での管理（推奨）
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/kindle-ocr-service-account.json"
```

### 定期的なキーローテーション
```bash
# 古いキーの削除（90日後など）
gcloud iam service-accounts keys list --iam-account=kindle-ocr-service@YOUR_PROJECT_ID.iam.gserviceaccount.com
gcloud iam service-accounts keys delete KEY_ID --iam-account=kindle-ocr-service@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

