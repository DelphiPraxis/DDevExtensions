@echo off
rem D7 DIAGNOSTICS build: like build_d7.bat but with madExcept compiled in
rem (-DmadExcept) and the binary patched by madExceptPatch afterwards.
setlocal
if not exist T:\ subst T: "D:\Delphi\___Claude Workspace\DDevExtensions"
cd /d T:\Code\DDevExtensions\D_7
set DCU=C:\Users\TLH\AppData\Local\Temp\d7dcu_diag
if not exist "%DCU%" mkdir "%DCU%"
set MAD=C:\Delphi\7\TLH\Packages\madCollection
"C:\Delphi\7\Bin\dcc32compiler.exe" -B -GD -DmadExcept;DDEV_PNG_NOINIT DDevExtensions.dpr ^
 -U"..\Source;..\Source\CompileProgress;..\Source\ProjectSettings;..\Source\IDEMenuHandler;..\Source\ExcelExport;..\Source\Keybindings;..\Source\FileCleaner;..\Source\CompileBackup;..\Source\FormDesignerHelpers;..\Source\FileSelector;..\Source\DSUFeatures;..\Source\ComponentSelector;..\Source\OldPalette;..\Source\StartParameterManager;..\Source\StartParameterTeam;..\Source\Editor;..\Source\CompilerEnhancements;..\..\..\CompileInterceptor\Source;..\..\..\Shared;..\..\..\Shared\PascalParser;..\..\..\Shared\IDE;..\..\..\Shared\IDE\Options;..\..\..\Shared\Xml;..\..\..\Shared\PNGDelphi;%MAD%\madExcept\Delphi 7;%MAD%\madBasic\Delphi 7;%MAD%\madDisAsm\Delphi 7;C:\Delphi\7\Lib;C:\Delphi\7\Source\ToolsAPI" ^
 -I"..\Source;..\jedi" ^
 -LUrtl -LUvcl -LUdesignide ^
 -N"%DCU%"
if ERRORLEVEL 1 goto Error
echo === patching with madExcept ===
"%MAD%\madExcept\Tools\madExceptPatch.exe" DDevExtensions7.dll
echo Patch exit: %ERRORLEVEL%
goto Leave
:Error
echo BUILD FAILED
:Leave
endlocal
