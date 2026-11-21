{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006-2009 Andreas Hausladen                                            *}
{*                                                                            *}
{******************************************************************************}

unit InterceptLoader;

interface

uses
  Windows, SysUtils, InterceptIntf;

function GetCompileInterceptorServices: ICompileInterceptorServices;
procedure UnloadCompilerInterceptorServices;

implementation

{function GetCompileInterceptorServices: ICompileInterceptorServices; stdcall;
  external 'CompileInterceptorW.dll' name 'GetCompileInterceptorServices';}

const
  // Pre-2009 (ANSI) IDEs must use the ANSI-built CompileInterceptor.dll (native PChar
  // filenames in the interceptor interface); 2009+ uses the Unicode CompileInterceptorW.dll.
  // The Win64 IDE loads CompileInterceptorW64.dll so that the 32/64-bit DLLs can ship
  // in the same directory.
  {$IFDEF CPUX64}
  CompileInterceptorDllName = 'CompileInterceptorW64.dll';
  {$ELSE}
  CompileInterceptorDllName = {$IFDEF UNICODE}'CompileInterceptorW.dll'{$ELSE}'CompileInterceptor.dll'{$ENDIF};
  {$ENDIF}

var
  _GetCompileInterceptorServices: function: ICompileInterceptorServices; stdcall;
  CompilerInterceptorLib: THandle;

function GetCompileInterceptorServices: ICompileInterceptorServices;
begin
  if not Assigned(_GetCompileInterceptorServices) then
  begin
    CompilerInterceptorLib := SafeLoadLibrary(PChar(ExtractFilePath(GetModuleName(HInstance)) + CompileInterceptorDllName));
    if CompilerInterceptorLib = 0 then
      CompilerInterceptorLib := SafeLoadLibrary(CompileInterceptorDllName); // search all PATHs
    if CompilerInterceptorLib <> 0 then
      _GetCompileInterceptorServices := GetProcAddress(CompilerInterceptorLib, 'GetCompileInterceptorServices');
  end;
  if Assigned(_GetCompileInterceptorServices) then
    Result := _GetCompileInterceptorServices()
  else
    raise Exception.Create('Cannot find ' + CompileInterceptorDllName);
end;

procedure UnloadCompilerInterceptorServices;
begin
  _GetCompileInterceptorServices := nil;
  if CompilerInterceptorLib <> 0 then
  begin
    FreeLibrary(CompilerInterceptorLib);
    CompilerInterceptorLib := 0;
  end;
end;


end.
