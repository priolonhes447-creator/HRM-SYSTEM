Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")

On Error Resume Next
http.open "GET", "http://localhost:5000/api/health", False
http.send

If Err.Number <> 0 Or http.Status <> 200 Then
    WshShell.Run "cmd /c cd /d """ & scriptDir & "\backend"" && node server.js >> server.stdout.log 2>> server.stderr.log", 0, False
End If
On Error GoTo 0
