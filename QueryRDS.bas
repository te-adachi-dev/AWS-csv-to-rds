Option Explicit

' API設定
Private Const API_URL As String = "YOUR_API_GATEWAY_URL/query"
Private Const API_KEY As String = "YOUR_API_KEY"

' RDSクエリ実行関数
Function ExecuteRDSQuery(sqlQuery As String) As String
    On Error GoTo ErrorHandler
    
    Dim http As Object
    Dim jsonBody As String
    Dim response As String
    
    ' HTTPオブジェクト作成
    Set http = CreateObject("MSXML2.XMLHTTP")
    
    ' リクエストボディ作成
    jsonBody = "{""sql"":""" & Replace(sqlQuery, """", "\""") & """}"
    
    ' API呼び出し
    http.Open "POST", API_URL, False
    http.setRequestHeader "Content-Type", "application/json"
    http.setRequestHeader "x-api-key", API_KEY
    http.Send jsonBody
    
    ' レスポンス取得
    response = http.responseText
    ExecuteRDSQuery = response
    
    Exit Function
    
ErrorHandler:
    ExecuteRDSQuery = "Error: " & Err.Description
End Function

' 結果をワークシートに展開
Sub QueryToSheet()
    Dim sql As String
    Dim result As String
    Dim jsonObj As Object
    Dim row As Long, col As Long
    Dim ws As Worksheet
    
    ' アクティブシート取得
    Set ws = ActiveSheet
    
    ' SQLクエリ入力
    sql = InputBox("SQLクエリを入力してください:", "RDSクエリ実行", "SELECT * FROM products LIMIT 10")
    If sql = "" Then Exit Sub
    
    ' クエリ実行
    result = ExecuteRDSQuery(sql)
    
    ' JSON解析
    Set jsonObj = JsonConverter.ParseJson(result)
    
    If jsonObj("success") Then
        ' ヘッダー行
        ws.Cells.Clear
        For col = 0 To UBound(jsonObj("columns"))
            ws.Cells(1, col + 1).Value = jsonObj("columns")(col)
            ws.Cells(1, col + 1).Font.Bold = True
        Next col
        
        ' データ行
        row = 2
        Dim recordItem As Variant
        For Each recordItem In jsonObj("rows")
            col = 1
            Dim colName As Variant
            For Each colName In jsonObj("columns")
                ws.Cells(row, col).Value = recordItem(colName)
                col = col + 1
            Next colName
            row = row + 1
        Next recordItem
        
        ' 実行情報
        ws.Cells(row + 1, 1).Value = "実行時間: " & jsonObj("execution_time_ms") & "ms"
        ws.Cells(row + 2, 1).Value = "行数: " & jsonObj("row_count")
        
        ' オートフィット
        ws.Columns.AutoFit
        
        MsgBox "クエリ実行完了！" & vbCrLf & _
               "取得行数: " & jsonObj("row_count") & vbCrLf & _
               "実行時間: " & jsonObj("execution_time_ms") & "ms", _
               vbInformation, "成功"
    Else
        MsgBox "エラー: " & jsonObj("error"), vbCritical, "クエリエラー"
    End If
    
End Sub

' シンプルなクエリ実行（デバッグ用）
Sub TestConnection()
    Dim result As String
    result = ExecuteRDSQuery("SELECT 1 as test")
    MsgBox result, vbInformation, "接続テスト"
End Sub