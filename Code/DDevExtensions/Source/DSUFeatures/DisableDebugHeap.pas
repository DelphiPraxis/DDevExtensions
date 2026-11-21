{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006-2011 Andreas Hausladen                                            *}
{*                                                                            *}
{******************************************************************************}

unit DisableDebugHeap;

{$I ..\DelphiExtension.inc}

interface

{ When a process is created by a debugger, the loader turns on the Windows heap
  validation flags (FLG_HEAP_ENABLE_TAIL_CHECK and friends in NtGlobalFlag).
  Allocation-heavy code then runs an order of magnitude slower - measured case:
  a Delphi 7 program on a domain machine froze for 25 seconds on the first
  TOpenDialog.Execute, because the legacy GetOpenFileName path enumerates the
  shell namespace including the network providers (WebDAV, Offline Files,
  LanMan, RDP), and every allocation in there went through heap validation. The
  same binary without a debugger attached opened the dialog instantly.

  Windows suppresses the validation flags when the debugged process has
  _NO_DEBUG_HEAP=1 in its environment; Visual Studio ships the same switch as
  "Enable Windows debug heap allocator". The IDE hands its own environment down
  to the process it debugs, so setting the variable here is enough - and it
  stays inside this process instead of ending up user-wide.

  The variable is inert for anything that is not being debugged, so the other
  children of the IDE (the compiler, external tools) are unaffected.

  Note that the debug heap is not pure overhead: it also catches heap misuse in
  the debugged program. Turning it off gives that up, which is why the option
  is off by default. }

procedure InstallDisableDebugHeap(Value: Boolean);

implementation

uses
  Windows;

const
  NoDebugHeapVar = '_NO_DEBUG_HEAP';

procedure InstallDisableDebugHeap(Value: Boolean);
begin
  // takes effect for processes started after this call, i.e. the next debug run
  if Value then
    SetEnvironmentVariable(NoDebugHeapVar, '1')
  else
    SetEnvironmentVariable(NoDebugHeapVar, nil);
end;

end.
