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
property KEY_LEFT : (ASCII character (getEnvVar("KINDLE_OCR_KEY_CODE", "29") as integer))
property CAPTURE_RECT : getEnvVar("KINDLE_OCR_CAPTURE_RECT", "50,100,1450,850")
property SCREENSHOT_DELAY : (getEnvVar("KINDLE_OCR_SCREENSHOT_DELAY", "0.3") as real)
property PAGE_DELAY : (getEnvVar("KINDLE_OCR_PAGE_DELAY", "0.2") as real)

-- メイン処理
on run
    -- プロジェクトルートディレクトリを取得
    set projectRoot to do shell script "dirname " & quoted form of (POSIX path of (path to me))
    set currentDate to do shell script "date +%Y%m%d_%H%M%S"

    -- プロジェクト内にスクリーンショットフォルダを作成
    set folderPath to projectRoot & "/screenshots/Kindle_Screenshots_" & currentDate & "/"

    -- Kindleアプリの状態確認と準備
    prepareKindleApp()

    -- 撮影設定の確認
    set userPages to confirmCaptureSettings(folderPath)
    if userPages is 0 then
        return -- キャンセルされた場合
    end if

    log "=== Kindle OCR処理開始 ==="
    log "プロジェクトルート: " & projectRoot
    log "出力フォルダ: " & folderPath
    log "撮影予定ページ数: " & userPages

    -- フォルダ作成
    createFolder(folderPath)

    -- スクリーンショット撮影開始
    set screenshotPaths to captureScreenshotsWithProgress(folderPath, userPages)

    -- スクリーンショット撮影完了後の確認ダイアログ
    set continueProcessing to confirmOCRProcessing(folderPath, screenshotPaths)

    if not continueProcessing then
        -- 中断された場合：スクリーンショットは保持して終了
        log "=== 処理中断（スクリーンショット保持） ==="
        showMessage("処理を中断しました。" & return & "スクリーンショットは以下に保存されています：" & return & folderPath)
        return
    end if

    -- OCR処理とアップロード
    if executePythonOCRWithProgress(folderPath, projectRoot) then
        cleanupScreenshots(screenshotPaths) -- スクリーンショットのみクリーンアップ
        log "=== 全処理完了 ==="
        showMessage("処理が完了しました。OCR結果がGoogle Docsにアップロードされました。")
    else
        log "=== 処理エラー ==="
        showMessage("エラーが発生しました。エラーログを確認してください。" & return & "スクリーンショットは保持されています：" & return & folderPath)
    end if
end run

-- Kindleアプリの準備
on prepareKindleApp()
    log "Kindleアプリの状態確認中..."

    try
        -- Kindleアプリが起動しているか確認
        tell application "System Events"
            set kindleRunning to (name of processes) contains "Amazon Kindle"
        end tell

        if kindleRunning then
            log "Kindleアプリが起動中です"
            -- 既に起動している場合はフォーカスを当てる
            tell application "Amazon Kindle"
                activate
            end tell
            delay 1
        else
            log "Kindleアプリを起動します"
            -- 起動していない場合は起動
            tell application "Amazon Kindle"
                activate
            end tell
            -- 起動待機
            delay 3
            display dialog "Kindleアプリが起動しました。" & return & "読みたい本を開いて、撮影開始したいページを表示してください。" & return & return & "準備ができたらOKを押してください。" buttons {"OK"} default button "OK"
        end if

    on error errorMessage
        log "Kindleアプリの準備でエラー: " & errorMessage
        display dialog "Kindleアプリの起動に失敗しました。" & return & "手動でKindleアプリを起動し、撮影したいページを表示してから再実行してください。" buttons {"OK"} default button "OK"
        error "Kindleアプリの準備失敗"
    end try

    -- Kindleアプリにフォーカスを確実に当てる
    tell application "Amazon Kindle" to activate
    delay 0.5

    log "Kindleアプリの準備完了"
end prepareKindleApp

-- 撮影設定の確認
on confirmCaptureSettings(folderPath)
    try
        -- 現在の設定を表示して確認
        set settingsMessage to "撮影設定確認:" & return & return & "出力フォルダ: " & folderPath & return & "デフォルト撮影ページ数: " & PAGES & return & "キャプチャ範囲: " & CAPTURE_RECT & return & "スクリーンショット間隔: " & SCREENSHOT_DELAY & "秒" & return & "ページめくり間隔: " & PAGE_DELAY & "秒" & return & return & "Kindleアプリの現在表示されているページから撮影を開始します。" & return & return & "撮影ページ数を変更しますか？"

        set userChoice to display dialog settingsMessage buttons {"キャンセル", "設定変更", "このまま開始"} default button "このまま開始"

        if button returned of userChoice is "キャンセル" then
            log "ユーザーによってキャンセルされました"
            return 0
        else if button returned of userChoice is "設定変更" then
            return getCustomPageCount()
        else
            return PAGES
        end if

    on error
        log "設定確認でエラーが発生しました"
        return 0
    end try
end confirmCaptureSettings

-- カスタムページ数の取得
on getCustomPageCount()
    try
        set userInput to display dialog "撮影するページ数を入力してください:" default answer (PAGES as string) buttons {"キャンセル", "OK"} default button "OK"

        if button returned of userInput is "キャンセル" then
            return 0
        end if

        set inputPages to (text returned of userInput) as integer

        -- 入力値の検証
        if inputPages < 1 then
            display dialog "ページ数は1以上で入力してください。" buttons {"OK"} default button "OK"
            return getCustomPageCount() -- 再帰的に再入力を求める
        else if inputPages > 1000 then
            set confirmLarge to display dialog "大量のページ数（" & inputPages & "枚）が指定されました。" & return & "処理に長時間かかる可能性があります。続行しますか？" buttons {"キャンセル", "続行"} default button "キャンセル"
            if button returned of confirmLarge is "キャンセル" then
                return getCustomPageCount()
            end if
        end if

        log "カスタムページ数設定: " & inputPages
        return inputPages

    on error
        display dialog "有効な数値を入力してください。" buttons {"OK"} default button "OK"
        return getCustomPageCount()
    end try
end getCustomPageCount

-- フォルダ作成
on createFolder(folderPath)
    do shell script "mkdir -p " & quoted form of folderPath
    log "フォルダ作成: " & folderPath
end createFolder

-- 進捗表示付きスクリーンショット連続撮影（カスタムページ数対応）
on captureScreenshotsWithProgress(folderPath, targetPages)
    set screenshotPaths to {}
    log "スクリーンショット撮影開始: " & targetPages & "枚"

    -- 撮影開始前の最終確認
    display dialog "撮影を開始します。" & return & return & "Kindleアプリの現在のページから " & targetPages & " ページを撮影します。" & return & return & "3秒後に自動的に開始されます。" buttons {"開始"} default button "開始" giving up after 3

    log "撮影カウントダウン開始"

    repeat with i from 1 to targetPages
        set screenshotPath to folderPath & "screenshot_" & (i as string) & ".png"

        -- 進捗ログ出力（10枚ごと、または最初と最後）
        if i = 1 or i mod 10 = 0 or i = targetPages then
            set progressPercent to round (i / targetPages * 100)
            log "スクリーンショット撮影中: " & i & "/" & targetPages & " (" & progressPercent & "%)"
        end if

        -- Kindleアプリにフォーカスを確実に当てる（最初の数回）
        if i <= 3 then
            tell application "Amazon Kindle" to activate
            delay 0.2
        end if

        -- スクリーンショット撮影
        try
            do shell script "screencapture -R " & CAPTURE_RECT & " " & quoted form of screenshotPath
            set end of screenshotPaths to screenshotPath

            -- 撮影成功をログ出力（最初の数枚のみ）
            if i <= 5 then
                log "スクリーンショット撮影成功: " & screenshotPath
            end if

        on error screenshotError
            log "スクリーンショット撮影エラー (ページ " & i & "): " & screenshotError
            -- エラーが発生してもスクリーンショットパスは追加（後でクリーンアップ）
            set end of screenshotPaths to screenshotPath
        end try

        delay SCREENSHOT_DELAY

        -- ページめくり（最後のページ以外）
        if i < targetPages then
            try
                tell application "System Events"
                    keystroke KEY_LEFT
                end tell
                delay PAGE_DELAY

                -- ページめくり成功をログ出力（最初の数回のみ）
                if i <= 5 then
                    log "ページめくり実行: " & i & " -> " & (i + 1)
                end if

            on error pageError
                log "ページめくりエラー (ページ " & i & "): " & pageError
            end try
        end if
    end repeat

    log "スクリーンショット撮影完了: " & targetPages & "枚"

    -- 実際に撮影されたファイル数を確認
    set actualCount to 0
    repeat with screenshotPath in screenshotPaths
        try
            do shell script "test -f " & quoted form of screenshotPath
            set actualCount to actualCount + 1
        on error
            -- ファイルが存在しない場合はカウントしない
        end try
    end repeat

    log "実際に撮影されたファイル数: " & actualCount & "枚"

    return screenshotPaths
end captureScreenshotsWithProgress

-- OCR処理継続確認ダイアログ
on confirmOCRProcessing(folderPath, screenshotPaths)
    try
        -- 実際に撮影されたファイル数を確認
        set actualCount to 0
        repeat with screenshotPath in screenshotPaths
            try
                do shell script "test -f " & quoted form of screenshotPath
                set actualCount to actualCount + 1
            on error
                -- ファイルが存在しない場合はカウントしない
            end try
        end repeat

        -- 確認メッセージ作成
        set confirmMessage to "スクリーンショットの取得が完了しました。" & return & return & "撮影結果:" & return & "• 撮影枚数: " & actualCount & "枚" & return & "• 保存場所: " & folderPath & return & return & "このままGoogle ドキュメントの作成に進みますか？" & return & return & "※「中断」を選択した場合、スクリーンショットは保持されます。"

        set userChoice to display dialog confirmMessage buttons {"中断", "Google ドキュメント作成"} default button "Google ドキュメント作成"

        if button returned of userChoice is "中断" then
            log "ユーザーによってOCR処理が中断されました"
            return false
        else
            log "OCR処理を継続します"
            return true
        end if

    on error errorMessage
        log "OCR処理確認でエラー: " & errorMessage
        -- エラーの場合はデフォルトで継続
        return true
    end try
end confirmOCRProcessing

-- 進捗表示付きPython OCRスクリプト実行
on executePythonOCRWithProgress(folderPath, projectRoot)
    try
        log "OCR処理開始..."

        -- 外部Pythonスクリプトを作成
        set pythonScriptPath to createExternalPythonScript(folderPath, projectRoot)

        -- 進捗ログファイルのパス
        set progressLogPath to folderPath & "progress.log"

        -- 仮想環境のPythonを使用して実行
        set pythonCommand to buildPythonCommand(projectRoot, pythonScriptPath)

        -- バックグラウンドでPython実行開始
        set fullCommand to pythonCommand & " > " & quoted form of progressLogPath & " 2>&1 &"
        set pythonPID to do shell script fullCommand & " echo $!"

        log "Python処理開始 (PID: " & pythonPID & ")"

        -- 進捗監視
        monitorPythonProgress(progressLogPath, pythonPID)

        -- 実行結果確認
        try
            do shell script "kill -0 " & pythonPID
            -- まだ実行中の場合は終了を待つ
            do shell script "wait " & pythonPID
        on error
            -- プロセス終了済み
        end try

        -- 最終結果確認
        set finalOutput to do shell script "cat " & quoted form of progressLogPath
        log "Python実行完了"

        -- 成功判定
        if finalOutput contains "=== Completed ===" then
            log "OCR処理成功"
            -- 一時ファイル削除（Pythonスクリプトと進捗ログのみ）
            do shell script "rm -f " & quoted form of pythonScriptPath
            do shell script "rm -f " & quoted form of progressLogPath
            return true
        else
            log "OCR処理失敗"
            log "出力内容: " & finalOutput
            return false
        end if

    on error errorMessage
        log "Python実行エラー: " & errorMessage
        -- エラーログ保存
        do shell script "echo " & quoted form of ("Python execution error: " & errorMessage) & " > " & quoted form of (folderPath & "error_log.txt")
        return false
    end try
end executePythonOCRWithProgress

-- Python進捗監視（ログ出力のみ）
on monitorPythonProgress(progressLogPath, pythonPID)
    set monitorCount to 0
    set lastLogSize to 0

    repeat
        delay 5
        set monitorCount to monitorCount + 1

        try
            -- プロセスの生存確認
            do shell script "kill -0 " & pythonPID

            -- ログファイルの内容確認
            try
                set currentLog to do shell script "cat " & quoted form of progressLogPath & " 2>/dev/null || echo '処理中...'"
                set currentLogSize to length of currentLog

                -- ログが更新された場合、最新の行をログ出力
                if currentLogSize > lastLogSize then
                    set recentLines to do shell script "tail -3 " & quoted form of progressLogPath & " 2>/dev/null || echo '処理中...'"
                    log "OCR進捗更新: " & recentLines
                    set lastLogSize to currentLogSize
                else
                    -- ログが更新されていない場合
                    log "OCR処理中... (" & (monitorCount * 5) & "秒経過)"
                end if

            on error
                log "OCR処理中... (" & (monitorCount * 5) & "秒経過)"
            end try

        on error
            -- プロセス終了
            log "Python処理完了検出"
            exit repeat
        end try

        -- 長時間実行の場合の警告（10分 = 120回 * 5秒）
        if monitorCount > 120 then
            log "警告: OCR処理が長時間実行されています (" & (monitorCount * 5) & "秒)"
            set monitorCount to 0
        end if
    end repeat
end monitorPythonProgress

-- 外部Pythonスクリプトファイル作成（進捗出力強化版）
on createExternalPythonScript(folderPath, projectRoot)
    set pythonScriptPath to folderPath & "ocr_script.py"

    -- シェルスクリプトでPythonファイルを作成
    do shell script "cat > " & quoted form of pythonScriptPath & " << 'PYTHON_EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
import time
from pathlib import Path
from google.cloud import vision_v1
from google.oauth2 import service_account
from googleapiclient.discovery import build
from datetime import datetime

# Configuration
PROJECT_ROOT = Path('" & projectRoot & "')
FOLDER_PATH = Path('" & folderPath & "')

def log_progress(message):
    \"\"\"進捗ログ出力\"\"\"
    timestamp = datetime.now().strftime('%H:%M:%S')
    print(f'[{timestamp}] {message}')
    sys.stdout.flush()

def get_env_var(name, default=None, required=False):
    value = os.environ.get(name, default)
    if required and not value:
        raise ValueError(f'Required env var not set: {name}')
    return value

def get_service_account_file():
    path = get_env_var('GOOGLE_APPLICATION_CREDENTIALS')
    if path:
        return Path(path)
    return PROJECT_ROOT / get_env_var('KINDLE_OCR_SERVICE_ACCOUNT_FILE', 'kindle-ocr-service-account.json')

def setup_clients():
    log_progress('Google APIクライアント初期化開始')
    service_file = get_service_account_file()
    log_progress(f'サービスアカウントファイル: {service_file}')

    if not service_file.exists():
        raise FileNotFoundError(f'Service account file not found: {service_file}')

    if not get_env_var('GOOGLE_APPLICATION_CREDENTIALS'):
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = str(service_file)

    log_progress('認証情報読み込み中...')
    credentials = service_account.Credentials.from_service_account_file(
        str(service_file),
        scopes=['https://www.googleapis.com/auth/drive.file', 'https://www.googleapis.com/auth/documents']
    )

    log_progress('Google APIクライアント作成中...')
    clients = {
        'vision': vision_v1.ImageAnnotatorClient(),
        'drive': build('drive', 'v3', credentials=credentials),
        'docs': build('docs', 'v1', credentials=credentials)
    }

    log_progress('Google APIクライアント初期化完了')
    return clients

def perform_ocr(image_files, vision_client):
    total_files = len(image_files)
    log_progress(f'OCR処理開始: {total_files}ファイル')
    ocr_text = ''

    for i, img_file in enumerate(sorted(image_files), 1):
        log_progress(f'OCR処理中 ({i}/{total_files}): {img_file.name}')

        try:
            with open(img_file, 'rb') as f:
                image = vision_v1.Image(content=f.read())

            response = vision_client.text_detection(image=image)

            if response.error.message:
                log_progress(f'  OCRエラー: {response.error.message}')
                continue

            if response.text_annotations:
                extracted_text = response.text_annotations[0].description
                ocr_text += extracted_text + chr(10) + chr(10)
                log_progress(f'  テキスト抽出成功: {len(extracted_text)}文字')
            else:
                log_progress(f'  テキストが見つかりませんでした')

        except Exception as e:
            log_progress(f'  処理エラー: {e}')
            continue

        # 進捗率表示
        if i % 5 == 0 or i == total_files:
            progress_percent = round((i / total_files) * 100)
            log_progress(f'OCR進捗: {progress_percent}% ({i}/{total_files})')

    final_text = ocr_text.strip()
    log_progress(f'OCR処理完了: 総文字数 {len(final_text)}文字')
    return final_text

def create_doc(text, clients):
    log_progress('Google Docs作成開始')

    folder_id = get_env_var('KINDLE_OCR_DRIVE_FOLDER_ID', required=True)
    doc_name = f'Kindle_OCR_{FOLDER_PATH.name}_{datetime.now().strftime(\"%Y%m%d_%H%M%S\")}'

    log_progress(f'ドキュメント名: {doc_name}')
    log_progress('Google Driveにドキュメント作成中...')

    doc = clients['drive'].files().create(body={
        'name': doc_name,
        'parents': [folder_id],
        'mimeType': 'application/vnd.google-apps.document'
    }, fields='id').execute()

    doc_id = doc['id']
    log_progress(f'ドキュメント作成完了: ID {doc_id}')

    log_progress('テキスト挿入中...')
    clients['docs'].documents().batchUpdate(
        documentId=doc_id,
        body={'requests': [{'insertText': {'location': {'index': 1}, 'text': text}}]}
    ).execute()

    url = f'https://docs.google.com/document/d/{doc_id}'
    log_progress(f'Google Docs作成完了: {url}')

    # URL保存
    with open(FOLDER_PATH / 'google_doc_url.txt', 'w') as f:
        f.write(url)

    return url

def main():
    try:
        log_progress('=== Kindle OCR処理開始 ===')
        log_progress(f'プロジェクトルート: {PROJECT_ROOT}')
        log_progress(f'出力フォルダ: {FOLDER_PATH}')
        log_progress(f'Python実行環境: {sys.executable}')

        # 画像ファイル検索
        log_progress('スクリーンショットファイル検索中...')
        images = sorted(FOLDER_PATH.glob('screenshot_*.png'))
        if not images:
            raise ValueError('スクリーンショットファイルが見つかりません')

        log_progress(f'スクリーンショット発見: {len(images)}ファイル')

        # Google APIクライアント初期化
        clients = setup_clients()

        # OCR処理実行
        text = perform_ocr(images, clients['vision'])

        if not text:
            raise ValueError('テキストが抽出されませんでした')

        # テキストファイル保存
        log_progress('テキストファイル保存中...')
        with open(FOLDER_PATH / 'ocr_output.txt', 'w', encoding='utf-8') as f:
            f.write(text)
        log_progress('テキストファイル保存完了')

        # Google Docs作成
        doc_url = create_doc(text, clients)

        log_progress('=== Completed ===')
        log_progress(f'Google Docs URL: {doc_url}')

    except Exception as e:
        log_progress(f'エラー発生: {e}')
        import traceback
        log_progress('詳細エラー情報:')
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
PYTHON_EOF"

    log "Pythonスクリプト作成完了: " & pythonScriptPath
    return pythonScriptPath
end createExternalPythonScript

-- 仮想環境対応のPythonコマンド構築
on buildPythonCommand(projectRoot, pythonScriptPath)
    set venvPaths to {projectRoot & "/kindle_ocr_env/bin/python3", projectRoot & "/venv/bin/python3", projectRoot & "/.venv/bin/python3"}

    repeat with venvPath in venvPaths
        try
            do shell script "test -f " & quoted form of venvPath
            log "仮想環境Python使用: " & venvPath
            return "cd " & quoted form of projectRoot & " && " & quoted form of venvPath & " " & quoted form of pythonScriptPath
        on error
        end try
    end repeat

    log "システムPython使用（警告: 仮想環境が見つかりません）"
    return "cd " & quoted form of projectRoot & " && python3 " & quoted form of pythonScriptPath
end buildPythonCommand

-- スクリーンショットファイルのみクリーンアップ
on cleanupScreenshots(screenshotPaths)
    log "スクリーンショットファイルクリーンアップ開始..."
    set cleanupCount to 0
    repeat with filePath in screenshotPaths
        try
            do shell script "rm -f " & quoted form of filePath
            set cleanupCount to cleanupCount + 1
        on error
            -- エラーは無視して続行
        end try
    end repeat
    log "スクリーンショットクリーンアップ完了: " & cleanupCount & "ファイル削除"
end cleanupScreenshots

-- メッセージ表示（最終結果のみ）
on showMessage(message)
    display dialog message buttons {"OK"} default button "OK"
    log message
end showMessage