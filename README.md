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

### 5.1 AppleScriptコードの設定値更新

`kindle_ocr_automation.scpt`をテキストエディタで開き、以下の値を実際の値に置き換え:

```python
# Pythonスクリプト内の設定値（行番号: 約80行目付近）
DRIVE_FOLDER_ID = 'YOUR_FOLDER_ID'  # 実際のフォルダIDに置き換え
```

**具体的な手順:**
1. Script Editorで`kindle_ocr_automation.scpt`を開く
2. `DRIVE_FOLDER_ID = 'YOUR_FOLDER_ID'`の行を見つける
3. `YOUR_FOLDER_ID`を実際のGoogle DriveフォルダIDに置き換え
4. ファイルを保存

### 5.2 環境変数設定（オプション）

```bash
# プロジェクトディレクトリのパスを取得
PROJECT_DIR=$(pwd)
PROJECT_ID=$(gcloud config get-value project)

# ~/.zshrc に環境変数を追加
cat >> ~/.zshrc << EOF

# Kindle OCR 設定
export GOOGLE_APPLICATION_CREDENTIALS="${PROJECT_DIR}/kindle-ocr-service-account.json"
export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export KINDLE_OCR_PROJECT_DIR="${PROJECT_DIR}"
EOF

# 設定を反映
source ~/.zshrc

# 設定確認
echo "認証情報: $GOOGLE_APPLICATION_CREDENTIALS"
echo "プロジェクトID: $GOOGLE_CLOUD_PROJECT"
echo "プロジェクトディレクトリ: $KINDLE_OCR_PROJECT_DIR"
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
# プロジェクトディレクトリで実行
cd /path/to/your/kindle-ocr-project  # kindle_ocr_automation.scptがあるディレクトリ

# 環境確認スクリプトを作成
cat > test_environment.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

def test_environment():
    print("=== Kindle OCR 環境テスト ===")
    
    # 1. プロジェクトディレクトリ確認
    project_dir = Path.cwd()
    print(f"プロジェクトディレクトリ: {project_dir}")
    
    # 2. 認証ファイル存在確認
    credentials_path = project_dir / 'kindle-ocr-service-account.json'
    if credentials_path.exists():
        print("✅ 認証ファイル: 存在")
        print(f"   パス: {credentials_path}")
    else:
        print("❌ 認証ファイル: 見つからない")
        print(f"   期待パス: {credentials_path}")
        return False
    
    # 3. AppleScriptファイル確認
    script_path = project_dir / 'kindle_ocr_automation.scpt'
    if script_path.exists():
        print("✅ AppleScriptファイル: 存在")
    else:
        print("❌ AppleScriptファイル: 見つからない")
        return False
    
    # 4. Google Cloud Vision API テスト
    try:
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = str(credentials_path)
        from google.cloud import vision_v1
        client = vision_v1.ImageAnnotatorClient()
        print("✅ Vision API: 接続成功")
    except Exception as e:
        print(f"❌ Vision API: エラー - {e}")
        return False
    
    # 5. Google Drive API テスト
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
    
    # 6. img2pdf確認
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

### ファイル構成の確認

```bash
# プロジェクトディレクトリの構成確認
ls -la

# 期待される構成:
# ├── .gitignore
# ├── README.md
# ├── kindle_ocr_automation.scpt
# ├── kindle-ocr-service-account.json  # 新規作成
# ├── kindle_ocr_env/                  # 仮想環境
# └── project_id.txt                   # プロジェクトID記録
```

### 設定情報の確認

```bash
# 重要な設定情報を表示
echo "=== Kindle OCR プロジェクト設定情報 ==="
echo "プロジェクトディレクトリ: $(pwd)"
echo "プロジェクトID: $(gcloud config get-value project)"
echo "サービスアカウント: kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com"
echo "認証キーファイル: $(pwd)/kindle-ocr-service-account.json"
echo "========================================"

# 設定をファイルに保存
cat > kindle_ocr_config.txt << EOF
プロジェクトディレクトリ: $(pwd)
プロジェクトID: $(gcloud config get-value project)
サービスアカウント: kindle-ocr-service@$(gcloud config get-value project).iam.gserviceaccount.com
認証キーファイル: $(pwd)/kindle-ocr-service-account.json
作成日: $(date)
EOF

echo "設定情報をkindle_ocr_config.txtに保存しました"
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
# 1. Kindleアプリで読みたい本を開く
# 2. 読み始めたいページを表示
# 3. AppleScriptを実行

# Script Editorから実行
open kindle_ocr_automation.scpt

# コマンドラインから実行
osascript kindle_ocr_automation.scpt
```

### 実行前のチェックリスト
- [ ] Kindleアプリが起動している
- [ ] 読み取りたい本が開かれている
- [ ] 開始ページが表示されている
- [ ] Google Driveフォルダが共有設定されている
- [ ] 仮想環境がアクティブになっている（`source kindle_ocr_env/bin/activate`）

### 実行後の確認
- デスクトップに一時フォルダ `Kindle_Screenshots_YYYYMMDD_HHMMSS` が作成される
- Google Driveの指定フォルダにドキュメントがアップロードされる
- 処理完了後、一時ファイルは自動削除される

## 12. カスタマイズ

### 設定のカスタマイズ
AppleScript内の設定値を変更可能：

```applescript
-- 設定値（kindle_ocr_automation.scpt の上部）
property PAGES : 200                    -- スクリーンショット数
property CAPTURE_RECT : "50,100,1500,850"  -- キャプチャ範囲
property SCREENSHOT_DELAY : 0.3         -- スクリーンショット間隔
property PAGE_DELAY : 0.2               -- ページめくり間隔
```

### 使用量とコスト管理
```bash
# Google Cloud Vision APIの使用量確認
gcloud logging read "resource.type=api AND protoPayload.serviceName=vision.googleapis.com" \
    --limit=50 --project=$(gcloud config get-value project)

# 課金情報の確認
gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID
```

