@echo off
rem D13 Win64 DIAGNOSTICS build: normal msbuild Release/Win64 but with madExcept
rem compiled in (-DmadExcept via DCC_Define), a detailed .map, and the binary
rem patched by madExceptPatch afterwards so DDevExtensions frames resolve by name
rem in the crash call stack. Output overwrites bin\Win64\DDevExtensionsD130.dll
rem (a build artifact) - redeploy to %APPDATA%\DDevExtensions and restore the
rem normal build when done.
setlocal
set PROJ=%~dp0DDevExtensions.dproj
set MAD64=C:\Delphi\13.1\TLH\Packages\madCollection\madExcept\BDS37\win64
set PATCH=C:\Delphi\13.1\TLH\Packages\madCollection\madExcept\Tools\madExceptPatch.exe
set OUT=%~dp0..\bin\Win64\DDevExtensionsD130.dll

call "C:\Delphi\13.1\bin\rsvars.bat"
msbuild "%PROJ%" /p:Config=Release /p:Platform=Win64 /p:DCC_Define=madExcept /p:DCC_MapFile=3 /p:DCC_UnitSearchPath="%MAD64%" /nologo /v:minimal
if ERRORLEVEL 1 goto Error

echo === patching with madExcept ===
"%PATCH%" "%OUT%"
echo Patch exit: %ERRORLEVEL%
goto Leave
:Error
echo BUILD FAILED
:Leave
endlocal
