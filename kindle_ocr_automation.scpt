-- 設定値
property PAGES : 200
property KEY_LEFT : (ASCII character 28)
property CAPTURE_RECT : "50,100,1500,850"
property SCREENSHOT_DELAY : 0.3
property PAGE_DELAY : 0.2

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
    return "#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
import subprocess
from pathlib import Path
from google.cloud import vision_v1
from google.oauth2 import service_account
from googleapiclient.discovery import build

# 設定
FOLDER_PATH = Path('" & folderPath & "')
SERVICE_ACCOUNT_FILE = '/path/to/your/service-account.json'
DRIVE_FOLDER_ID = 'YOUR_FOLDER_ID'
SCOPES = ['https://www.googleapis.com/auth/drive.file', 'https://www.googleapis.com/auth/documents']

def setup_clients():
    \"\"\"Google API クライアント初期化\"\"\"
    os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = SERVICE_ACCOUNT_FILE
    credentials = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=SCOPES)

    return {
        'vision': vision_v1.ImageAnnotatorClient(),
        'drive': build('drive', 'v3', credentials=credentials),
        'docs': build('docs', 'v1', credentials=credentials)
    }

def perform_batch_ocr(image_files, vision_client):
    \"\"\"バッチOCR処理\"\"\"
    ocr_text = ''

    for image_file in sorted(image_files):
        print(f'Processing: {image_file.name}')

        with open(image_file, 'rb') as f:
            image = vision_v1.Image(content=f.read())

        response = vision_client.text_detection(image=image)
        if response.text_annotations:
            ocr_text += response.text_annotations[0].description + '\\n\\n'

    return ocr_text.strip()

def create_google_doc(ocr_text, clients):
    \"\"\"Google Docs作成・アップロード\"\"\"
    # ファイル名生成（最初の10文字、安全な文字のみ）
    safe_chars = ''.join(c for c in ocr_text[:20] if c.isalnum() or c in ' -_')
    doc_name = safe_chars.strip() or 'Kindle_OCR_Output'

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

    print(f'Document created: https://docs.google.com/document/d/{doc_id}')
    return doc_id

def create_pdf(image_files):
    \"\"\"PDF作成\"\"\"
    try:
        pdf_path = FOLDER_PATH / 'kindle_output.pdf'
        subprocess.run(['img2pdf'] + [str(f) for f in image_files] + ['-o', str(pdf_path)],
                      check=True, capture_output=True)
        print(f'PDF created: {pdf_path}')
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f'PDF creation failed: {e}')

def main():
    try:
        # 画像ファイル取得
        image_files = sorted(FOLDER_PATH.glob('screenshot_*.png'))
        if not image_files:
            raise ValueError('No screenshot files found')

        print(f'Found {len(image_files)} images')

        # クライアント初期化
        clients = setup_clients()

        # OCR実行
        print('Starting OCR...')
        ocr_text = perform_batch_ocr(image_files, clients['vision'])

        if not ocr_text:
            raise ValueError('No text extracted from images')

        # テキストファイル保存
        with open(FOLDER_PATH / 'ocr_output.txt', 'w', encoding='utf-8') as f:
            f.write(ocr_text)

        # Google Docs作成
        print('Uploading to Google Docs...')
        create_google_doc(ocr_text, clients)

        # PDF作成
        print('Creating PDF...')
        create_pdf(image_files)

        print('All processes completed successfully!')

    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
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