program FixIfDirectiveParsingTest;

// Command line check for the hook in FixIfDirectiveParsing.pas. It runs the
// hook against a stand-in for the IDE's TPascalScanner.CheckDirective that
// behaves the way the disassembly shows: one skip bit per open block, and
// $IF handled like $IFDEF on the text behind it.
//
//   dcc32 -U..\..\..\..\Shared;..\..\..\..\Shared\IDE -I..;..\..\jedi FixIfDirectiveParsingTest.dpr
//   FixIfDirectiveParsingTest            the hook has to take over
//   FixIfDirectiveParsingTest noifend    scanner without $IFEND: hook must stay passive
//   FixIfDirectiveParsingTest ambiguous  two candidates for the bit stack: passive
//
// Exit code 0 = as expected. The hook decides once per process whether it
// takes over, hence the three runs.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  CondExprEval in 'CondExprEval.pas',
  FixIfDirectiveParsing in 'FixIfDirectiveParsing.pas';

type
  TFakeScanner = class(TObject)
  public
    Filler: array[0..10] of Integer; // moves the state to an offset the hook has to find
    Flag: Byte;                      // reset by every call, like the IDE's flags
    IfState: Cardinal;
    Mirror: Cardinal;                // a second field that follows IfState ("ambiguous")
    Calls: Integer;                  // changes on every call as well
    Depth: Integer;                  // open blocks, to see that pushes and pops balance
    Symbols: TStringList;
    KnowsIfEnd, Mirroring: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

var
  Failures: Integer;

constructor TFakeScanner.Create;
begin
  inherited Create;
  Symbols := TStringList.Create;
  Symbols.Add('MSWINDOWS');
  KnowsIfEnd := True;
end;

destructor TFakeScanner.Destroy;
begin
  Symbols.Free;
  inherited Destroy;
end;

procedure FakeCheckDirective(Scanner: TObject; var P: PAnsiChar);
var
  S: TFakeScanner;
  Start: PAnsiChar;
  Name, Param: AnsiString;

  procedure Push(Skip: Boolean);
  begin
    S.IfState := (S.IfState shl 1) or Cardinal(Ord(Skip));
    Inc(S.Depth);
  end;

begin
  S := TFakeScanner(Scanner);
  Inc(S.Calls);
  S.Flag := 0;

  Start := P;
  while P^ in ['A'..'Z', 'a'..'z', '_'] do
    Inc(P);
  SetString(Name, Start, P - Start);
  Name := AnsiString(UpperCase(string(Name)));

  Start := P; // parameter: the next word
  while Start^ = ' ' do
    Inc(Start);
  SetString(Param, Start, 0);
  while not (Start^ in [#0, ' ', '}', '*']) do
  begin
    Param := Param + Start^;
    Inc(Start);
  end;

  if (Name = 'IFDEF') or (Name = 'IF') then // $IF like $IFDEF - the IDE's bug
    Push(S.Symbols.IndexOf(string(Param)) < 0)
  else if Name = 'IFNDEF' then
    Push(S.Symbols.IndexOf(string(Param)) >= 0)
  else if Name = 'ELSE' then
    S.IfState := S.IfState xor 1
  else if (Name = 'ENDIF') or ((Name = 'IFEND') and S.KnowsIfEnd) then
  begin
    S.IfState := S.IfState shr 1;
    Dec(S.Depth);
  end;
  if S.Mirroring then
    S.Mirror := S.IfState;
end;

{ Lets the scanner meet Directive in a source text, through the hook }
procedure Run(S: TFakeScanner; const Directive: AnsiString);
var
  Source: AnsiString;
  P, NameEnd: PAnsiChar;
begin
  Source := Directive + ' rest of the source';
  P := PAnsiChar(Source);
  while P^ <> '$' do
    Inc(P);
  Inc(P);
  NameEnd := P;
  while NameEnd^ in ['A'..'Z', 'a'..'z', '_'] do
    Inc(NameEnd);
  HookedCheckDirective(S, P);
  if P <> NameEnd then
  begin
    Inc(Failures);
    WriteLn('FAIL  ', Directive, '  P is not behind the directive name');
  end;
end;

procedure Expect(S: TFakeScanner; const What: string; State: Cardinal; Depth: Integer);
begin
  if (S.IfState <> State) or (S.Depth <> Depth) then
  begin
    Inc(Failures);
    WriteLn(Format('FAIL  %s  expected state %d depth %d, got state %d depth %d',
      [What, State, Depth, S.IfState, S.Depth]));
  end;
end;

var
  S: TFakeScanner;
  Passive: Boolean;
begin
  @OrgCheckDirective := @FakeCheckDirective;
  S := TFakeScanner.Create;
  try
    S.KnowsIfEnd := ParamStr(1) <> 'noifend';
    S.Mirroring := ParamStr(1) = 'ambiguous';
    Passive := not S.KnowsIfEnd or S.Mirroring;

    if Passive then
    begin
      // the IDE's behaviour must come through unchanged: $IF = $IFDEF, block skipped
      Run(S, '{$IF CompilerVersion >= 1}');
      Expect(S, 'passive: true $IF still skipped', 1, 1);
      Run(S, '{$ENDIF}');
      Expect(S, 'passive: closed', 0, 0);
      Run(S, '{$IF Defined(MSWINDOWS)}');
      Expect(S, 'passive: second $IF', 1, 1);
    end
    else
    begin
      Run(S, '{$IF CompilerVersion >= 1}');
      Expect(S, 'true $IF keeps the block', 0, 1);
      Run(S, '{$IFEND}');
      Expect(S, 'closed', 0, 0);

      Run(S, '{$IF CompilerVersion >= 999}');
      Expect(S, 'false $IF skips', 1, 1);
      Run(S, '{$ELSE}');
      Expect(S, '$ELSE flips', 0, 1);
      Run(S, '{$ENDIF}');
      Expect(S, 'closed', 0, 0);

      Run(S, '{$if defined(MSWINDOWS) and not Defined(FPC)}');
      Expect(S, 'Defined() asked from the scanner', 0, 1);
      Run(S, '{$IFEND}');
      Run(S, '{$IF Defined(FPC) or (RTLVersion > 999)}');
      Expect(S, 'undefined symbol', 1, 1);
      Run(S, '{$IFEND}');
      Expect(S, 'closed', 0, 0);

      Run(S, '(*$IF CompilerVersion >= 1*)');
      Expect(S, 'paren-star directive', 0, 1);
      Run(S, '(*$IFEND*)');

      Run(S, '{$IF Declared(TBytes)}'); // not understood: the IDE's own handling
      Expect(S, 'unknown expression left to the IDE', 1, 1);
      Run(S, '{$IF CompilerVersion >= 1}'); // nested in a skipped block
      Expect(S, 'nested: outer skip stays', 2, 2);
      Run(S, '{$IFEND}');
      Run(S, '{$IFEND}');
      Expect(S, 'closed', 0, 0);

      Run(S, '{$IFDEF MSWINDOWS}'); // other directives pass through
      Expect(S, '$IFDEF untouched', 0, 1);
      Run(S, '{$ENDIF}');
      Expect(S, 'closed', 0, 0);
    end;
  finally
    S.Free;
  end;

  if Failures = 0 then
    WriteLn('FixIfDirectiveParsing ', ParamStr(1), ': all checks passed');
  Halt(Failures);
end.
