@echo off
rem D7 command-line build for DDevExtensions.
rem D7 dcc32 quirks (found 2026-07-18):
rem  - dcc32 corrupts itself on file paths longer than ~127 chars (AV, bogus
rem    "unexpected EOF in comment" in jedi.inc, invalid chars, ICE D10869).
rem    The repo root is deep, so build via SUBST drive T: -> repo root.
rem  - DCC32.exe is the dcc32speed wrapper; use dcc32compiler.exe (the real
rem    compiler) to keep one variable out of the equation.
setlocal
if not exist T:\ subst T: "D:\Delphi\___Claude Workspace\DDevExtensions"
cd /d T:\Code\DDevExtensions\D_7
set DCU=C:\Users\TLH\AppData\Local\Temp\d7dcu
if not exist "%DCU%" mkdir "%DCU%"
"C:\Delphi\7\Bin\dcc32compiler.exe" -B -DDDEV_PNG_NOINIT DDevExtensions.dpr ^
 -U"..\Source;..\Source\CompileProgress;..\Source\ProjectSettings;..\Source\IDEMenuHandler;..\Source\ExcelExport;..\Source\Keybindings;..\Source\FileCleaner;..\Source\CompileBackup;..\Source\FormDesignerHelpers;..\Source\FileSelector;..\Source\DSUFeatures;..\Source\ComponentSelector;..\Source\OldPalette;..\Source\StartParameterManager;..\Source\StartParameterTeam;..\Source\Editor;..\..\..\CompileInterceptor\Source;..\..\..\Shared;..\..\..\Shared\PascalParser;..\..\..\Shared\IDE;..\..\..\Shared\IDE\Options;..\..\..\Shared\Xml;..\..\..\Shared\PNGDelphi;C:\Delphi\7\Lib;C:\Delphi\7\Source\ToolsAPI" ^
 -I"..\Source;..\jedi" ^
 -LUrtl -LUvcl -LUdesignide ^
 -N"%DCU%"
endlocal
