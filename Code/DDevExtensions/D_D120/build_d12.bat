@echo off
rem D12 command-line build for DDevExtensions (Release, Win32 + Win64).
rem msbuild with the D12.3 rsvars fails on this machine (MSB4066: the
rem BDS\23.0 EnvOptions.proj uses a Condition attribute the old .NET
rem Framework msbuild rejects), so build with dcc32/dcc64 directly - same
rem pattern as D_7\build_d7.bat (SUBST keeps the paths short).
rem
rem Output (driven by {$LIBSUFFIX} in the .dpr, analogous to CompileInterceptor):
rem   Win32 -> ..\Bin\DDevExtensionsD120.dll     (32-bit IDE, Experts)
rem   Win64 -> ..\Bin\DDevExtensionsD120_64.dll  (64-bit IDE, Experts x64)
setlocal
if not exist T:\ subst T: "D:\Delphi\___Claude Workspace\DDevExtensions"
cd /d T:\Code\DDevExtensions\D_D120

set SRC=..\Source;..\Source\CompileProgress;..\Source\ProjectSettings;..\Source\IDEMenuHandler;..\Source\ExcelExport;..\Source\Keybindings;..\Source\FileCleaner;..\Source\CompileBackup;..\Source\FormDesignerHelpers;..\Source\FileSelector;..\Source\DSUFeatures;..\Source\ComponentSelector;..\Source\OldPalette;..\Source\StartParameterManager;..\Source\StartParameterTeam;..\Source\Editor;..\..\..\CompileInterceptor\Source;..\..\..\Shared;..\..\..\Shared\PascalParser;..\..\..\Shared\IDE;..\..\..\Shared\IDE\Options;..\..\..\Shared\Xml
set NS=-NSVcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;System;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;Bde

echo === Win32 (dcc32) -> DDevExtensionsD120.dll ===
set DCU32=C:\Users\TLH\AppData\Local\Temp\d12dcu
if not exist "%DCU32%" mkdir "%DCU32%"
"C:\Delphi\12.3\bin\dcc32.exe" -B DDevExtensions.dpr ^
 -U"%SRC%;C:\Delphi\12.3\lib\win32\release;C:\Delphi\12.3\source\ToolsAPI" ^
 -I"..\Source;..\jedi" ^
 %NS% ^
 -DRELEASE ^
 -LUrtl -LUvcl -LUdesignide ^
 -E"..\Bin" ^
 -N"%DCU32%"
if errorlevel 1 goto :done

echo === Win64 (dcc64) -> DDevExtensionsD120_64.dll ===
set DCU64=C:\Users\TLH\AppData\Local\Temp\d12dcu64
if not exist "%DCU64%" mkdir "%DCU64%"
"C:\Delphi\12.3\bin\dcc64.exe" -B DDevExtensions.dpr ^
 -U"%SRC%;C:\Delphi\12.3\lib\win64\release;C:\Delphi\12.3\source\ToolsAPI" ^
 -I"..\Source;..\jedi" ^
 %NS% ^
 -DRELEASE ^
 -LUrtl -LUvcl -LUdesignide ^
 -E"..\Bin" ^
 -N"%DCU64%"

:done
endlocal
