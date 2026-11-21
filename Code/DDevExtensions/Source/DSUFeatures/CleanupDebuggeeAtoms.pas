{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006-2011 Andreas Hausladen                                            *}
{*                                                                            *}
{******************************************************************************}

unit CleanupDebuggeeAtoms;

{$I ..\DelphiExtension.inc}

interface

// "Program Reset" (Ctrl+F2) terminates the debugged program; its VCL never
// reaches the finalization that would delete its global atoms (see
// VclAtomSweep). This runs the sweep when the IDE starts - for what the last
// session or an IDE crash left behind - and a moment after every debug
// process ends.

procedure InstallCleanupDebuggeeAtoms(Value: Boolean);

implementation

uses
  Windows, SysUtils, Classes, ExtCtrls, ToolsAPI, VclAtomSweep;

{.$DEFINE ATOMDIAG} // log to %APPDATA%\DDevExtensions\Atoms.log (dot = off)

const
  // the debuggee's threads need a moment to disappear after ProcessDestroyed
  SweepDelayMs = 1500;

type
  TAtomSweepNotifier = class(TNotifierObject, IOTANotifier, IOTADebuggerNotifier)
  private
    FTimer: TTimer;
    procedure TimerTick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    { IOTADebuggerNotifier }
    procedure ProcessCreated({$IF CompilerVersion >= 20.0}const{$IFEND} Process: IOTAProcess);
    procedure ProcessDestroyed({$IF CompilerVersion >= 20.0}const{$IFEND} Process: IOTAProcess);
    procedure BreakpointAdded({$IF CompilerVersion >= 20.0}const{$IFEND} Breakpoint: IOTABreakpoint);
    procedure BreakpointDeleted({$IF CompilerVersion >= 20.0}const{$IFEND} Breakpoint: IOTABreakpoint);
  end;

var
  GNotifierIndex: Integer = -1;

{$IFDEF ATOMDIAG}
procedure Log(const Msg: string);
var
  H: THandle;
  Line: AnsiString;
  N: DWORD;
begin
  H := CreateFile(PChar(GetEnvironmentVariable('APPDATA') + '\DDevExtensions\Atoms.log'),
    GENERIC_WRITE, FILE_SHARE_READ, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if H <> INVALID_HANDLE_VALUE then
  begin
    SetFilePointer(H, 0, nil, FILE_END);
    Line := AnsiString(FormatDateTime('yyyy-mm-dd hh:nn:ss ', Now) + Msg) + #13#10;
    WriteFile(H, Line[1], Length(Line), N, nil);
    CloseHandle(H);
  end;
end;
{$ENDIF ATOMDIAG}

procedure Sweep;
{$IFDEF ATOMDIAG}
var
  N: Integer;
begin
  N := SweepStaleVclAtoms(Log);
  Log(Format('sweep: %d reference(s) deleted', [N]));
end;
{$ELSE}
begin
  SweepStaleVclAtoms(nil);
end;
{$ENDIF ATOMDIAG}

{ TAtomSweepNotifier }

constructor TAtomSweepNotifier.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := SweepDelayMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtomSweepNotifier.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

procedure TAtomSweepNotifier.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  Sweep;
end;

procedure TAtomSweepNotifier.ProcessCreated({$IF CompilerVersion >= 20.0}const{$IFEND} Process: IOTAProcess);
begin
end;

procedure TAtomSweepNotifier.ProcessDestroyed({$IF CompilerVersion >= 20.0}const{$IFEND} Process: IOTAProcess);
begin
  FTimer.Enabled := False; // restart: one sweep covers several processes ending together
  FTimer.Enabled := True;
end;

procedure TAtomSweepNotifier.BreakpointAdded({$IF CompilerVersion >= 20.0}const{$IFEND} Breakpoint: IOTABreakpoint);
begin
end;

procedure TAtomSweepNotifier.BreakpointDeleted({$IF CompilerVersion >= 20.0}const{$IFEND} Breakpoint: IOTABreakpoint);
begin
end;

procedure InstallCleanupDebuggeeAtoms(Value: Boolean);
begin
  if Value then
  begin
    if (GNotifierIndex >= 0) or (BorlandIDEServices = nil) then
      Exit;
    GNotifierIndex := (BorlandIDEServices as IOTADebuggerServices).AddNotifier(TAtomSweepNotifier.Create);
    Sweep; // what the last session or an IDE crash left behind
  end
  else if GNotifierIndex >= 0 then
  begin
    try
      // from the finalization BorlandIDEServices may already be gone
      if Assigned(BorlandIDEServices) then
        (BorlandIDEServices as IOTADebuggerServices).RemoveNotifier(GNotifierIndex);
    except
    end;
    GNotifierIndex := -1;
  end;
end;

initialization

finalization
  InstallCleanupDebuggeeAtoms(False);

end.
