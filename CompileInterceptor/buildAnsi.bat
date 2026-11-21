@echo off

::SET BORLAND=C:\Borland
::SET BORLAND=C:\Program Files (x86)\Borland\
SET BORLAND=C:\Delphi\
SET P=%PATH%

::copy source\AppConsts.pas Installer\AppConsts.pas >NUL

:D10
echo === Delphi 10 ==============================
SET PATH=%Borland%\BDS\4.0\Bin;C:\Windows\System32
cd Source
dcc32 -B -GD CompileInterceptor.dpr
::if ERRORLEVEL 1 goto Error1
if NOT ERRORLEVEL 1 goto OK

:D7
echo === Delphi 7 ==============================
::SET PATH=%Borland%\Delphi7\Bin;C:\Windows\System32
SET PATH=%Borland%\7\Bin;C:\Windows\System32
cd Source
dcc32 -B -GD CompileInterceptor.dpr
if ERRORLEVEL 1 goto Error1

:OK
::cd Installer
::dcc32 -B InstallDelphiSpeedUp10.dpr
::if ERRORLEVEL 1 goto Error1
cd ..


:: ===========================================
goto Leave
:Error1
cd ..
:Error0
pause


:Leave
SET PATH=%P%
SET P=
SET BORLAND=
