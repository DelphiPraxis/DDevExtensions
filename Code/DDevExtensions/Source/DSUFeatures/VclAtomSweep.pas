{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006-2011 Andreas Hausladen                                            *}
{*                                                                            *}
{******************************************************************************}

unit VclAtomSweep;

{$I ..\DelphiExtension.inc}

interface

// Every VCL program puts entries into the global atom table of the Windows
// session when it starts (unchanged from Delphi 7 to 13):
//
//   Delphi<pid>                       Vcl.Controls.InitControls
//   ControlOfs<hinstance><threadid>   Vcl.Controls.InitControls
//   WndProcPtr<hinstance><threadid>   Vcl.Dialogs initialization
//
// and deletes them in its finalization. A program that is terminated instead
// of closed - "Program Reset" in the IDE, a crash, a kill - never gets there,
// and Windows does not clean the table up on process exit. The table holds
// 16384 entries; when it is full, the clipboard and the UAC prompt fail for
// the whole session.
//
// SweepStaleVclAtoms walks the table and deletes the VCL atoms whose process
// or thread is gone. Everything else, and every atom of a living VCL program,
// is left alone: deleting a live program's ControlOfs atom would break its
// FindControl (it checks GlobalFindAtom(ControlAtomString) = ControlAtom).
//
// Liveness comes from Toolhelp snapshots, which list every process and
// thread of the machine without needing a handle to any of them. A thread id
// is reused by Windows within minutes, so a living thread is only accepted
// as the owner when its process has a Delphi<pid> atom and the HInstance in
// the atom's name is one of that process's loaded modules.

type
  TAtomLogProc = procedure(const Msg: string);

{ Returns the number of atom references deleted }
function SweepStaleVclAtoms(Log: TAtomLogProc): Integer;

implementation

uses
  Windows, SysUtils, TlHelp32;

const
  TH32CS_SNAPMODULE32 = $00000010; // not in every TlHelp32.pas
  FirstGlobalAtom = $C000;
  LastGlobalAtom = $FFFF;

type
  TThreadInfo = record
    Tid, Pid: DWORD;
  end;
  TThreadInfos = array of TThreadInfo;
  TDwords = array of DWORD;
  TBases = array of Int64;

  TAtomEntry = record
    Atom: ATOM;
    Name: string;
  end;
  TAtomEntries = array of TAtomEntry;

function HexDigit(C: Char): Integer; // -1 if C is no hex digit
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
  else
    Result := -1;
  end;
end;

function AllHex(const S: string; From: Integer): Boolean;
var
  I: Integer;
begin
  Result := From <= Length(S);
  for I := From to Length(S) do
    if HexDigit(S[I]) < 0 then
    begin
      Result := False;
      Exit;
    end;
end;

function HexRange(const S: string; From, ToPos: Integer): Int64; // already checked to be hex
var
  I: Integer;
begin
  Result := 0;
  for I := From to ToPos do
    Result := (Result shl 4) or Int64(HexDigit(S[I]));
end;

function Snapshot(Flags, Pid: DWORD): THandle;
var
  Attempt: Integer;
begin
  // a module snapshot can fail with ERROR_BAD_LENGTH while the process is
  // loading something - the documented answer is to try again
  Result := CreateToolhelp32Snapshot(Flags, Pid);
  Attempt := 1;
  while (Result = INVALID_HANDLE_VALUE) and (GetLastError = ERROR_BAD_LENGTH) and (Attempt < 5) do
  begin
    Inc(Attempt);
    Result := CreateToolhelp32Snapshot(Flags, Pid);
  end;
end;

function SnapshotThreads(out Threads: TThreadInfos): Boolean;
var
  H: THandle;
  TE: THREADENTRY32;
  N: Integer;
begin
  Result := False;
  H := Snapshot(TH32CS_SNAPTHREAD, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  N := 0;
  TE.dwSize := SizeOf(TE);
  if Thread32First(H, TE) then
    repeat
      if N = Length(Threads) then
        SetLength(Threads, N * 2 + 512);
      Threads[N].Tid := TE.th32ThreadID;
      Threads[N].Pid := TE.th32OwnerProcessID;
      Inc(N);
    until not Thread32Next(H, TE);
  CloseHandle(H);
  SetLength(Threads, N);
  Result := N > 0;
end;

function SnapshotProcesses(out Pids: TDwords): Boolean;
var
  H: THandle;
  PE: PROCESSENTRY32;
  N: Integer;
begin
  Result := False;
  H := Snapshot(TH32CS_SNAPPROCESS, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  N := 0;
  PE.dwSize := SizeOf(PE);
  if Process32First(H, PE) then
    repeat
      if N = Length(Pids) then
        SetLength(Pids, N * 2 + 64);
      Pids[N] := PE.th32ProcessID;
      Inc(N);
    until not Process32Next(H, PE);
  CloseHandle(H);
  SetLength(Pids, N);
  Result := N > 0;
end;

{ False if the modules cannot be listed (other bitness, elevated process) }
function ModuleBases(Pid: DWORD; out Bases: TBases): Boolean;
var
  H: THandle;
  ME: MODULEENTRY32;
  N: Integer;
begin
  Result := False;
  H := Snapshot(TH32CS_SNAPMODULE or TH32CS_SNAPMODULE32, Pid);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  N := 0;
  ME.dwSize := SizeOf(ME);
  if Module32First(H, ME) then
    repeat
      if N = Length(Bases) then
        SetLength(Bases, N * 2 + 64);
      {$IFDEF CPUX64}
      Bases[N] := Int64(NativeUInt(ME.modBaseAddr));
      {$ELSE}
      Bases[N] := Int64(Cardinal(ME.modBaseAddr));
      {$ENDIF}
      Inc(N);
    until not Module32Next(H, ME);
  CloseHandle(H);
  SetLength(Bases, N);
  Result := N > 0;
end;

function OwnerOfThread(const Threads: TThreadInfos; Tid: DWORD; out Pid: DWORD): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Threads) do
    if Threads[I].Tid = Tid then
    begin
      Pid := Threads[I].Pid;
      Result := True;
      Exit;
    end;
  Result := False;
end;

function ContainsDword(const Values: TDwords; Value: DWORD): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Values) do
    if Values[I] = Value then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function ContainsBase(const Values: TBases; Value: Int64): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Values) do
    if Values[I] = Value then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function HasDelphiAtom(Pid: DWORD): Boolean;
begin
  Result := GlobalFindAtom(PChar('Delphi' + IntToHex(Pid, 8))) <> 0;
end;

function IsStaleVclAtom(const Name: string; const Threads: TThreadInfos; const Pids: TDwords): Boolean;
var
  Tid, Pid: DWORD;
  Inst: Int64;
  Bases: TBases;
begin
  Result := False;
  if (Length(Name) = 14) and (Copy(Name, 1, 6) = 'Delphi') and AllHex(Name, 7) then
    Result := not ContainsDword(Pids, DWORD(HexRange(Name, 7, 14)))
  else if (Length(Name) >= 26) and (Length(Name) <= 34) and
          ((Copy(Name, 1, 10) = 'ControlOfs') or (Copy(Name, 1, 10) = 'WndProcPtr')) and
          AllHex(Name, 11) then
  begin
    // the thread id is the last 8 digits; HInstance before it has 8 (Win32) to 16 (Win64)
    Tid := DWORD(HexRange(Name, Length(Name) - 7, Length(Name)));
    Inst := HexRange(Name, 11, Length(Name) - 8);
    if not OwnerOfThread(Threads, Tid, Pid) then
      Result := True                              // the thread is gone
    else if not HasDelphiAtom(Pid) then
      Result := True                              // id reused by a thread of a non-VCL program
    else if ModuleBases(Pid, Bases) then
      Result := not ContainsBase(Bases, Inst);    // id reused inside a VCL program: HInstance must be one of its modules
  end;
end;

{ A program that was started several times under the same ids while the stale
  entry stood has raised the reference count - take it down to zero }
function DeleteAtomCompletely(Atom: ATOM; const Name: string): Integer;
begin
  Result := 0;
  while (Result < 64) and (GlobalFindAtom(PChar(Name)) = Atom) do
  begin
    if GlobalDeleteAtom(Atom) <> 0 then
      Break;
    Inc(Result);
  end;
end;

function SweepStaleVclAtoms(Log: TAtomLogProc): Integer;
var
  A, I, Len, N: Integer;
  Buf: array[0..255] of Char;
  Entries: TAtomEntries;
  Threads: TThreadInfos;
  Pids: TDwords;
begin
  Result := 0;

  // the names first, the snapshots afterwards: a program that starts in
  // between is in the snapshots but not in the list, so nothing of it is
  // touched; a thread that ends in between is kept until the next sweep
  N := 0;
  for A := FirstGlobalAtom to LastGlobalAtom do
  begin
    Len := GlobalGetAtomName(ATOM(A), Buf, Length(Buf));
    if Len = 0 then
      Continue;
    if N = Length(Entries) then
      SetLength(Entries, N * 2 + 256);
    Entries[N].Atom := ATOM(A);
    SetString(Entries[N].Name, Buf, Len);
    Inc(N);
  end;
  SetLength(Entries, N);

  if not SnapshotThreads(Threads) or not SnapshotProcesses(Pids) then
    Exit; // no facts, no deletions

  for I := 0 to High(Entries) do
  begin
    if not IsStaleVclAtom(Entries[I].Name, Threads, Pids) then
      Continue;
    N := DeleteAtomCompletely(Entries[I].Atom, Entries[I].Name);
    Inc(Result, N);
    if Assigned(Log) then
      Log(Format('deleted %s (%d reference(s))', [Entries[I].Name, N]));
  end;
end;

end.
