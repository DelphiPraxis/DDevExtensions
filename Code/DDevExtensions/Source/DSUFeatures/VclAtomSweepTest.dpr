program VclAtomSweepTest;

// Command line check for VclAtomSweep.pas against the real atom table:
//   dcc32 VclAtomSweepTest.dpr && VclAtomSweepTest
// Plants VCL-style atoms for a finished process and a finished thread (their
// handles kept open, as the debugger does), for this live process and thread,
// and some that merely look similar - then checks what the sweep deletes.
// Exit code 0 = as expected. Must run in a normal session (needs a window
// station atom table).

{$APPTYPE CONSOLE}

uses
  Windows,
  SysUtils,
  VclAtomSweep in 'VclAtomSweep.pas';

var
  Failures: Integer;
  HelperEvent: THandle;

function HelperThread(P: Pointer): DWORD; stdcall;
begin
  WaitForSingleObject(HelperEvent, INFINITE);
  Result := 0;
end;

function QuickThread(P: Pointer): DWORD; stdcall;
begin
  Result := 0;
end;

{ A process that has finished, its handle still open (the id stays reserved) }
function FinishedProcessId(out Handle: THandle): DWORD;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  Cmd := 'cmd.exe /c exit';
  UniqueString(Cmd);
  if not CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    RaiseLastOSError;
  WaitForSingleObject(PI.hProcess, 10000);
  CloseHandle(PI.hThread);
  Handle := PI.hProcess;
  Result := PI.dwProcessId;
end;

function FinishedThreadId(out Handle: THandle): DWORD;
begin
  Handle := CreateThread(nil, 0, @QuickThread, nil, 0, Result);
  WaitForSingleObject(Handle, 10000);
end;

procedure Plant(const Name: string; Times: Integer);
var
  I: Integer;
begin
  for I := 1 to Times do
    if GlobalAddAtom(PChar(Name)) = 0 then
      RaiseLastOSError;
end;

procedure Expect(const Name: string; StillThere: Boolean);
var
  Present: Boolean;
begin
  Present := GlobalFindAtom(PChar(Name)) <> 0;
  if Present <> StillThere then
  begin
    Inc(Failures);
    if StillThere then
      WriteLn('FAIL  ', Name, ' was deleted but belongs to something alive')
    else
      WriteLn('FAIL  ', Name, ' is still there');
  end;
  // leave the table as we found it
  while GlobalFindAtom(PChar(Name)) <> 0 do
    if GlobalDeleteAtom(GlobalFindAtom(PChar(Name))) <> 0 then
      Break;
end;

procedure LogLine(const Msg: string);
begin
  WriteLn('      ', Msg);
end;

var
  DeadProc, DeadThread, Helper: THandle;
  DeadPid, DeadTid, HelperTid, OwnPid, OwnTid: DWORD;
  Deleted: Integer;
  SDeadPid, SDeadTid, SHelperTid, SOwnPid, SOwnTid, SInst: string;
begin
  DeadPid := FinishedProcessId(DeadProc);
  DeadTid := FinishedThreadId(DeadThread);
  HelperEvent := CreateEvent(nil, True, False, nil);
  Helper := CreateThread(nil, 0, @HelperThread, nil, 0, HelperTid);
  OwnPid := GetCurrentProcessId;
  OwnTid := GetCurrentThreadId;
  SDeadPid := IntToHex(DeadPid, 8);
  SDeadTid := IntToHex(DeadTid, 8);
  SHelperTid := IntToHex(HelperTid, 8);
  SOwnPid := IntToHex(OwnPid, 8);
  SOwnTid := IntToHex(OwnTid, 8);
  SInst := IntToHex(HInstance, 8); // what Vcl.Controls would write for this program

  // phase 1: this process has no Delphi<pid> atom yet, so a living thread of
  // ours looks like a reused thread id - its ControlOfs atom must go
  Plant('ControlOfs' + SInst + SHelperTid, 1);
  SweepStaleVclAtoms(LogLine);
  Expect('ControlOfs' + SInst + SHelperTid, False);

  // phase 2: the real picture
  Plant('Delphi' + SOwnPid, 1);                           // alive
  Plant('ControlOfs' + SInst + SOwnTid, 1);               // alive
  Plant('WndProcPtr' + SInst + SOwnTid, 1);               // alive
  Plant('ControlOfs' + SInst + SHelperTid, 1);            // alive thread, process has its Delphi atom now
  Plant('ControlOfs12340000' + SOwnTid, 1);               // alive thread, but no module of ours at that address: reused id
  Plant('Delphi' + SDeadPid, 1);                          // finished process
  Plant('ControlOfs00400000' + SDeadTid, 2);              // finished thread, referenced twice
  Plant('WndProcPtr0000000140000000' + SDeadTid, 1);      // finished thread, Win64-style HInstance
  Plant('DDevExtensionsAtomTest', 1);                     // not a VCL atom
  Plant('Delphi' + SDeadPid + '0', 1);                    // wrong length
  Plant('ControlOfs0040000' + SDeadTid, 1);               // too short
  Plant('ControlOfsXX400000' + SDeadTid, 1);              // not hex

  Deleted := SweepStaleVclAtoms(LogLine);

  Expect('Delphi' + SOwnPid, True);
  Expect('ControlOfs' + SInst + SOwnTid, True);
  Expect('WndProcPtr' + SInst + SOwnTid, True);
  Expect('ControlOfs' + SInst + SHelperTid, True);
  Expect('ControlOfs12340000' + SOwnTid, False);
  Expect('Delphi' + SDeadPid, False);
  Expect('ControlOfs00400000' + SDeadTid, False);
  Expect('WndProcPtr0000000140000000' + SDeadTid, False);
  Expect('DDevExtensionsAtomTest', True);
  Expect('Delphi' + SDeadPid + '0', True);
  Expect('ControlOfs0040000' + SDeadTid, True);
  Expect('ControlOfsXX400000' + SDeadTid, True);
  if Deleted < 5 then
  begin
    Inc(Failures);
    WriteLn('FAIL  expected at least 5 deleted references, got ', Deleted);
  end;

  SetEvent(HelperEvent);
  WaitForSingleObject(Helper, 5000);
  CloseHandle(Helper);
  CloseHandle(HelperEvent);
  CloseHandle(DeadThread);
  CloseHandle(DeadProc);

  if Failures = 0 then
    WriteLn('VclAtomSweep: all checks passed (', Deleted, ' stale references deleted)');
  Halt(Failures);
end.
