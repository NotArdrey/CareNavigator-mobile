Option Explicit

Dim fso
Dim shell
Dim monitorPath
Dim command
Dim quote

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

monitorPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Monitor_SteelSeries_Sonar.bat")
If Not fso.FileExists(monitorPath) Then
    WScript.Quit 2
End If

quote = Chr(34)
command = quote & shell.ExpandEnvironmentStrings("%ComSpec%") & quote & " /d /c " & quote & quote & monitorPath & quote & quote
shell.Run command, 0, False
