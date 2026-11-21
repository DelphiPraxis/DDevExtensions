@echo off
rem Builds the ANSI CompileInterceptor.dll with D7 (for pre-2009 IDEs).
setlocal
if not exist T:\ subst T: "D:\Delphi\___Claude Workspace\DDevExtensions"
cd /d T:\CompileInterceptor\Source
"C:\Delphi\7\Bin\dcc32compiler.exe" -B -GD CompileInterceptor.dpr -U"C:\Delphi\7\Lib" -E..\Bin -N"C:\Users\TLH\AppData\Local\Temp\d7dcu_ci"
endlocal
