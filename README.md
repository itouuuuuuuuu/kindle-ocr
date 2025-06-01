# Kindle OCRスクリプト実行環境構築ガイド

## 1. 前提条件の確認

### システム要件
- **macOS** (AppleScript使用のため)
- **Python 3.8以上**
- **インターネット接続** (Google API使用)
- **Google アカウント** (Google Cloud Platform使用)

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

### 3.5 サービスアカウント作成

```bash
# 現在のプロジェクトIDを取得
PROJECT_ID=$(gcloud config get-value project)

# サービスアカウント作成
gcloud iam service-accounts create kindle-ocr-service \
    --display-name="Kindle OCR Service Account" \
    --description="Service account for Kindle OCR automation"

# サービスアカウントキー生成
gcloud iam service-accounts keys create ~/kindle-ocr-service-account.json \
    --iam-account=kindle-ocr-service@${PROJECT_ID}.iam.gserviceaccount.com

# キーファイルの権限設定
chmod 600 ~/kindle-ocr-service-account.json

# 作成確認
echo "サービスアカウント: kindle-ocr-service@${PROJECT_ID}.iam.gserviceaccount.com"
echo "キーファイル: ~/kindle-ocr-service-account.json"
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

### 5.1 AppleScriptコードの設定値更新

`kindle_ocr_automation.scpt`内の以下の値を実際の値に置き換え:

```python
# Pythonスクリプト内の設定値（実際のパスに置き換え）
SERVICE_ACCOUNT_FILE = '/Users/YOUR_USERNAME/kindle-ocr-service-account.json'
DRIVE_FOLDER_ID = '1ABC123DEF456GHI789'  # 実際のフォルダID
```

### 5.2 環境変数設定

```bash
# 現在のユーザー名とプロジェクトIDを取得
USERNAME=$(whoami)
PROJECT_ID=$(gcloud config get-value project)

# ~/.zshrc に環境変数を追加
cat >> ~/.zshrc << EOF

# Kindle OCR 設定
export GOOGLE_APPLICATION_CREDENTIALS="/Users/${USERNAME}/kindle-ocr-service-account.json"
export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export KINDLE_OCR_FOLDER_ID="YOUR_DRIVE_FOLDER_ID"  # 実際のフォルダIDに置き換え
EOF

# 設定を反映
source ~/.zshrc

# 設定確認
echo "認証情報: $GOOGLE_APPLICATION_CREDENTIALS"
echo "プロジェクトID: $GOOGLE_CLOUD_PROJECT"
```

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

def test_environment():
    print("=== Kindle OCR 環境テスト ===")
    
    # 1. 環境変数確認
    credentials_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
    project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
    
    print(f"認証情報パス: {credentials_path}")
    print(f"プロジェクトID: {project_id}")
    
    # 2. 認証ファイル存在確認
    if credentials_path and os.path.exists(credentials_path):
        print("✅ 認証ファイル: 存在")
    else:
        print("❌ 認証ファイル: 見つからない")
        return False
    
    # 3. Google Cloud Vision API テスト
    try:
        from google.cloud import vision_v1
        client = vision_v1.ImageAnnotatorClient()
        print("✅ Vision API: 接続成功")
    except Exception as e:
        print(f"❌ Vision API: エラー - {e}")
        return False
    
    # 4. Google Drive API テスト
    try:
        from googleapiclient.discovery import build
        from google.oauth2 import service_account
        
        credentials = service_account.Credentials.from_service_account_file(
            credentials_path,
            scopes=['https://www.googleapis.com/auth/drive.file']
        )
        service = build('drive', 'v3', credentials=credentials)
        print("✅ Drive API: 接続成功")
    except Exception as e:
        print(f"❌ Drive API: エラー - {e}")
        return False
    
    # 5. img2pdf確認
    import subprocess
    try:
        result = subprocess.run(['img2pdf', '--version'], capture_output=True, text=True)
        print("✅ img2pdf: インストール済み")
    except FileNotFoundError:
        print("❌ img2pdf: 見つからない")
        return False
    
    print("🎉 すべてのテストが成功しました！")
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

### 設定情報の確認

```bash
# 重要な設定情報を表示
echo "=== Kindle OCR プロジェクト設定情報 ==="
echo "プロジェクトID: $(gcloud config get-value project)"
echo "サービスアカウント: kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com"
echo "認証キーファイル: ~/kindle-ocr-service-account.json"
echo "環境変数GOOGLE_APPLICATION_CREDENTIALS: $GOOGLE_APPLICATION_CREDENTIALS"
echo "環境変数GOOGLE_CLOUD_PROJECT: $GOOGLE_CLOUD_PROJECT"
echo "========================================"

# 設定をファイルに保存
cat > kindle_ocr_config.txt << EOF
プロジェクトID: $(gcloud config get-value project)
サービスアカウント: kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com
認証キーファイル: ~/kindle-ocr-service-account.json
作成日: $(date)
EOF

echo "設定情報をkindle_ocr_config.txtに保存しました"
```

## 9. トラブルシューティング

### よくある問題と解決方法

**1. プロジェクトIDエラー**
```bash
# プロジェクトIDの確認
gcloud projects list
gcloud config get-value project

# プロジェクトの再設定
gcloud config set project YOUR_ACTUAL_PROJECT_ID
```

**2. 課金設定エラー**
```bash
# 課金設定の確認
gcloud billing projects describe $(gcloud config get-value project)

# 課金アカウントのリンク（必要に応じて）
gcloud billing projects link $(gcloud config get-value project) --billing-account=BILLING_ACCOUNT_ID
```

**3. API有効化エラー**
```bash
# APIの状態確認
gcloud services list --available --filter="name:(vision OR drive OR docs)"
gcloud services list --enabled --filter="name:(vision OR drive OR docs)"

# APIの再有効化
gcloud services enable vision.googleapis.com --project=$(gcloud config get-value project)
```

**4. 権限エラー**
```bash
# サービスアカウントの権限確認
gcloud projects get-iam-policy $(gcloud config get-value project)

# 必要に応じて権限付与
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
    --member="serviceAccount:kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com" \
    --role="roles/editor"
```

## 10. セキュリティ考慮事項

### 認証情報の保護
```bash
# サービスアカウントキーの権限設定
chmod 600 ~/kindle-ocr-service-account.json

# .gitignoreに認証情報を追加（既に設定済み）
echo "*.json" >> .gitignore
echo ".env*" >> .gitignore
```

### 定期的なメンテナンス
```bash
# サービスアカウントキーの一覧表示
gcloud iam service-accounts keys list \
    --iam-account=kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com

# 古いキーの削除（90日後など）
# gcloud iam service-accounts keys delete KEY_ID \
#     --iam-account=kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com
```
