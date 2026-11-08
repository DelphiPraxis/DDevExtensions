{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* F12 debug-hotkey restore (integrated feature)                              *}
{*                                                                            *}
{******************************************************************************}

unit F12HotKeySupport;

{
  Restores the F12 "pause the running program" debug hotkey for the RAD Studio /
  Delphi IDE on Windows Vista .. 11. Clean-room reimplementation of Andreas
  Hausladen's standalone DelphiF12HotKeySupport expert, folded into DDevExtensions
  as an optional feature.

  Mechanism (documented, stable OS APIs only - no IDE internals, no ntdll byte
  signatures, so it survives IDE and Windows updates):
    1. A global WH_KEYBOARD_LL hook in the IDE process observes F12 system wide.
    2. On F12, when the IDE is NOT the foreground window, the foreground process
       is checked with CheckRemoteDebuggerPresent - only a process that IS being
       debugged is touched (breaking a non-debugged process would crash it). In
       practice that is the IDE's own debuggee.
    3. It is paused with kernel32!DebugBreakProcess; the attached debugger (the
       IDE / its 64-bit debug host) catches the breakpoint and stops the program.
    4. Bitness: a 32-bit IDE cannot break a native 64-bit target, so for such a
       target it hands the PID to the bundled F12Break64.exe (expected next to
       the DDevExtensions DLL). The 64-bit IDE breaks both directly.

  This is pure Win32 API code - it never registers a wizard and never passes a
  managed type across the IDE boundary, so it is safe in the non-Unicode IDEs
  (Delphi 7 / 2007) too, just like the original.
}

interface

procedure InstallF12HotKeySupport(Value: Boolean);

implementation

uses
  Windows, Messages, SysUtils;

{$IF not Declared(WH_KEYBOARD_LL)}
const
  WH_KEYBOARD_LL = 13; // old RTLs (Delphi 7 Windows.pas) lack the LL-hook constant
{$IFEND}

{.$DEFINE F12DIAG}   // diagnostic log to %TEMP%\DDevExtensions_F12.log (dot = off)

{ ---- imported APIs not present in every RTL version ---- }
function DebugBreakProcess(Process: THandle): BOOL; stdcall;
  external kernel32 name 'DebugBreakProcess';
function CheckRemoteDebuggerPresent(hProcess: THandle;
  var pbDebuggerPresent: BOOL): BOOL; stdcall;
  external kernel32 name 'CheckRemoteDebuggerPresent';
function IsWow64Process(hProcess: THandle; var Wow64Process: BOOL): BOOL; stdcall;
  external kernel32 name 'IsWow64Process';

type
  PKBDLLHOOKSTRUCT = ^TKBDLLHOOKSTRUCT;
  TKBDLLHOOKSTRUCT = record
    vkCode: DWORD;
    scanCode: DWORD;
    flags: DWORD;
    time: DWORD;
    {$IFDEF CPUX64}
    dwExtraInfo: UInt64;
    {$ELSE}
    dwExtraInfo: Cardinal;
    {$ENDIF}
  end;

var
  GHook: HHOOK = 0;
  GIs64BitOS: Boolean = False;

{$IFDEF F12DIAG}
procedure Log(const S: string);
var
  f: THandle;
  path: string;
  buf: array[0..259] of Char;
  line: AnsiString;
  n, w: DWORD;
begin
  n := GetEnvironmentVariable('TEMP', buf, Length(buf));
  if n = 0 then Exit;
  path := Copy(buf, 1, n) + '\DDevExtensions_F12.log';
  f := CreateFile(PChar(path), FILE_APPEND_DATA,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_ALWAYS, 0, 0);
  if f = INVALID_HANDLE_VALUE then Exit;
  try
    line := AnsiString(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + S + #13#10);
    SetFilePointer(f, 0, nil, FILE_END);
    WriteFile(f, line[1], Length(line), w, nil);
  finally
    CloseHandle(f);
  end;
end;
{$ELSE}
procedure Log(const S: string); {$IF CompilerVersion >= 18.0}inline;{$IFEND} begin end;
{$ENDIF}

{ --------------------------------------------------------------- break worker }

type
  PBreakInfo = ^TBreakInfo;
  TBreakInfo = record
    Pid: DWORD;
    Target64: Boolean;
  end;

procedure LaunchHelper64(APid: DWORD);
var
  ModName: array[0..MAX_PATH] of Char;
  Cmd: string;
  si: TStartupInfo;
  pi: TProcessInformation;
begin
  if GetModuleFileName(HInstance, ModName, MAX_PATH) = 0 then
    Exit;
  Cmd := '"' + ExtractFilePath(ModName) + 'F12Break64.exe" ' + IntToStr(APid);
  FillChar(si, SizeOf(si), 0);
  si.cb := SizeOf(si);
  si.dwFlags := STARTF_USESHOWWINDOW;
  si.wShowWindow := SW_HIDE;
  if CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW,
       nil, nil, si, pi) then
  begin
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
  end;
end;

{ Runs off the hook thread so the low-level hook returns immediately. }
function BreakThread(Param: Pointer): Integer; stdcall;
var
  Info: PBreakInfo;
  h: THandle;
begin
  Result := 0;
  Info := PBreakInfo(Param);
  try
    if Info.Target64 then
    begin
      Log(Format('  BreakThread: 64-bit path -> launch helper for pid=%d', [Info.Pid]));
      LaunchHelper64(Info.Pid);
    end
    else
    begin
      h := OpenProcess(PROCESS_ALL_ACCESS, False, Info.Pid);
      if h = 0 then
        Log(Format('  BreakThread: OpenProcess(ALL_ACCESS, pid=%d) FAILED err=%d', [Info.Pid, GetLastError]))
      else
      try
        if DebugBreakProcess(h) then
          Log(Format('  BreakThread: DebugBreakProcess(pid=%d) OK', [Info.Pid]))
        else
          Log(Format('  BreakThread: DebugBreakProcess(pid=%d) FAILED err=%d', [Info.Pid, GetLastError]));
      finally
        CloseHandle(h);
      end;
    end;
  finally
    Dispose(Info);
  end;
end;

{ Fast, synchronous gate: is APid a debugged process, and is it a native 64-bit
  target the 32-bit IDE cannot break directly? Returns True if we should break. }
function ShouldBreak(APid: DWORD; out ATarget64: Boolean): Boolean;
var
  h: THandle;
  dbg, wow: BOOL;
begin
  Result := False;
  ATarget64 := False;
  if APid = 0 then
    Exit;
  h := OpenProcess(PROCESS_QUERY_INFORMATION, False, APid);
  if h = 0 then
  begin
    Log(Format('  ShouldBreak: OpenProcess(QI, pid=%d) FAILED err=%d', [APid, GetLastError]));
    Exit;
  end;
  try
    dbg := False;
    if not CheckRemoteDebuggerPresent(h, dbg) then
    begin
      Log(Format('  ShouldBreak: CheckRemoteDebuggerPresent FAILED err=%d', [GetLastError]));
      Exit;
    end;
    if not dbg then
    begin
      Log('  ShouldBreak: process is NOT being debugged -> skip');
      Exit;                       { not debugged -> never touch it (safe) }
    end;
    wow := False;
    IsWow64Process(h, wow);
    {$IFNDEF CPUX64}
    { 32-bit expert: it cannot inject a break into a native 64-bit target, so
      such a target (non-WOW64 on a 64-bit OS) must go through the 64-bit helper. }
    ATarget64 := GIs64BitOS and (not wow);
    {$ELSE}
    { 64-bit expert: DebugBreakProcess reaches both 64-bit and 32-bit targets
      directly -> never need the external helper. }
    ATarget64 := False;
    {$ENDIF}
    Log(Format('  ShouldBreak: OK debugged=1 wow=%d needHelper=%d', [Ord(wow <> False), Ord(ATarget64)]));
    Result := True;
  finally
    CloseHandle(h);
  end;
end;

{ --------------------------------------------------------------- keyboard hook }

function IsIDEForeground: Boolean;
var
  Wnd: HWND;
  Pid: DWORD;
begin
  Wnd := GetForegroundWindow;
  if Wnd = 0 then
  begin
    Result := False;
    Exit;
  end;
  Pid := 0;
  GetWindowThreadProcessId(Wnd, Pid);
  Result := Pid = GetCurrentProcessId;
end;

function ForegroundPid: DWORD;
var
  Wnd: HWND;
begin
  Result := 0;
  Wnd := GetForegroundWindow;
  if Wnd <> 0 then
    GetWindowThreadProcessId(Wnd, Result);
end;

function LowLevelKeyboardProc(nCode: Integer; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
var
  Kb: PKBDLLHOOKSTRUCT;
  Pid: DWORD;
  Target64: Boolean;
  Info: PBreakInfo;
  Tid: DWORD;
  h: THandle;
begin
  if (nCode = HC_ACTION) and
     ((wParam = WM_KEYDOWN) or (wParam = WM_SYSKEYDOWN)) then
  begin
    Kb := PKBDLLHOOKSTRUCT(lParam);
    if (Kb <> nil) and (Kb.vkCode = VK_F12) then
    begin
      Log(Format('F12 down: IDEforeground=%d fgPid=%d ourPid=%d',
        [Ord(IsIDEForeground), ForegroundPid, GetCurrentProcessId]));
      if not IsIDEForeground then
      begin
        Pid := ForegroundPid;
        if (Pid <> 0) and (Pid <> GetCurrentProcessId) and
           ShouldBreak(Pid, Target64) then
        begin
          New(Info);
          Info.Pid := Pid;
          Info.Target64 := Target64;
          h := CreateThread(nil, 0, @BreakThread, Info, 0, Tid);
          if h <> 0 then
            CloseHandle(h)
          else
            Dispose(Info);
          Result := 1;              { swallow: debuggee must not receive F12 }
          Exit;
        end;
      end;
    end;
  end;
  Result := CallNextHookEx(GHook, nCode, wParam, lParam);
end;

{ ------------------------------------------------------------- install / remove }

procedure DetectOS;
{$IFNDEF CPUX64}
var
  wow: BOOL;
{$ENDIF}
begin
  {$IFNDEF CPUX64}
  wow := False;
  { A 32-bit process running under WOW64 means the OS is 64-bit. }
  if IsWow64Process(GetCurrentProcess, wow) then
    GIs64BitOS := wow;
  {$ELSE}
  GIs64BitOS := True;   { a native 64-bit process implies a 64-bit OS }
  {$ENDIF}
end;

procedure InstallHook;
begin
  if GHook = 0 then
    GHook := SetWindowsHookEx(WH_KEYBOARD_LL, @LowLevelKeyboardProc, HInstance, 0);
  Log(Format('InstallHook: GHook=%d (0 = FAILED, err=%d)', [GHook, GetLastError]));
end;

procedure RemoveHook;
begin
  if GHook <> 0 then
  begin
    UnhookWindowsHookEx(GHook);
    GHook := 0;
  end;
end;

procedure InstallF12HotKeySupport(Value: Boolean);
begin
  if Value then
  begin
    DetectOS;
    InstallHook;
  end
  else
    RemoveHook;
end;

initialization

finalization
  RemoveHook;

end.
