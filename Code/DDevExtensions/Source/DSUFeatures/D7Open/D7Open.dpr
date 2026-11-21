program D7Open;

{
  Shell launcher for Delphi 7 project files (.dpr/.dpk/.bpg).

  Why it exists: the stock file association starts "delphi32.exe /np" and hands
  the file over via DDE. Delphi 7 services that DDE [open(...)] about one second
  into its startup - BEFORE any expert DLL is loaded - so when the project's
  .dsk was written by a newer BDS IDE, the desktop restore busy-loops and no
  IDE plugin (DDevExtensions' SkipForeignDsk included) ever gets a chance to
  intervene. Measured 2026-08-23, see Delphi_Eigenheiten.md.

  What it does when invoked with a file:
    1. Parks a foreign (BDS-written) sibling .dsk as <name>.dsk.bak - same
       detection as SkipForeignDsk.pas (.dproj/.groupproj/.bdsproj reference).
    2. If a Delphi 7 instance is running, forwards the file via DDE
       (service DELPHI32, topic System) so it opens in the running IDE -
       exactly what the stock association did.
    3. Otherwise starts delphi32 with the file as a command-line argument -
       on that path the IDE loads experts first, so SkipForeignDsk is armed
       before the project opens.

  Setup: run "D7Open.exe /register" once (per user, no admin needed) - it
  points .dpr/.dpk/.bpg at this launcher via HKCU\Software\Classes and keeps
  the original icons. "/unregister" restores the stock association.
}

{$APPTYPE GUI}

uses
  Windows, SysUtils, Registry, ShellAPI;

{ ---- minimal DDEML client declarations (D7 has no raw DDEML unit) ---- }
const
  SHCNE_ASSOCCHANGED = $08000000;
  SHCNF_IDLIST       = 0;

procedure SHChangeNotify(wEventId: Longint; uFlags: UINT; dwItem1, dwItem2: Pointer);
  stdcall; external 'shell32.dll';

const
  APPCMD_CLIENTONLY = $00000010;
  CP_WINANSI        = 1004;
  XTYP_EXECUTE      = $4050;
  DMLERR_NO_ERROR   = 0;

type
  HSZ = THandle;
  HCONV = THandle;
  HDDEDATA = THandle;
  TDdeCallback = function(CallType, Fmt: UINT; Conv: HCONV; hsz1, hsz2: HSZ;
    Data: HDDEDATA; Data1, Data2: DWORD): HDDEDATA; stdcall;

function DdeInitialize(var Inst: DWORD; Callback: TDdeCallback; Cmd, Res: DWORD): UINT;
  stdcall; external 'user32.dll' name 'DdeInitializeA';
function DdeUninitialize(Inst: DWORD): BOOL;
  stdcall; external 'user32.dll';
function DdeCreateStringHandle(Inst: DWORD; Psz: PAnsiChar; CodePage: Integer): HSZ;
  stdcall; external 'user32.dll' name 'DdeCreateStringHandleA';
function DdeFreeStringHandle(Inst: DWORD; Hsz: HSZ): BOOL;
  stdcall; external 'user32.dll';
function DdeConnect(Inst: DWORD; Service, Topic: HSZ; Context: Pointer): HCONV;
  stdcall; external 'user32.dll';
function DdeDisconnect(Conv: HCONV): BOOL;
  stdcall; external 'user32.dll';
function DdeClientTransaction(Data: Pointer; DataLen: DWORD; Conv: HCONV;
  Item: HSZ; Fmt, CallType: UINT; Timeout: DWORD; Result: PDWORD): HDDEDATA;
  stdcall; external 'user32.dll';

function DdeCb(CallType, Fmt: UINT; Conv: HCONV; hsz1, hsz2: HSZ;
  Data: HDDEDATA; Data1, Data2: DWORD): HDDEDATA; stdcall;
begin
  Result := 0;
end;

{ ---- foreign .dsk parking (same logic as SkipForeignDsk.pas) ---- }

function IsForeignDsk(const DskFile: string): Boolean;
var
  F: file;
  Data: string;
  Size: Integer;
begin
  Result := False;
  try
    if not FileExists(DskFile) then
      Exit;
    AssignFile(F, DskFile);
    FileMode := fmOpenRead or fmShareDenyNone;
    Reset(F, 1);
    try
      Size := FileSize(F);
      if Size <= 0 then
        Exit;
      SetLength(Data, Size);
      BlockRead(F, Data[1], Size);
    finally
      CloseFile(F);
    end;
    Data := AnsiLowerCase(Data);
    Result := (Pos('.dproj', Data) > 0) or (Pos('.groupproj', Data) > 0) or
              (Pos('.bdsproj', Data) > 0);
  except
  end;
end;

procedure ParkForeignDsk(const ProjectFile: string);
var
  DskFile, BakFile: string;
begin
  try
    DskFile := ChangeFileExt(ProjectFile, '.dsk');
    if not IsForeignDsk(DskFile) then
      Exit;
    BakFile := DskFile + '.bak';
    if FileExists(BakFile) then
      DeleteFile(BakFile);
    RenameFile(DskFile, BakFile);
  except
  end;
end;

{ ---- IDE location / launch ---- }

function Delphi32Path: string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('\Software\Borland\Delphi\7.0') then
    begin
      Result := Reg.ReadString('App');
      if (Result = '') or not FileExists(Result) then
        Result := IncludeTrailingPathDelimiter(Reg.ReadString('RootDir')) + 'Bin\delphi32.exe';
    end;
  finally
    Reg.Free;
  end;
  if (Result = '') or not FileExists(Result) then
    Result := 'C:\Delphi\7\Bin\delphi32.exe';
end;

{ Try to hand the file to a running IDE via DDE. True = an instance took it. }
function OpenViaDde(const FileName: string): Boolean;
var
  Inst: DWORD;
  Service, Topic: HSZ;
  Conv: HCONV;
  Cmd: string;
begin
  Result := False;
  Inst := 0;
  if DdeInitialize(Inst, DdeCb, APPCMD_CLIENTONLY, 0) <> DMLERR_NO_ERROR then
    Exit;
  try
    Service := DdeCreateStringHandle(Inst, 'DELPHI32', CP_WINANSI);
    Topic := DdeCreateStringHandle(Inst, 'System', CP_WINANSI);
    try
      Conv := DdeConnect(Inst, Service, Topic, nil);
      if Conv <> 0 then
      try
        Cmd := '[open("' + FileName + '")]';
        Result := DdeClientTransaction(PChar(Cmd), Length(Cmd) + 1, Conv, 0,
          CF_TEXT, XTYP_EXECUTE, 10000, nil) <> 0;
      finally
        DdeDisconnect(Conv);
      end;
    finally
      DdeFreeStringHandle(Inst, Service);
      DdeFreeStringHandle(Inst, Topic);
    end;
  finally
    DdeUninitialize(Inst);
  end;
end;

{ ---- association registration (per user, HKCU\Software\Classes) ---- }

const
  Exts: array[0..2] of string = ('.dpr', '.dpk', '.bpg');
  OldProgIds: array[0..2] of string = ('DelphiProject', 'DelphiPackage', 'BorlandProjectGroup');

procedure RegisterAssociations;
var
  Reg, RegRead: TRegistry;
  I: Integer;
  ProgId, Icon, Launcher: string;
begin
  Launcher := ParamStr(0);
  // separate read instance: OpenKeyReadOnly permanently degrades the object's
  // Access to KEY_READ (D7), which would make every later WriteString fail
  RegRead := TRegistry.Create(KEY_READ);
  Reg := TRegistry.Create;
  try
    for I := Low(Exts) to High(Exts) do
    begin
      ProgId := 'D7Open' + Exts[I]; // e.g. "D7Open.dpr"

      // keep the stock icon if the old ProgId provides one
      RegRead.RootKey := HKEY_CLASSES_ROOT;
      Icon := '';
      if RegRead.OpenKeyReadOnly('\' + OldProgIds[I] + '\DefaultIcon') then
      begin
        Icon := RegRead.ReadString('');
        RegRead.CloseKey;
      end;
      if Icon = '' then
        Icon := Delphi32Path + ',1';

      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKey('\Software\Classes\' + ProgId + '\DefaultIcon', True) then
      begin
        Reg.WriteString('', Icon);
        Reg.CloseKey;
      end;
      if Reg.OpenKey('\Software\Classes\' + ProgId + '\shell\open\command', True) then
      begin
        Reg.WriteString('', '"' + Launcher + '" "%1"');
        Reg.CloseKey;
      end;
      if Reg.OpenKey('\Software\Classes\' + Exts[I], True) then
      begin
        Reg.WriteString('', ProgId);
        Reg.CloseKey;
      end;
    end;
  finally
    Reg.Free;
    RegRead.Free;
  end;
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
  MessageBox(0, 'D7Open now handles .dpr/.dpk/.bpg for this user.'#13#10 +
    'Run "D7Open.exe /unregister" to restore the stock association.',
    'D7Open', MB_ICONINFORMATION);
end;

procedure UnregisterAssociations;
var
  Reg: TRegistry;
  I: Integer;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    for I := Low(Exts) to High(Exts) do
    begin
      Reg.DeleteKey('\Software\Classes\' + Exts[I]);
      Reg.DeleteKey('\Software\Classes\D7Open' + Exts[I]);
    end;
  finally
    Reg.Free;
  end;
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
  MessageBox(0, 'Stock associations for .dpr/.dpk/.bpg restored.', 'D7Open',
    MB_ICONINFORMATION);
end;

{ ---- main ---- }

var
  FileName: string;
begin
  FileName := ParamStr(1);
  if SameText(FileName, '/register') then
    RegisterAssociations
  else if SameText(FileName, '/unregister') then
    UnregisterAssociations
  else if FileName = '' then
    ShellExecute(0, 'open', PChar(Delphi32Path), '/np', nil, SW_SHOWNORMAL)
  else
  begin
    ParkForeignDsk(FileName);
    if not OpenViaDde(FileName) then
      ShellExecute(0, 'open', PChar(Delphi32Path), PChar('"' + FileName + '"'),
        nil, SW_SHOWNORMAL);
  end;
end.
