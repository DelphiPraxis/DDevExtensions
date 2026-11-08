program CondExprEvalTest;

// Command line check for CondExprEval.pas:
//   dcc32 -CC CondExprEvalTest.dpr && CondExprEvalTest
// Exit code 0 = all expressions evaluated as expected.

{$APPTYPE CONSOLE}

uses
  CondExprEval in 'CondExprEval.pas';

var
  Failures: Integer;

function IsDefined(const Symbol: AnsiString; Data: Pointer): Boolean;
begin
  // the symbol arrives in the spelling of the expression
  Result := (Symbol = 'MSWINDOWS') or (Symbol = 'DEBUG') or (Symbol = 'debug');
end;

{ Expected: 'T' / 'F' = understood with that result, '?' = not understood }
procedure Check(const Expr: AnsiString; Expected: AnsiChar);
var
  Value: Boolean;
  Got: AnsiChar;
begin
  if not EvalCondExpr(Expr, IsDefined, nil, Value) then
    Got := '?'
  else if Value then
    Got := 'T'
  else
    Got := 'F';
  if Got <> Expected then
  begin
    Inc(Failures);
    WriteLn('FAIL  ', Expr, '  expected ', Expected, ', got ', Got);
  end;
end;

begin
  Check('CompilerVersion >= 1', 'T');
  Check(' CompilerVersion>=999 ', 'F');
  Check('compilerversion < 999.5', 'T');
  Check('RTLVersion >= 14', 'T');
  Check('CompilerVersion = CompilerVersion', 'T');
  Check('CompilerVersion <> CompilerVersion', 'F');
  Check('$10 = 16', 'T');
  Check('Defined(MSWINDOWS)', 'T');
  Check('defined( debug )', 'T');
  Check('Defined(FPC)', 'F');
  Check('not Defined(FPC)', 'T');
  Check('Defined(MSWINDOWS) and not Defined(FPC)', 'T');
  Check('Defined(FPC) or Defined(LINUX)', 'F');
  Check('Defined(FPC) xor Defined(DEBUG)', 'T');
  Check('(CompilerVersion >= 1) and Defined(DEBUG)', 'T');
  Check('(CompilerVersion >= 999) or (RTLVersion >= 999)', 'F');
  Check('not ((CompilerVersion >= 999) or Defined(FPC))', 'T');
  Check('Defined(FPC) = False', 'T');
  Check('True', 'T');
  Check('False', 'F');
  Check('Declared(RTLVersion) and (RTLVersion >= 14)', 'T');
  Check('Defined(MSWINDOWS)'#13#10'  and Defined(DEBUG)', 'T');
  // not understood - must be reported, never guessed
  Check('', '?');
  Check('CompilerVersion', '?');
  Check('CompilerVersion >=', '?');
  Check('CompilerVersion >= 21 and Defined(DEBUG)', '?'); // Pascal precedence: 21 and ...
  Check('Declared(TBytes)', '?');
  Check('SizeOf(Pointer) = 8', '?');
  Check('Defined(MSWINDOWS', '?');
  Check('Defined(MSWINDOWS) garbage', '?');
  Check('SomeConst > 5', '?');
  Check('not 5', '?');

  if Failures = 0 then
    WriteLn('CondExprEval: all checks passed');
  Halt(Failures);
end.
