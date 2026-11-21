{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006-2011 Andreas Hausladen                                            *}
{*                                                                            *}
{******************************************************************************}

unit FixIfDirectiveParsing;

{$I ..\DelphiExtension.inc}

interface

// The IDE has its own Pascal scanner (Pasmgr.TPascalScanner). It is the one
// behind the uses clause maintenance of the form designer, class completion
// and the other source updates the IDE does on its own. Its directive handler
// (CheckDirective) keeps one "skip" bit per open conditional block, but it
// cannot evaluate expressions: for $IF it runs the very same code as for
// $IFDEF, taking the text after "$IF" as the name of a conditional symbol. In
//
//   uses
//     {$IF CompilerVersion >= 21}System.Actions, ActnList,{$IFEND} Forms;
//
// it looks for a symbol called "CompilerVersion", does not find one and skips
// the block. The form designer then does not see System.Actions and ActnList
// and adds them once more on every save - the unit stops compiling (E2004
// Identifier redeclared), and removing the two units only lasts until the
// next save. Seen from Delphi 2009 up to 13 (disassembly of delphicoreide370:
// the "IF" branch is a copy of the "IFDEF" branch).
//
// This hooks CheckDirective, evaluates the $IF expression (CondExprEval) and
// pushes the bit the expression really yields. Expressions it does not
// understand are left to the IDE, i.e. skipped as before. $ELSEIF is still
// ignored by the IDE - a block with $ELSEIF is seen as $IF ... $ELSE.
//
// Nothing is written into the scanner object. The bit is pushed by handing
// the original handler an $IFDEF/$IFNDEF of a symbol nobody defines, and
// Defined(X) is answered by the scanner itself (push $IFDEF X, look at the
// bit, pop). Only the position of the bit stack inside the object has to be
// known for that. It is found on first use by watching what a push and a pop
// change, together with a check that the scanner pushes and pops the way this
// unit relies on. If anything is off, the hook stays passive for the session.

procedure InstallFixIfDirectiveParsing(Value: Boolean);

{$IF CompilerVersion >= 20.0}
// The hook itself. In the interface for FixIfDirectiveParsingTest.dpr, which
// runs it against a stand-in for the IDE's handler.
type
  // TPascalScanner.CheckDirective(var P: PAnsiChar); P points behind the "$"
  TCheckDirectiveProc = procedure(Scanner: TObject; var P: PAnsiChar);

var
  OrgCheckDirective: TCheckDirectiveProc;

procedure HookedCheckDirective(Scanner: TObject; var P: PAnsiChar);
{$IFEND}

implementation

{$IF CompilerVersion >= 20.0} // Delphi 7's CheckDirective takes the PChar by value - not looked into

uses
  Windows, SysUtils, IDEHooks, Hooking, CondExprEval;

{.$DEFINE IFDIRDIAG} // diagnostic log to %APPDATA%\DDevExtensions\IfDirective.log (dot = off)

const
  {$IFDEF CPUX64}
  sCheckDirective: PAnsiChar = '_ZN6Pasmgr14TPascalScanner14CheckDirectiveERPc';
  {$ELSE}
  sCheckDirective: PAnsiChar = '@Pasmgr@TPascalScanner@CheckDirective$qqrrpc';
  {$ENDIF}

  // DDevExtensions_NeverDefined is a conditional symbol nobody defines
  sPushSkip: AnsiString = 'IFDEF DDevExtensions_NeverDefined}';
  sPushKeep: AnsiString = 'IFNDEF DDevExtensions_NeverDefined}';
  sPopEndIf: AnsiString = 'ENDIF}';
  sPopIfEnd: AnsiString = 'IFEND}';

  smUnknown = 0;
  smActive = 1;
  smDisabled = 2;

var
  CheckDirectiveAddr: Pointer;
  ScannerMode: Integer; // smXxx
  IfStateOfs: Integer;  // offset of the scanner's skip-bit stack, valid in smActive

{$IFDEF IFDIRDIAG}
var
  LogLines: Integer;

procedure Log(const S: string);
var
  h: THandle;
  Line: AnsiString;
  n: DWORD;
begin
  if LogLines >= 300 then
    Exit;
  Inc(LogLines);
  h := CreateFile(PChar(GetEnvironmentVariable('APPDATA') + '\DDevExtensions\IfDirective.log'),
    GENERIC_WRITE, FILE_SHARE_READ, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if h <> INVALID_HANDLE_VALUE then
  begin
    SetFilePointer(h, 0, nil, FILE_END);
    Line := AnsiString(S) + #13#10;
    WriteFile(h, Line[1], Length(Line), n, nil);
    CloseHandle(h);
  end;
end;
{$ENDIF IFDIRDIAG}

{ Runs a directive through the IDE's own handler, as if it stood in the source }
procedure Feed(Scanner: TObject; const Directive: AnsiString);
var
  P: PAnsiChar;
begin
  P := PAnsiChar(Directive);
  OrgCheckDirective(Scanner, P);
end;

function IfState(Scanner: TObject): Cardinal;
begin
  Result := PCardinal(PAnsiChar(Scanner) + IfStateOfs)^;
end;

{ Finds the skip-bit stack in the scanner that is at work right now and checks
  that it behaves as expected: a new block is pushed at bit 0, a set bit means
  "skipping", $ENDIF and $IFEND pop. The scanner is left as it was. }
function ProbeScanner(Scanner: TObject): Boolean;
var
  Size, Ofs, Found: Integer;
  Before, Pushed1, Pushed2: array of Byte;
  V, V1: Cardinal;
begin
  Result := False;
  Size := Scanner.InstanceSize and not 3;
  if (Size < 8) or (Size > $10000) then
    Exit;
  SetLength(Before, Size);
  SetLength(Pushed1, Size);
  SetLength(Pushed2, Size);
  Move(Pointer(Scanner)^, Before[0], Size);
  Feed(Scanner, sPushSkip);
  Move(Pointer(Scanner)^, Pushed1[0], Size);
  Feed(Scanner, sPushSkip);
  Move(Pointer(Scanner)^, Pushed2[0], Size);
  Feed(Scanner, sPopEndIf);
  Feed(Scanner, sPopEndIf);

  // the one DWORD that had a set bit shifted in twice and is back to its value
  // (two pushes, because a plain nesting counter goes 0 -> 1 -> 0 as well)
  Found := -1;
  Ofs := 0;
  while Ofs < Size do
  begin
    V := PCardinal(@Before[Ofs])^;
    V1 := (V shl 1) or 1;
    if (V and $C0000000 = 0) and (PCardinal(@Pushed1[Ofs])^ = V1) and
       (PCardinal(@Pushed2[Ofs])^ = (V1 shl 1) or 1) and
       (PCardinal(PAnsiChar(Scanner) + Ofs)^ = V) then
    begin
      if Found <> -1 then
        Exit; // ambiguous
      Found := Ofs;
    end;
    Inc(Ofs, 4);
  end;
  if Found = -1 then
    Exit;
  IfStateOfs := Found;

  // $IFNDEF of an undefined symbol has to push a clear bit and $IFEND has to
  // pop. Both are only visible on top of a set bit - a clear bit on an empty
  // stack changes nothing.
  V := IfState(Scanner);
  Feed(Scanner, sPushSkip);
  V1 := IfState(Scanner);
  Feed(Scanner, sPushKeep);
  if IfState(Scanner) = V1 shl 1 then
  begin
    Feed(Scanner, sPopIfEnd);
    Result := IfState(Scanner) = V1;
    if not Result then
      Feed(Scanner, sPopEndIf); // no $IFEND in this scanner: undo the push, stay passive
  end
  else if IfState(Scanner) <> V1 then
    Feed(Scanner, sPopEndIf);
  Feed(Scanner, sPopEndIf);
  Result := Result and (IfState(Scanner) = V);
end;

{ Defined(Symbol), answered by the scanner's own conditional symbol table }
function SymbolDefined(const Symbol: AnsiString; Data: Pointer): Boolean;
begin
  Feed(TObject(Data), 'IFDEF ' + Symbol + '}');
  Result := IfState(TObject(Data)) and 1 = 0;
  Feed(TObject(Data), sPopEndIf);
end;

procedure HookedCheckDirective(Scanner: TObject; var P: PAnsiChar);
var
  Start, Stop: PAnsiChar;
  Expr: AnsiString;
  Cond: Boolean;
begin
  Start := P;
  if (ScannerMode <> smDisabled) and (Start <> nil) and
     (Start[0] in ['I', 'i']) and (Start[1] in ['F', 'f']) and
     not (Start[2] in ['A'..'Z', 'a'..'z', '_']) then
  begin
    if ScannerMode = smUnknown then
    begin
      if ProbeScanner(Scanner) then
        ScannerMode := smActive
      else
        ScannerMode := smDisabled;
      {$IFDEF IFDIRDIAG}
      Log(Format('probe: %s, mode=%d, bit stack at +$%x, instance size %d',
        [Scanner.ClassName, ScannerMode, IfStateOfs, Scanner.InstanceSize]));
      {$ENDIF IFDIRDIAG}
    end;

    // ponytail: the bit stack holds 32 blocks and the Defined() probe needs one;
    // beyond 30 open blocks the IDE's own handling stays in charge
    if (ScannerMode = smActive) and (IfState(Scanner) and $C0000000 = 0) then
    begin
      Inc(Start, 2);
      Stop := Start; // the directive ends at "}" or "*)"
      while not (Stop^ in [#0, '}']) and not ((Stop^ = '*') and (Stop[1] = ')')) do
        Inc(Stop);
      SetString(Expr, Start, Stop - Start);
      if EvalCondExpr(Expr, SymbolDefined, Scanner, Cond) then
      begin
        {$IFDEF IFDIRDIAG}
        Log(Format('$IF%s -> %s', [string(Expr), BoolToStr(Cond, True)]));
        {$ENDIF IFDIRDIAG}
        if Cond then
          Feed(Scanner, sPushKeep)
        else
          Feed(Scanner, sPushSkip);
        P := Start; // behind the directive's name, where the original leaves it as well
        Exit;
      end;
      {$IFDEF IFDIRDIAG}
      Log(Format('$IF%s -> not understood, left to the IDE', [string(Expr)]));
      {$ENDIF IFDIRDIAG}
    end;
  end;
  OrgCheckDirective(Scanner, P);
end;

procedure InstallFixIfDirectiveParsing(Value: Boolean);
var
  Lib: THandle;
begin
  if Value = (CheckDirectiveAddr <> nil) then
    Exit;
  if Value then
  begin
    Lib := GetModuleHandle(delphicoreide_bpl);
    if Lib <> 0 then
      CheckDirectiveAddr := GetProcAddress(Lib, sCheckDirective);
    if CheckDirectiveAddr <> nil then
      @OrgCheckDirective := RedirectOrgCall(CheckDirectiveAddr, @HookedCheckDirective);
  end
  else
  begin
    RestoreOrgCall(CheckDirectiveAddr, @OrgCheckDirective);
    @OrgCheckDirective := nil;
    CheckDirectiveAddr := nil;
  end;
end;

initialization

finalization
  InstallFixIfDirectiveParsing(False);

{$ELSE}

procedure InstallFixIfDirectiveParsing(Value: Boolean);
begin
end;

{$IFEND}

end.
