@echo off
rem Builds the version-independent 64-bit break helper for the F12 debug-hotkey
rem feature. One F12Break64.exe covers every IDE version; only the 32-bit IDE
rem needs it (to break a native 64-bit debuggee). Output -> ..\..\Bin.
setlocal
if not exist T:\ subst T: "D:\Delphi\___Claude Workspace\DDevExtensions"
cd /d T:\Code\DDevExtensions\Source\DSUFeatures\F12Break64
set DCU=C:\Users\TLH\AppData\Local\Temp\f12break64dcu
if not exist "%DCU%" mkdir "%DCU%"
"C:\Delphi\13.1\bin\dcc64.exe" -B F12Break64.dpr ^
 -U"C:\Delphi\13.1\lib\win64\release" ^
 -NSWinapi;System;System.Win ^
 -E"..\..\..\Bin" ^
 -N"%DCU%"
endlocal
