{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006-2011 Andreas Hausladen                                            *}
{*                                                                            *}
{******************************************************************************}

unit CondExprEval;

// Evaluates the expression of a $IF / $ELSEIF compiler directive, e.g.
//   CompilerVersion >= 21
//   Defined(MSWINDOWS) and not Defined(FPC)
//   (RTLVersion < 23) or Defined(FORCE_OLD)
//
// Understood: CompilerVersion and RTLVersion (the values of the compiler this
// unit was built with - for an IDE plugin that is the IDE's own compiler),
// numbers, True/False, Defined(Symbol), not/and/or/xor, the six comparisons
// and parentheses, with Pascal's operator precedence.
//
// Anything else - Declared(SomeType), SizeOf(), constants from other units -
// makes the function return False. It never guesses.
//
// No dependencies on purpose, so CondExprEvalTest.dpr can check it from the
// command line.

interface

type
  TCondDefinedFunc = function(const Symbol: AnsiString; Data: Pointer): Boolean;

{ Returns True if the expression was understood; Value is its result then. }
function EvalCondExpr(const Expr: AnsiString; IsDefined: TCondDefinedFunc; Data: Pointer;
  out Value: Boolean): Boolean;

implementation

type
  TCondValue = record
    IsBool: Boolean;
    B: Boolean;
    N: Double;
  end;

function EvalCondExpr(const Expr: AnsiString; IsDefined: TCondDefinedFunc; Data: Pointer;
  out Value: Boolean): Boolean;
const
  IdentChars = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
var
  P: PAnsiChar;
  Failed: Boolean;

  procedure SkipWhite;
  begin
    while P^ in [#1..' '] do
      Inc(P);
  end;

  function ReadIdent: AnsiString;
  var
    S: PAnsiChar;
  begin
    SkipWhite;
    S := P;
    while P^ in IdentChars do
      Inc(P);
    SetString(Result, S, P - S);
  end;

  function Upper(const S: AnsiString): AnsiString;
  var
    I: Integer;
  begin
    Result := S;
    for I := 1 to Length(Result) do
      if Result[I] in ['a'..'z'] then
        Dec(Result[I], 32);
  end;

  function AcceptWord(const UpperWord: AnsiString): Boolean;
  var
    Q: PAnsiChar;
    I: Integer;
  begin
    Result := False;
    SkipWhite;
    Q := P;
    for I := 1 to Length(UpperWord) do
    begin
      if UpCase(Q^) <> UpperWord[I] then
        Exit;
      Inc(Q);
    end;
    if Q^ in IdentChars then
      Exit;
    P := Q;
    Result := True;
  end;

  function AcceptRelOp: Integer; // 0 = none
  begin
    Result := 0;
    SkipWhite;
    case P^ of
      '=': Result := 1;
      '<':
        if P[1] = '>' then
          Result := 2
        else if P[1] = '=' then
          Result := 4
        else
          Result := 3;
      '>':
        if P[1] = '=' then
          Result := 6
        else
          Result := 5;
    end;
    if Result in [2, 4, 6] then
      Inc(P, 2)
    else if Result <> 0 then
      Inc(P);
  end;

  function ParseExpr: TCondValue; forward;

  function ParsePrimary: TCondValue;
  var
    S: PAnsiChar;
    Num, Ident, Arg: AnsiString;
    Code, IntValue: Integer;
  begin
    Result.IsBool := False;
    Result.B := False;
    Result.N := 0;
    SkipWhite;
    if P^ = '(' then
    begin
      Inc(P);
      Result := ParseExpr;
      SkipWhite;
      if P^ = ')' then
        Inc(P)
      else
        Failed := True;
    end
    else if P^ in ['0'..'9', '$'] then
    begin
      S := P;
      Inc(P);
      if S^ = '$' then
      begin
        while P^ in ['0'..'9', 'A'..'F', 'a'..'f'] do
          Inc(P);
        SetString(Num, S, P - S);
        Val(string(Num), IntValue, Code);
        Result.N := IntValue;
      end
      else
      begin
        while P^ in ['0'..'9', '.'] do
          Inc(P);
        SetString(Num, S, P - S);
        Val(string(Num), Result.N, Code);
      end;
      if Code <> 0 then
        Failed := True;
    end
    else
    begin
      Ident := Upper(ReadIdent);
      if Ident = 'COMPILERVERSION' then
        Result.N := CompilerVersion
      else if Ident = 'RTLVERSION' then
        Result.N := RTLVersion
      else if (Ident = 'TRUE') or (Ident = 'FALSE') then
      begin
        Result.IsBool := True;
        Result.B := Ident = 'TRUE';
      end
      else if (Ident = 'DEFINED') or (Ident = 'DECLARED') then
      begin
        SkipWhite;
        if P^ = '(' then
          Inc(P)
        else
          Failed := True;
        Arg := ReadIdent;
        SkipWhite;
        if P^ = ')' then
          Inc(P)
        else
          Failed := True;
        Result.IsBool := True;
        if Failed or (Arg = '') then
          Failed := True
        else if Ident = 'DEFINED' then
        begin
          if Assigned(IsDefined) then
            Result.B := IsDefined(Arg, Data) // in the spelling of the source
          else
            Failed := True;
        end
        else if (Upper(Arg) = 'COMPILERVERSION') or (Upper(Arg) = 'RTLVERSION') then
          Result.B := True // both exist since Delphi 6
        else
          Failed := True; // would need the real symbol tables
      end
      else
        Failed := True;
    end;
  end;

  function ParseFactor: TCondValue;
  begin
    if AcceptWord('NOT') then
    begin
      Result := ParseFactor;
      if Result.IsBool then
        Result.B := not Result.B
      else
        Failed := True;
    end
    else
      Result := ParsePrimary;
  end;

  function ParseTerm: TCondValue;
  var
    R: TCondValue;
  begin
    Result := ParseFactor;
    while not Failed and AcceptWord('AND') do
    begin
      R := ParseFactor;
      if Result.IsBool and R.IsBool then
        Result.B := Result.B and R.B
      else
        Failed := True;
    end;
  end;

  function ParseSimple: TCondValue;
  var
    R: TCondValue;
    IsXor: Boolean;
  begin
    Result := ParseTerm;
    while not Failed do
    begin
      IsXor := False;
      if not AcceptWord('OR') then
      begin
        if not AcceptWord('XOR') then
          Break;
        IsXor := True;
      end;
      R := ParseTerm;
      if not (Result.IsBool and R.IsBool) then
        Failed := True
      else if IsXor then
        Result.B := Result.B xor R.B
      else
        Result.B := Result.B or R.B;
    end;
  end;

  function ParseExpr: TCondValue;
  var
    R: TCondValue;
    Op: Integer;
  begin
    Result := ParseSimple;
    if Failed then
      Exit;
    Op := AcceptRelOp;
    if Op = 0 then
      Exit;
    R := ParseSimple;
    if Failed or (Result.IsBool <> R.IsBool) then
    begin
      Failed := True;
      Exit;
    end;
    if Result.IsBool then
    begin
      Result.N := Ord(Result.B);
      R.N := Ord(R.B);
    end;
    case Op of
      1: Result.B := Result.N = R.N;
      2: Result.B := Result.N <> R.N;
      3: Result.B := Result.N < R.N;
      4: Result.B := Result.N <= R.N;
      5: Result.B := Result.N > R.N;
      6: Result.B := Result.N >= R.N;
    end;
    Result.IsBool := True;
  end;

var
  V: TCondValue;
begin
  P := PAnsiChar(Expr);
  Failed := False;
  V := ParseExpr;
  SkipWhite;
  Result := not Failed and (P^ = #0) and V.IsBool;
  Value := Result and V.B;
end;

end.
