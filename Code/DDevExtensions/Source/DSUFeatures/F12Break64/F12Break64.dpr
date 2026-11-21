program F12Break64;
{
  64-bit break helper for the F12 debug-hotkey feature (F12HotKeySupport.pas).

  A 32-bit IDE process cannot reliably inject a break into a native 64-bit
  target, so the 32-bit DDevExtensions DLL launches this native-bitness helper
  with the debuggee PID. It just issues DebugBreakProcess; the debugger attached
  to that process (the IDE / its debug host) catches the breakpoint and pauses it.

  Bitness-independent in purpose - one F12Break64.exe covers every IDE version.
  The 64-bit IDE never needs it (DebugBreakProcess reaches both bitnesses there).
  Build once with dcc64 (see build_f12break64.bat); deploy next to the DLL.

  Pure Win32/64 API, statically linked.
}
{$APPTYPE CONSOLE}
{$SetPEFlags $0020}   // IMAGE_FILE_LARGE_ADDRESS_AWARE

uses
  Winapi.Windows,
  System.SysUtils;

function DebugBreakProcess(Process: THandle): BOOL; stdcall;
  external kernel32 name 'DebugBreakProcess';

var
  Pid: DWORD;
  h: THandle;
begin
  if ParamCount < 1 then
    Exit;
  Pid := StrToUIntDef(ParamStr(1), 0);
  if Pid = 0 then
    Exit;
  h := OpenProcess(PROCESS_ALL_ACCESS, False, Pid);
  if h = 0 then
    Exit;
  try
    DebugBreakProcess(h);
  finally
    CloseHandle(h);
  end;
end.
