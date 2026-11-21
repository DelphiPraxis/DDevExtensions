unit DiagHiddenExcept;

{ Diagnostic-only unit, compiled into the madExcept build (build_d13_diag_x64.bat).
  The x64 "Home on a blank line" exception is HANDLED by the IDE, so madExcept's
  normal (unhandled-only) reporting never fires. Here we register a HIDDEN
  (handled) exception handler that logs the bug report - only for exceptions
  whose report passes through DDevExtensions - to %APPDATA%\DDevExtensions\
  HiddenExcept.log, so the throwing DDev hook can be identified. Excluded from
  normal builds (guarded by the madExcept conditional define). }

interface

implementation

{$IFDEF madExcept}
uses
  Windows, SysUtils, madExcept;

var
  LogCount: Integer;

procedure OnHidden(const exceptIntf: IMEException; var handled: Boolean);
var
  rep, fn: string;
  F: TextFile;
begin
  try
    if LogCount >= 30 then
      Exit;
    rep := exceptIntf.GetBugReport(False, 3000);   // partial (fast) report incl. call stack
    if Pos('DDevExtensions', rep) = 0 then
      Exit;                                         // only exceptions passing through our DLL
    Inc(LogCount);
    fn := GetEnvironmentVariable('APPDATA') + '\DDevExtensions\HiddenExcept.log';
    AssignFile(F, fn);
    if FileExists(fn) then
      Append(F)
    else
      Rewrite(F);
    try
      WriteLn(F, '================ hidden exception #' + IntToStr(LogCount) + ' ================');
      WriteLn(F, 'class: ' + string(exceptIntf.ExceptClass));
      WriteLn(F, 'msg  : ' + string(exceptIntf.ExceptMessage));
      WriteLn(F, rep);
      WriteLn(F, '');
    finally
      CloseFile(F);
    end;
  except
    // diagnostics must never break the IDE
  end;
end;

initialization
  RegisterHiddenExceptionHandler(OnHidden, stDontSync);
{$ENDIF}
end.
