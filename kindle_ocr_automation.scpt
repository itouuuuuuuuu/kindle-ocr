-- 設定値（環境変数から取得、デフォルト値も設定）
on getEnvVar(varName, defaultValue)
    try
        return do shell script "echo $" & varName
    on error
        return defaultValue
    end try
end getEnvVar

-- 環境変数から設定値を取得
property PAGES : (getEnvVar("KINDLE_OCR_PAGES", "200") as integer)
property KEY_LEFT : (ASCII character (getEnvVar("KINDLE_OCR_KEY_CODE", "28") as integer))
property CAPTURE_RECT : getEnvVar("KINDLE_OCR_CAPTURE_RECT", "50,100,1500,850")
property SCREENSHOT_DELAY : (getEnvVar("KINDLE_OCR_SCREENSHOT_DELAY", "0.3") as real)
property PAGE_DELAY : (getEnvVar("KINDLE_OCR_PAGE_DELAY", "0.2") as real)

-- メイン処理
on run
    set currentDate to do shell script "date +%Y%m%d_%H%M%S"
    set folderPath to (POSIX path of (path to desktop folder)) & "Kindle_Screenshots_" & currentDate & "/"

    -- フォルダ作成とスクリーンショット撮影
    createFolder(folderPath)
    tell application "Amazon Kindle" to activate
    set screenshotPaths to captureScreenshots(folderPath)

    -- OCR処理とアップロード
    if executePythonOCR(folderPath) then
        cleanup(screenshotPaths, folderPath)
        showMessage("処理が完了しました。OCR結果がGoogle Docsにアップロードされました。")
    else
        showMessage("エラーが発生しました。エラーログを確認してください。")
    end if
end run

-- フォルダ作成
on createFolder(folderPath)
    do shell script "mkdir -p " & quoted form of folderPath
end createFolder

-- スクリーンショット連続撮影
on captureScreenshots(folderPath)
    set screenshotPaths to {}

    repeat with i from 1 to PAGES
        set screenshotPath to folderPath & "screenshot_" & (i as string) & ".png"

        -- スクリーンショット撮影
        do shell script "screencapture -R " & CAPTURE_RECT & " " & quoted form of screenshotPath
        set end of screenshotPaths to screenshotPath

        delay SCREENSHOT_DELAY

        -- ページめくり（最後のページ以外）
        if i < PAGES then
            tell application "System Events"
                keystroke KEY_LEFT
                delay PAGE_DELAY
            end tell
        end if
    end repeat

    return screenshotPaths
end captureScreenshots

-- Python OCRスクリプト実行
on executePythonOCR(folderPath)
    set pythonScript to generatePythonScript(folderPath)
    set tempPythonFile to folderPath & "ocr_script.py"

    try
        -- Pythonスクリプト書き出し・実行
        do shell script "cat > " & quoted form of tempPythonFile & " << 'EOF'" & return & pythonScript & return & "EOF"
        do shell script "cd " & quoted form of folderPath & " && python3 ocr_script.py 2>&1"
        do shell script "rm " & quoted form of tempPythonFile
        return true
    on error errorMessage
        -- エラーログ保存
        do shell script "echo " & quoted form of errorMessage & " > " & quoted form of (folderPath & "error_log.txt")
        return false
    end try
end executePythonOCR

-- Pythonスクリプト生成
on generatePythonScript(folderPath)
    -- プロジェクトルートディレクトリ（このスクリプトがある場所）を取得
    set projectRoot to do shell script "dirname " & quoted form of (POSIX path of (path to me))

    return "#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
import subprocess
from pathlib import Path
from google.cloud import vision_v1
from google.oauth2 import service_account
from googleapiclient.discovery import build

def get_env_var(var_name, default_value=None, required=False):
    \"\"\"環境変数を取得\"\"\"
    value = os.environ.get(var_name, default_value)
    if required and not value:
        raise ValueError(f'必須の環境変数が設定されていません: {var_name}')
    return value

def get_project_root():
    \"\"\"プロジェクトルートディレクトリを取得\"\"\"
    # 環境変数から取得を試行
    project_root = get_env_var('KINDLE_OCR_PROJECT_ROOT')
    if project_root:
        return Path(project_root)

    # スクリプトから推定（フォールバック）
    return Path('" & projectRoot & "')

def get_service_account_file():
    \"\"\"サービスアカウントファイルのパスを取得\"\"\"
    # 環境変数から直接パス指定
    service_account_path = get_env_var('GOOGLE_APPLICATION_CREDENTIALS')
    if service_account_path:
        return Path(service_account_path)

    # プロジェクトルート内のデフォルトファイル
    project_root = get_project_root()
    default_file = project_root / get_env_var('KINDLE_OCR_SERVICE_ACCOUNT_FILE', 'kindle-ocr-service-account.json')
    return default_file

# 設定値を環境変数から取得
PROJECT_ROOT = get_project_root()
FOLDER_PATH = Path('" & folderPath & "')
SERVICE_ACCOUNT_FILE = get_service_account_file()
DRIVE_FOLDER_ID = get_env_var('KINDLE_OCR_DRIVE_FOLDER_ID', required=True)
DOC_NAME_PREFIX = get_env_var('KINDLE_OCR_DOC_NAME_PREFIX', 'Kindle_OCR_Output')
PDF_OUTPUT_NAME = get_env_var('KINDLE_OCR_PDF_NAME', 'kindle_output.pdf')
TEXT_OUTPUT_NAME = get_env_var('KINDLE_OCR_TEXT_NAME', 'ocr_output.txt')

# Google API設定
SCOPES = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/documents'
]

def setup_clients():
    \"\"\"Google API クライアント初期化\"\"\"
    if not SERVICE_ACCOUNT_FILE.exists():
        raise FileNotFoundError(f'サービスアカウントファイルが見つかりません: {SERVICE_ACCOUNT_FILE}')

    # 環境変数を設定（既に設定されていない場合）
    if not get_env_var('GOOGLE_APPLICATION_CREDENTIALS'):
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = str(SERVICE_ACCOUNT_FILE)

    credentials = service_account.Credentials.from_service_account_file(
        str(SERVICE_ACCOUNT_FILE),
        scopes=SCOPES
    )

    return {
        'vision': vision_v1.ImageAnnotatorClient(),
        'drive': build('drive', 'v3', credentials=credentials),
        'docs': build('docs', 'v1', credentials=credentials)
    }

def perform_batch_ocr(image_files, vision_client):
    \"\"\"バッチOCR処理\"\"\"
    ocr_text = ''
    total_files = len(image_files)

    for i, image_file in enumerate(sorted(image_files), 1):
        print(f'Processing ({i}/{total_files}): {image_file.name}')

        with open(image_file, 'rb') as f:
            image = vision_v1.Image(content=f.read())

        response = vision_client.text_detection(image=image)

        # エラーチェック
        if response.error.message:
            print(f'OCR Error for {image_file.name}: {response.error.message}')
            continue

        if response.text_annotations:
            ocr_text += response.text_annotations[0].description + '\\n\\n'

    return ocr_text.strip()

def create_google_doc(ocr_text, clients):
    \"\"\"Google Docs作成・アップロード\"\"\"
    # ファイル名生成
    name_length = int(get_env_var('KINDLE_OCR_DOC_NAME_LENGTH', '20'))
    safe_chars = ''.join(c for c in ocr_text[:name_length] if c.isalnum() or c in ' -_')
    doc_name = safe_chars.strip() or DOC_NAME_PREFIX

    # タイムスタンプ追加オプション
    if get_env_var('KINDLE_OCR_ADD_TIMESTAMP', 'false').lower() == 'true':
        from datetime import datetime
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        doc_name = f'{doc_name}_{timestamp}'

    print(f'Creating Google Doc: {doc_name}')

    # Google Docs作成
    file_metadata = {
        'name': doc_name,
        'parents': [DRIVE_FOLDER_ID],
        'mimeType': 'application/vnd.google-apps.document'
    }

    document = clients['drive'].files().create(body=file_metadata, fields='id').execute()
    doc_id = document['id']

    # テキスト挿入
    requests = [{'insertText': {'location': {'index': 1}, 'text': ocr_text}}]
    clients['docs'].documents().batchUpdate(documentId=doc_id, body={'requests': requests}).execute()

    doc_url = f'https://docs.google.com/document/d/{doc_id}'
    print(f'Document created: {doc_url}')

    # URLをファイルに保存
    url_file = FOLDER_PATH / 'google_doc_url.txt'
    with open(url_file, 'w') as f:
        f.write(doc_url)

    return doc_id

def create_pdf(image_files):
    \"\"\"PDF作成\"\"\"
    try:
        pdf_path = FOLDER_PATH / PDF_OUTPUT_NAME
        cmd = ['img2pdf'] + [str(f) for f in image_files] + ['-o', str(pdf_path)]

        print(f'Creating PDF: {pdf_path}')
        subprocess.run(cmd, check=True, capture_output=True)
        print(f'PDF created successfully: {pdf_path}')

    except subprocess.CalledProcessError as e:
        print(f'PDF creation failed: {e.stderr.decode() if e.stderr else str(e)}')
    except FileNotFoundError:
        print('img2pdf not found. Please install: brew install img2pdf')

def main():
    try:
        print('=== Kindle OCR Processing Started ===')
        print(f'プロジェクトルート: {PROJECT_ROOT}')
        print(f'サービスアカウントファイル: {SERVICE_ACCOUNT_FILE}')
        print(f'Google Drive フォルダID: {DRIVE_FOLDER_ID}')
        print(f'出力フォルダ: {FOLDER_PATH}')

        # 画像ファイル取得
        image_files = sorted(FOLDER_PATH.glob('screenshot_*.png'))
        if not image_files:
            raise ValueError('No screenshot files found')

        print(f'Found {len(image_files)} screenshot files')

        # クライアント初期化
        print('Initializing Google API clients...')
        clients = setup_clients()

        # OCR実行
        print('Starting OCR processing...')
        ocr_text = perform_batch_ocr(image_files, clients['vision'])

        if not ocr_text:
            raise ValueError('No text extracted from images')

        print(f'OCR completed. Extracted {len(ocr_text)} characters')

        # テキストファイル保存
        text_file = FOLDER_PATH / TEXT_OUTPUT_NAME
        with open(text_file, 'w', encoding='utf-8') as f:
            f.write(ocr_text)
        print(f'Text saved: {text_file}')

        # Google Docs作成
        print('Uploading to Google Docs...')
        create_google_doc(ocr_text, clients)

        # PDF作成（オプション）
        if get_env_var('KINDLE_OCR_CREATE_PDF', 'true').lower() == 'true':
            print('Creating PDF...')
            create_pdf(image_files)

        print('=== All processes completed successfully! ===')

    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
"
end generatePythonScript

-- クリーンアップ
on cleanup(screenshotPaths, folderPath)
    repeat with filePath in screenshotPaths
        do shell script "rm -f " & quoted form of filePath
    end repeat
    do shell script "rm -f " & quoted form of (folderPath & "ocr_script.py")
end cleanup

-- メッセージ表示
on showMessage(message)
    display dialog message buttons {"OK"} default button "OK"
end showMessage
