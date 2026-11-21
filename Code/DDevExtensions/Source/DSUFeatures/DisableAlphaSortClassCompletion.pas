{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006-2011 Andreas Hausladen                                            *}
{*                                                                            *}
{******************************************************************************}

unit DisableAlphaSortClassCompletion;

{$I ..\DelphiExtension.inc}

{$IFDEF CPUX64}
  // x64 IAT-gated reorder + SetSorted no-op. Reverse-engineered against
  // delphicoreide370 (D13.1), but no longer version-locked: the install is
  // all-or-nothing with a UNIQUE-match requirement on the fragile SetSorted
  // site, and the runtime gate self-validates the live object layout on the
  // first real completion (AlphaValidateIterator) and self-disables on any IDE
  // build whose Complete/layout does not match - so it can be attempted on any
  // x64 IDE (e.g. D12/coreide290, a future D14) and safely turns itself off
  // where it does not fit, instead of needing a per-version compile guard.
  {$DEFINE ALPHASORT_X64_WIP}
{$ENDIF}

interface

procedure InstallDisableAlphaSortClassCompletion(Value: Boolean);

implementation

{$IF CompilerVersion < 20.0} // mirrors 2009+ compiler internals; not available on D7
procedure InstallDisableAlphaSortClassCompletion(Value: Boolean);
begin
end;
{$ELSE}

uses
  Windows, SysUtils, Classes, TypInfo, Hooking, IDEHooks;

type
  TClassSymbol = class
  end;

  TBaseSymbol = class(TObject)
  public
    Next: TBaseSymbol;
    FShortIdent: ShortString;    //UTF8-encoded data
    FIdent: UnicodeString;
  end;

  TSymbolTable = class(TObject)
  private
    FCount: Integer;
    FSymbolList: array[0..31] of TBaseSymbol;
    //FCompare: TCompareSymbols;
  public
    property Count: Integer read FCount;
  end;

  TTableIterator = class
  protected
    FxxxLocation: Integer;
    FxxxIndex: Integer;
    FxxxSymbol: TBaseSymbol;
    FCount: Integer; // FCount must be at this offset

    FSymbols: array of TBaseSymbol;

    function GetSymbol(Index: Integer): TBaseSymbol;
    procedure LoadSymbols(Table: TSymbolTable);
    procedure QuickSort(L, R: Integer);
  public
    constructor Create(Table: TSymbolTable);
    property Count: Integer read FCount;
    property Symbols[Index: Integer]: TBaseSymbol read GetSymbol; default;
  end;

  TMethodSymbol = class;

  TAccess = (saDefault, saStrictPrivate, saPrivate, saStrictProtected, saProtected, saPublic, saPublished, saAutomated);

  TMethodSignature = class
  public
    MethodSymbol: TMethodSymbol;
    TypeData: PTypeData;
    TypeSize: Word;
    Empty: Boolean;
    HeaderPos, HeaderNamePos, HeaderEnd, HeaderLineEnd: LongInt;
    CodePos, CodeNamePos, CodeHeaderEnd, CodeBegin, CodeEnd, CodeStatement: LongInt;
    ImplHeaderEnd, ImplEnd: LongInt;
    BeginPos: LongInt;
    Access: TAccess;
    DispidPos, DispidEnd: LongInt;
    Next: TMethodSignature;
    InterfaceMethod: Boolean;
    NestedProcedures: TSymbolTable;

    function IsImplemented: Boolean;
    function GetTypeSortId: Integer;
  end;

  TMethodSymbol = class(TBaseSymbol)
  public
    FMethodSignature: TMethodSignature;
  end;

var
  OrgTClassSymbol_MethodAddPos: function(Instance: TClassSymbol; const Name: string): Integer;
  OrgTSortedThingList_SetSorted: Pointer;
  OrgTTableIterator_Ctor: Pointer;
  OrgTTableIterator_GetSymbol: Pointer;

  CallAddrTSortedThingList_SetSortedP: PByte;
  CompleteMethodSymbolTableIteratorP: PByte;

{$IFNDEF CPUX64}
function TClassSymbol_MethodAddPos(Instance: TClassSymbol; const Name: string): Integer;
  external delphicoreide_bpl name '@Pasmgr@TClassSymbol@MethodAddPos$qqrx20System@UnicodeString';
{$ENDIF}
{$IFDEF CPUX64}
function TClassSymbol_MethodAddPos(Instance: TClassSymbol; const Name: string): Integer;
  external delphicoreide_bpl name '_ZN6Pasmgr12TClassSymbol12MethodAddPosEN6System13UnicodeStringE';
{$ENDIF}

{$IFNDEF CPUX64}
procedure TPascalClassCompleter_Complete;
  external delphicoreide_bpl name '@Completers@TPascalClassCompleter@Complete$qqrx20System@UnicodeString';
{$ENDIF}
{$IFDEF CPUX64}
procedure TPascalClassCompleter_Complete;
  external delphicoreide_bpl name '_ZN10Completers21TPascalClassCompleter8CompleteEN6System13UnicodeStringE';
{$ENDIF}

function TClassSymbol_MethodAddPos_AlphSort(Instance: TClassSymbol; const Name: string): Integer;
begin
  Result := OrgTClassSymbol_MethodAddPos(Instance, '');
end;

procedure TSortedThingList_SetSorted(Instance: TObject; Value: Boolean);
begin
  // don't sort the list, the TTableIterator already did that
end;

{ TTableIterator }

constructor TTableIterator.Create(Table: TSymbolTable);
begin
  inherited Create;
  if Table <> nil then
    LoadSymbols(Table);
end;

procedure TTableIterator.LoadSymbols(Table: TSymbolTable);
var
  Index: Integer;
  Symbol: TBaseSymbol;
  Location: Integer;
begin
  FCount := Table.Count;
  SetLength(FSymbols, FCount);

  Index := 0;
  for Location := 0 to Length(Table.FSymbolList) - 1 do
  begin
    Symbol := Table.FSymbolList[Location];
    if Symbol <> nil then
    begin
      repeat
        FSymbols[Index] := Symbol;
        Inc(Index);
        Symbol := Symbol.Next;
      until Symbol = nil;
      if Index >= FCount then
        Break;
    end;
  end;

  if Count > 0 then
    QuickSort(0, Count - 1);
end;

function TTableIterator.GetSymbol(Index: Integer): TBaseSymbol;
begin
  Result := FSymbols[Index];
end;


function CompareInt(V1, V2: Integer): Integer; inline;
begin
  if V1 = V2 then
    Result := 0
  else if V1 > V2 then
    Result := 1
  else
    Result := -1;
end;

function CompareSymbol(Sym1, Sym2: TBaseSymbol): Integer;
var
  M1, M2: TMethodSymbol;
  Id1, Id2: Integer;
  HP1, HP2: Integer;
begin
  if Sym1 <> Sym2 then
  begin
    M1 := TMethodSymbol(Sym1);
    M2 := TMethodSymbol(Sym2);
    Id1 := M1.FMethodSignature.GetTypeSortId;
    Id2 := M2.FMethodSignature.GetTypeSortId;

    if Id1 = Id2 then
    begin
      HP1 := M1.FMethodSignature.HeaderPos;
      HP2 := M2.FMethodSignature.HeaderPos;
      if (HP1 = 0) and (HP2 = 0) then
        Result := CompareInt(M1.FMethodSignature.CodePos, M2.FMethodSignature.CodePos)
      else
        Result := CompareInt(HP1, HP2);
    end
    else if Id1 > Id2 then
      Result := 1
    else
      Result := -1;
  end
  else
    Result := 0;
end;

procedure TTableIterator.QuickSort(L, R: Integer);
var
  I, J: Integer;
  P, T: TBaseSymbol;
begin
  repeat
    I := L;
    J := R;
    P := FSymbols[(L + R) shr 1];
    repeat
      while CompareSymbol(FSymbols[I], P) < 0 do
        Inc(I);
      while CompareSymbol(FSymbols[J], P) > 0 do
        Dec(J);
      if I <= J then
      begin
        if I <> J then
        begin
          T := FSymbols[I];
          FSymbols[I] := FSymbols[J];
          FSymbols[J] := T;
        end;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then
      QuickSort(L, J);
    L := I;
  until I >= R;
end;

{ TMethodSignature }

function TMethodSignature.IsImplemented: Boolean;
begin
  Result := (CodePos <> 0) and (TypeData <> nil);
end;

function TMethodSignature.GetTypeSortId: Integer;
begin
  Result := 100;
  if TypeData <> nil then
  begin
    case TypeData.MethodKind of
      mkClassConstructor:
        Result := 0;
      {$IF CompilerVersion >= 21.0} // 2010+
      mkClassDestructor:
        Result := 1;
      {$IFEND}
      mkConstructor:
        Result := 2;
      mkDestructor:
        Result := 3;
//      mkClassProcedure, mkClassFunction:
//        Result := 4;
      mkOperatorOverload:
        Result := 200;
    end;
  end;
end;

{-------------------------------------------------------------------------------------------------}

function TTableIterator_Create(ASymbolTable: TSymbolTable): TTableIterator;
begin
  Result := TTableIterator.Create(ASymbolTable);
end;

{$IFNDEF CPUX64}
function MethodSymbolTableIteratorFactory(AClass: TClass; DL: Integer; ASymbolTable: TSymbolTable): TTableIterator;
asm
  push ecx

  // Sort all items that are already collected
  mov eax, [ebp-$10] // Thingslist
  mov edx, 1
  call [OrgTSortedThingList_SetSorted]

  // Disable sorting so that the methods can be added in their correct order
// !!! Sorting is implemented wrongly. Disabling sort calls TList.Sort, and as long as nobody calls SetSorted no further sorting is done
//  mov eax, [ebp-$10] // Thingslist
//  xor edx, edx
//  call [OrgTSortedThingList_SetSorted]

  pop eax
  call TTableIterator_Create
end;
{$ELSE}
function MethodSymbolTableIteratorFactory(AClass: TClass; DL: Integer; ASymbolTable: TSymbolTable): TTableIterator;
begin
  // Win64: simplified fallback - just create the iterator without sorting hack
  Result := TTableIterator_Create(ASymbolTable);
end;
{$ENDIF ~CPUX64}
{begin
  // Sort all items that are already collected
  OrgTSortedThingList_SetSorted(ThingList, True);
  // Disable sorting so that the methods can be added in their correct order
  //OrgTSortedThingList_SetSorted(ThingList, False);

  Result := TTableIterator.Create;
end;}

{-------------------------------------------------------------------------------------------------}

{$IFDEF CPUX64}
{$IFDEF ALPHASORT_X64_WIP}
// ---------------------------------------------------------------------------
//  Delphi 13 x64 implementation. The x86 path scans Complete for byte patterns
//  and ReplaceRelCallOffset-patches the iterator ctor / GetSymbol / SetSorted
//  calls. On x64 the iterator ctor / GetSymbol calls are IMPORTED from
//  designide370 (Symbols::TTableIterator) via delphicoreide370 IAT stubs. The
//  TSortedThingList.SetSorted(True) call - the one that re-sorts the collected
//  "to add" list ALPHABETICALLY right before the implementation stubs are
//  generated - does exist on x64 too, as an internal E8 call inside Complete
//  (TSortedThingList is not exported from the 64-bit BPLs, which is why it was
//  first believed to be folded into the ctor; it is not). All the object
//  layouts this unit relies on (TSymbolTable.FCount@+8/FSymbolList@+0x10,
//  TBaseSymbol.Next@+8, TMethodSymbol.FMethodSignature@+0x118,
//  TMethodSignature.HeaderPos@+0x1C/CodePos@+0x2C, TTableIterator.FCount@+0x18)
//  were confirmed by a diagnostic round against the live IDE and match exactly
//  what the compiler generates for these decls on x64.
//
//  Wiring strategy:
//  - Patch the ctor & GetSymbol IAT slots (full 64-bit pointer, so no rel32 /
//    near-trampoline concern) to gate functions that check whether the
//    caller's return address is inside TPascalClassCompleter.Complete:
//      - from Complete  -> our reordering factory / GetSymbol (decl order)
//      - otherwise      -> delegate to the real designide ctor / GetSymbol
//    so the IDE-wide IAT patch is safe for every other caller.
//  - NOP out the SetSorted(True) call site in Complete. The x86 feature
//    redirects that call to an empty procedure; same effect. Without it the
//    completer re-sorts the "to add" list and the generated stubs come out
//    alphabetical even though the iterator delivered declaration order.
//  - MethodAddPos redirect as a normal function-entry hook, as on x86.
//
//  The ReturnAddress window MUST end at Complete's own epilogue, not at a
//  fixed size: the symbol range behind the epilogue also contains exception
//  funclets and the recursive class enumerator used by GetClasses (at
//  Complete+~0xf80 in D13.1), which creates a Symbols::TTableIterator over
//  CLASS symbol tables. Substituting our method-comparing iterator there would
//  read TClassSymbol+0x118 as a TMethodSignature - garbage. The epilogue is
//  located by matching the frame size taken from the prologue.
// ---------------------------------------------------------------------------
const
  sDsgnTableIteratorCtor      = '_ZN7Symbols14TTableIteratorC3EPNS_12TSymbolTableE';
  sDsgnTableIteratorGetSymbol = '_ZN7Symbols14TTableIterator9GetSymbolEi';

type
  TIteratorCtorProc = function(AClass: Pointer; AllocFlag: NativeInt; ATable: Pointer): Pointer;
  TIteratorGetSymProc = function(Instance: Pointer; Index: Integer): Pointer;

var
  AlphaCtorIatSlot: PPointer;    // delphicoreide370 IAT slot for the ctor
  AlphaGetSymIatSlot: PPointer;  // delphicoreide370 IAT slot for GetSymbol
  AlphaOrgCtor: Pointer;         // real designide ctor
  AlphaOrgGetSym: Pointer;       // real designide GetSymbol
  AlphaCompleteLo, AlphaCompleteHi: NativeUInt;
  AlphaMethodAddPosHooked: Boolean;
  // Runtime self-validation. Install strengthens the structural checks; the
  // gate validates the LIVE object layout on the first real completion before
  // trusting our reorder. AlphaProbation = layout not yet confirmed on this
  // IDE; AlphaDisabled = confirmed wrong (our offsets don't match) -> every
  // gate falls through to the untouched designide iterator (feature off, no
  // corruption). This is what lets the hook be attempted on ANY x64 IDE and
  // self-disable on a version it wasn't reverse-engineered for.
  AlphaProbation: Boolean;
  AlphaDisabled: Boolean;
  AlphaSetSortedCallP: PByte;                  // E8 call site of TSortedThingList.SetSorted(True) in Complete
  AlphaSetSortedOrgBytes: array[0..4] of Byte; // original call bytes for uninstall
  AlphaSetSortedPatched: Boolean;

{.$DEFINE ALPHASORTDIAG} // diagnostic log to %APPDATA%\DDevExtensions\AlphaSort.log (dot = off)

procedure AlphaLog(const S: string);
{$IFDEF ALPHASORTDIAG}
var
  F: TextFile;
  FileName: string;
begin
  try
    FileName := GetEnvironmentVariable('APPDATA') + '\DDevExtensions\AlphaSort.log';
    AssignFile(F, FileName);
    if FileExists(FileName) then Append(F) else Rewrite(F);
    try
      WriteLn(F, S);
    finally
      CloseFile(F);
    end;
  except
    // status logging must never break the IDE
  end;
end;
{$ELSE}
begin
  // diagnostics disabled - re-enable ALPHASORTDIAG above when reverse
  // engineering a new IDE version's symbol layout
end;
{$ENDIF}

function AlphaReadable(P: Pointer; Len: NativeUInt): Boolean;
var
  mbi: TMemoryBasicInformation;
begin
  Result := False;
  if (P = nil) or (NativeUInt(P) < $10000) then Exit;
  if VirtualQuery(P, mbi, SizeOf(mbi)) = 0 then Exit;
  if mbi.State <> MEM_COMMIT then Exit;
  if (mbi.Protect and (PAGE_NOACCESS or PAGE_GUARD)) <> 0 then Exit;
  Result := NativeUInt(P) + Len <= NativeUInt(mbi.BaseAddress) + NativeUInt(mbi.RegionSize);
end;

// Committed AND executable - used at install time to sanity-check that the
// SetSorted call site's E8 target is real code (a coincidental byte match's
// rel32 would point at garbage).
function AlphaExecReadable(P: Pointer): Boolean;
const
  EXEC = PAGE_EXECUTE or PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY;
var
  mbi: TMemoryBasicInformation;
begin
  Result := False;
  if (P = nil) or (NativeUInt(P) < $10000) then Exit;
  if VirtualQuery(P, mbi, SizeOf(mbi)) = 0 then Exit;
  if mbi.State <> MEM_COMMIT then Exit;
  Result := (mbi.Protect and EXEC) <> 0;
end;

// Runtime layout self-validation. Wrong object offsets make the symbol pointers
// our iterator collected (via the Next/FSymbolList chain) or their fields come
// out as garbage. We verify that BEFORE the completer generates from a reordered
// list. Encoding-agnostic: check that a real object's pointers (VMT, signature)
// land in committed memory and HeaderPos is bounded - not identifier text, so a
// Unicode method name never trips it.
function AlphaValidateIterator(it: TTableIterator): Boolean;
var
  i, n: Integer;
  sym, sig: Pointer;
  hp: Integer;
begin
  Result := False;
  try
    if (it.Count < 0) or (it.Count > 4096) then Exit;
    n := it.Count;
    if n > 8 then n := 8;
    for i := 0 to n - 1 do
    begin
      sym := it.GetSymbol(i);
      if not AlphaReadable(sym, $120) then Exit;             // symbol incl. FMethodSignature slot
      if not AlphaReadable(PPointer(sym)^, SizeOf(Pointer)) then Exit; // VMT into a module
      sig := PPointer(PByte(sym) + $118)^;                   // TMethodSymbol.FMethodSignature
      if sig <> nil then
      begin
        if not AlphaReadable(sig, $20) then Exit;
        if not AlphaReadable(PPointer(sig)^, SizeOf(Pointer)) then Exit; // signature VMT
        hp := PInteger(PByte(sig) + $1C)^;                   // HeaderPos
        if (hp < 0) or (hp > $0FFFFFFF) then Exit;
      end;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

// A ctor call from inside Complete gets our reordering iterator; every other
// caller in the IDE - and every call once the feature self-disabled - gets the
// untouched designide iterator.
function AlphaCtorGate(AClass: Pointer; AllocFlag: NativeInt; ATable: Pointer): Pointer;
var
  ra: NativeUInt;
  rawCount: Integer;
  it: TTableIterator;
begin
  ra := NativeUInt(ReturnAddress);
  if AlphaDisabled or (ra < AlphaCompleteLo) or (ra >= AlphaCompleteHi) then
  begin
    Result := TIteratorCtorProc(AlphaOrgCtor)(AClass, AllocFlag, ATable);
    Exit;
  end;

  // Guard the raw FCount before building our iterator: LoadSymbols does
  // SetLength(FSymbols, Count), so a garbage Count from a wrong offset would
  // attempt a huge allocation. Bail to the real ctor if it is implausible.
  if (ATable = nil) or not AlphaReadable(ATable, $10) then
  begin
    Result := TIteratorCtorProc(AlphaOrgCtor)(AClass, AllocFlag, ATable);
    Exit;
  end;
  rawCount := PInteger(PByte(ATable) + $08)^;            // TSymbolTable.FCount
  if (rawCount < 0) or (rawCount > 4096) then
  begin
    AlphaLog(Format('verify: raw table count %d implausible -> disabling', [rawCount]));
    AlphaDisabled := True;
    Result := TIteratorCtorProc(AlphaOrgCtor)(AClass, AllocFlag, ATable);
    Exit;
  end;

  it := MethodSymbolTableIteratorFactory(TClass(AClass), Integer(AllocFlag), TSymbolTable(ATable));

  if AlphaProbation then
  begin
    if AlphaValidateIterator(it) then
    begin
      AlphaProbation := False;
      AlphaLog(Format('verify: layout OK (count=%d) - feature active', [it.Count]));
    end
    else
    begin
      // Our offsets do not match this IDE build - do NOT hand the completer a
      // reordered (possibly garbage) list. Discard our iterator, run this
      // completion with the real one, and disable all further gating.
      AlphaLog('verify: layout MISMATCH - disabling (feature off on this IDE)');
      AlphaDisabled := True;
      it.Free;
      Result := TIteratorCtorProc(AlphaOrgCtor)(AClass, AllocFlag, ATable);
      Exit;
    end;
  end;

  Result := it;
end;

function AlphaGetSymGate(Instance: Pointer; Index: Integer): Pointer;
var
  ra: NativeUInt;
begin
  ra := NativeUInt(ReturnAddress);
  if AlphaDisabled or (ra < AlphaCompleteLo) or (ra >= AlphaCompleteHi) then
    Result := TIteratorGetSymProc(AlphaOrgGetSym)(Instance, Index)
  else
    Result := TTableIterator(Instance).GetSymbol(Index);
end;

// Complete's symbol range also covers exception funclets and GetClasses'
// recursive class enumerator; the function itself ends at the epilogue that
// releases the frame allocated in the prologue:
//   prologue: push rbp/rdi/rsi/rbx; subq $FrameSize, %rsp
//   epilogue: leaq FrameSize(%rbp), %rsp; pop rbx/rsi/rdi/rbp; ret
// The imm32 frame size makes the 12-byte epilogue unique within the range
// (funclets and the enumerator use smaller disp8 frames).
function AlphaFindCompleteEnd(CompleteP: PByte): PByte;
var
  FrameSize: Integer;
  p, limit: PByte;
begin
  Result := nil;
  if (CompleteP[0] <> $55) or (CompleteP[1] <> $57) or (CompleteP[2] <> $56) or
     (CompleteP[3] <> $53) or (CompleteP[4] <> $48) or (CompleteP[5] <> $81) or
     (CompleteP[6] <> $EC) then
    Exit; // unexpected prologue - abort the install
  FrameSize := PInteger(CompleteP + 7)^;
  p := CompleteP + 11;
  limit := CompleteP + $1800;
  while NativeUInt(p) < NativeUInt(limit) do
  begin
    if (p[0] = $48) and (p[1] = $8D) and (p[2] = $A5) and (PInteger(p + 3)^ = FrameSize) and
       (p[7] = $5B) and (p[8] = $5E) and (p[9] = $5F) and (p[10] = $5D) and (p[11] = $C3) then
    begin
      Result := p + 12;
      Exit;
    end;
    Inc(p);
  end;
end;

// The alphabetical re-sort of the collected "to add" list, right before the
// generation loop iterates it:
//   mov rcx,[rbp+D]    48 8B 8D dd dd dd dd   D = the thing-list local
//   mov dl,1           B2 01
//   call SetSorted     E8 rr rr rr rr         <- result points here
//   xor eax,eax        33 C0
//   mov rcx,[rbp+D]    48 8B 8D dd dd dd dd   (same D)
//   mov ebx,[rcx+10]   8B 59 10               (list count -> generation loop)
// The match must be UNIQUE in Complete: a coincidental hit elsewhere makes
// Count <> 1, and the caller then refuses to patch rather than NOP a wrong call.
function AlphaFindSetSortedCall(CompleteP, LimitP: PByte; out Count: Integer): PByte;
var
  p: PByte;
begin
  Result := nil;
  Count := 0;
  p := CompleteP;
  while NativeUInt(p) + 26 <= NativeUInt(LimitP) do
  begin
    if (p[0] = $48) and (p[1] = $8B) and (p[2] = $8D) and
       (p[7] = $B2) and (p[8] = $01) and (p[9] = $E8) and
       (p[14] = $33) and (p[15] = $C0) and
       (p[16] = $48) and (p[17] = $8B) and (p[18] = $8D) and
       (p[23] = $8B) and (p[24] = $59) and (p[25] = $10) and
       (PInteger(p + 3)^ = PInteger(p + 19)^) then
    begin
      if Count = 0 then Result := p + 9;
      Inc(Count);
    end;
    Inc(p);
  end;
  if Count <> 1 then Result := nil;
end;

// Locate the delphicoreide IAT slot that Complete uses to reach a designide
// export, by scanning Complete for the E8 call whose import stub reads a slot
// currently holding RealFn.
function AlphaFindIatSlot(CompleteP, LimitP: PByte; RealFn: Pointer): PPointer;
var
  p, limit, t: PByte;
  slot: PPointer;
begin
  Result := nil;
  p := CompleteP;
  limit := LimitP;
  while NativeUInt(p) < NativeUInt(limit) do
  begin
    if p^ = $E8 then
    begin
      try
        t := PByte(GetCallTargetAddress(p));       // E8 direct target = import stub
        if (t <> nil) and (t[0] = $FF) and (t[1] = $25) then
        begin
          slot := PPointer(t + 6 + PInteger(t + 2)^); // FF25 -> *[rip+disp32] = IAT slot
          if AlphaReadable(slot, SizeOf(Pointer)) and (slot^ = RealFn) then
          begin
            Result := slot;
            Exit;
          end;
        end;
      except
        // mis-aligned E8 operand - ignore
      end;
    end;
    Inc(p);
  end;
end;

function AlphaPatchSlot(Slot: PPointer; NewValue: Pointer): Boolean;
var
  OldProt: DWORD;
begin
  Result := False;
  if (Slot = nil) or not AlphaReadable(Slot, SizeOf(Pointer)) then Exit;
  if VirtualProtect(Slot, SizeOf(Pointer), PAGE_READWRITE, OldProt) then
  begin
    Slot^ := NewValue;
    VirtualProtect(Slot, SizeOf(Pointer), OldProt, OldProt);
    Result := True;
  end;
end;

procedure InstallAlphaSortX64(Value: Boolean);
const
  NopCall: array[0..4] of Byte = ($90, $90, $90, $90, $90);
var
  hCore, hDsgn: THandle;
  CompleteP, CompleteEndP: PByte;
  ssCount, i: Integer;
  readback: array[0..4] of Byte;
begin
  if Value then
  begin
    if AlphaCtorIatSlot <> nil then Exit;   // already installed

    hCore := GetModuleHandle(delphicoreide_bpl);
    hDsgn := GetModuleHandle(designide_bpl);
    if (hCore = 0) or (hDsgn = 0) then
    begin
      AlphaLog(Format('install: BPL not loaded (core=%d dsgn=%d)', [hCore, hDsgn]));
      Exit;
    end;

    AlphaOrgCtor := GetProcAddress(hDsgn, sDsgnTableIteratorCtor);
    AlphaOrgGetSym := GetProcAddress(hDsgn, sDsgnTableIteratorGetSymbol);
    if (AlphaOrgCtor = nil) or (AlphaOrgGetSym = nil) then
    begin
      AlphaLog('install: designide ctor/GetSymbol symbol not found');
      Exit;
    end;

    CompleteP := GetActualAddr(@TPascalClassCompleter_Complete);
    if CompleteP = nil then
    begin
      AlphaLog('install: Complete not resolved');
      Exit;
    end;

    CompleteEndP := AlphaFindCompleteEnd(CompleteP);
    if CompleteEndP = nil then
    begin
      AlphaLog('install: Complete epilogue not found');
      Exit;
    end;

    // All-or-nothing: without the SetSorted no-op the completer re-sorts the
    // "to add" list and the output stays alphabetical, so don't install at all.
    // Require a UNIQUE match (a coincidental hit would be ambiguous -> unsafe).
    AlphaSetSortedCallP := AlphaFindSetSortedCall(CompleteP, CompleteEndP, ssCount);
    if AlphaSetSortedCallP = nil then
    begin
      AlphaLog(Format('install: SetSorted call site not uniquely found (matches=%d)', [ssCount]));
      Exit;
    end;
    // The E8 at the site must point at real code; a coincidental byte match's
    // rel32 would not.
    if not AlphaExecReadable(GetCallTargetAddress(AlphaSetSortedCallP)) then
    begin
      AlphaLog('install: SetSorted call target not executable - aborting');
      AlphaSetSortedCallP := nil;
      Exit;
    end;

    AlphaCompleteLo := NativeUInt(CompleteP);
    AlphaCompleteHi := NativeUInt(CompleteEndP);
    AlphaProbation := True;    // layout confirmed on the first real completion
    AlphaDisabled := False;

    AlphaCtorIatSlot := AlphaFindIatSlot(CompleteP, CompleteEndP, AlphaOrgCtor);
    AlphaGetSymIatSlot := AlphaFindIatSlot(CompleteP, CompleteEndP, AlphaOrgGetSym);
    if (AlphaCtorIatSlot = nil) or (AlphaGetSymIatSlot = nil) then
    begin
      AlphaLog(Format('install: IAT slot not found (ctor=%p getsym=%p)',
        [AlphaCtorIatSlot, AlphaGetSymIatSlot]));
      AlphaCtorIatSlot := nil;
      AlphaGetSymIatSlot := nil;
      AlphaSetSortedCallP := nil;
      Exit;
    end;

    if not AlphaPatchSlot(AlphaCtorIatSlot, @AlphaCtorGate) then
    begin
      AlphaLog('install: ctor slot patch failed');
      AlphaCtorIatSlot := nil;
      AlphaGetSymIatSlot := nil;
      AlphaSetSortedCallP := nil;
      Exit;
    end;
    if not AlphaPatchSlot(AlphaGetSymIatSlot, @AlphaGetSymGate) then
    begin
      AlphaPatchSlot(AlphaCtorIatSlot, AlphaOrgCtor); // roll back ctor patch
      AlphaLog('install: getsym slot patch failed');
      AlphaCtorIatSlot := nil;
      AlphaGetSymIatSlot := nil;
      AlphaSetSortedCallP := nil;
      Exit;
    end;

    // No-op the alphabetical re-sort (x86 redirects this call to an empty
    // procedure; NOPing the E8 site has the same effect and needs no rel32-
    // reachable target). The mov rcx/mov dl setup before it stays - harmless.
    Move(AlphaSetSortedCallP^, AlphaSetSortedOrgBytes, SizeOf(AlphaSetSortedOrgBytes));
    if not InjectCode(AlphaSetSortedCallP, @NopCall[0], SizeOf(NopCall)) then
    begin
      AlphaPatchSlot(AlphaCtorIatSlot, AlphaOrgCtor);
      AlphaPatchSlot(AlphaGetSymIatSlot, AlphaOrgGetSym);
      AlphaLog('install: SetSorted nop patch failed');
      AlphaCtorIatSlot := nil;
      AlphaGetSymIatSlot := nil;
      AlphaSetSortedCallP := nil;
      Exit;
    end;
    AlphaSetSortedPatched := True;
    FlushInstructionCache(GetCurrentProcess, AlphaSetSortedCallP, SizeOf(NopCall));

    // Readback: confirm the NOP actually landed (defends against a silently
    // failed write to protected code). Roll everything back if it did not.
    Move(AlphaSetSortedCallP^, readback, SizeOf(readback));
    for i := 0 to High(readback) do
      if readback[i] <> $90 then
      begin
        InjectCode(AlphaSetSortedCallP, @AlphaSetSortedOrgBytes[0], SizeOf(AlphaSetSortedOrgBytes));
        AlphaPatchSlot(AlphaCtorIatSlot, AlphaOrgCtor);
        AlphaPatchSlot(AlphaGetSymIatSlot, AlphaOrgGetSym);
        AlphaLog('install: SetSorted NOP readback mismatch - rolled back');
        AlphaSetSortedPatched := False;
        AlphaCtorIatSlot := nil;
        AlphaGetSymIatSlot := nil;
        AlphaSetSortedCallP := nil;
        Exit;
      end;

    // Insertion-position redirect (same as x86): make MethodAddPos behave as if
    // the new method name were empty. RedirectOrgCall handles the x64 trampoline.
    if not AlphaMethodAddPosHooked then
    begin
      if Assigned(OrgTClassSymbol_MethodAddPos) then
        RedirectOrg(@TClassSymbol_MethodAddPos, @TClassSymbol_MethodAddPos_AlphSort)
      else
        @OrgTClassSymbol_MethodAddPos := RedirectOrgCall(@TClassSymbol_MethodAddPos, @TClassSymbol_MethodAddPos_AlphSort);
      AlphaMethodAddPosHooked := True;
    end;

    AlphaLog(Format('install: active (ctorSlot=%p getsymSlot=%p setsorted=%p Complete=%p..%p)',
      [AlphaCtorIatSlot, AlphaGetSymIatSlot, AlphaSetSortedCallP, CompleteP, CompleteEndP]));
  end
  else
  begin
    if AlphaCtorIatSlot <> nil then
    begin
      AlphaPatchSlot(AlphaCtorIatSlot, AlphaOrgCtor);
      AlphaCtorIatSlot := nil;
    end;
    if AlphaGetSymIatSlot <> nil then
    begin
      AlphaPatchSlot(AlphaGetSymIatSlot, AlphaOrgGetSym);
      AlphaGetSymIatSlot := nil;
    end;
    if AlphaSetSortedPatched then
    begin
      InjectCode(AlphaSetSortedCallP, @AlphaSetSortedOrgBytes[0], SizeOf(AlphaSetSortedOrgBytes));
      FlushInstructionCache(GetCurrentProcess, AlphaSetSortedCallP, SizeOf(AlphaSetSortedOrgBytes));
      AlphaSetSortedPatched := False;
    end;
    AlphaSetSortedCallP := nil;
    if AlphaMethodAddPosHooked then
    begin
      RestoreOrgCall(@TClassSymbol_MethodAddPos, @OrgTClassSymbol_MethodAddPos);
      AlphaMethodAddPosHooked := False;
    end;
    AlphaLog('uninstall: restored');
  end;
end;
{$ENDIF ALPHASORT_X64_WIP}
{$ENDIF CPUX64}

procedure InstallDisableAlphaSortClassCompletion(Value: Boolean);
{$IFNDEF CPUX64}
const
  CompleteSetSortedBytes: array[0..18] of SmallInt = (
    $B2, $01,             // mov dl,$01                                    //  0
    $8B, $45, $F0,        // mov eax,[ebp-$10]                             //  2  == SortedThingList (used in CompleteMethodSymbolTableIteratorBytes)
    $E8, -1, -1, -1, -1,  // call TSortedThingList.SetSorted  ; $21ce165c  //  5
    $8B, $45, $F0,        // mov eax,[ebp-$10]                             // 10
    {$IF CompilerVersion >= 25.0} // XE4+
    $8B, $78, $08,        // mov edi,[eax+$08]                             // 13
    $4F,                  // dec edi                                       // 16
    $85, $FF              // test edi,edi                                  // 17
    {$ELSE}
    $8B, $70, $08,        // mov esi,[eax+$08]                             // 13
    $4E,                  // dec esi                                       // 16
    $85, $F6              // test esi,esi                                  // 17
    {$IFEND}
  );
  CallOffsetSetSorted = 5;

  CompleteMethodSymbolTableIteratorBytes: array[0..71] of SmallInt = (
    $8B, $45, $F8,                      // mov eax,[ebp-$08]                           //  0
    $8B, $88, -1, -1, $00, $00,         // mov ecx,[eax+$0000012c]                     //  3
    $B2, $01,                           // mov dl,$01                                  //  9
    $A1, -1, -1, -1, -1,                // mov eax,[$21df1e68]                         // 11
    $E8, -1, -1, -1, -1,                // call TTableIterator.Create  ; $21c646c4     // 16 // => call MethodSymbolTableIteratorFactory
    {$IF CompilerVersion = 21.0} // 2010 what did they do?
    $89, $45, $C0,                      // mov [ebp-$40],eax                           // 21
    {$ELSE}
    $89, $45, $C4,                      // mov [ebp-$3c],eax                           // 21
    {$IFEND}
    $33, $C0,                           // xor eax,eax                                 // 24
    $55,                                // push ebp                                    // 26
    $68, -1, -1, -1, -1,                // push $21ce114d                              // 27
    $64, $FF, $30,                      // push dword ptr fs:[eax]                     // 32
    $64, $89, $20,                      // mov fs:[eax],esp                            // 35
    {$IF CompilerVersion = 21.0} // 2010 what did they do?
    $8B, $45, $C0,                      // mov eax,[ebp-$40]                           // 38
    {$ELSE}
    $8B, $45, $C4,                      // mov eax,[ebp-$3c]                           // 38
    {$IFEND}
    $8B, -1, $10,                       // mov edi,[eax+$10]                           // 41
    -1,                                 // dec edi                                     // 44
    $85, -1,                            // test edi,edi                                // 45
    $0F, $8C, -1, -1, $00, $00,         // jl $21ce1137                                // 47
    -1,                                 // inc edi                                     // 53
    {$IF CompilerVersion = 21.0} // 2010 what did they do?
    $C7, $45, $CC, $00, $00, $00, $00,  // mov [ebp-$34],$00000000                     // 54
    $8B, $55, $CC,                      // mov edx,[ebp-$30]                           // 61
    $8B, $45, $C0,                      // mov eax,[ebp-$40]                           // 64
    {$ELSE}
    $C7, $45, $D0, $00, $00, $00, $00,  // mov [ebp-$30],$00000000                     // 54
    $8B, $55, $D0,                      // mov edx,[ebp-$34]                           // 61
    $8B, $45, $C4,                      // mov eax,[ebp-$3c]                           // 64
    {$IFEND}
    $E8, -1, -1, -1, -1                 // call TTableIterator.GetSymbol  ; $21c646cc  // 67  => replace with out GetSymbol method
  );
  CallOffsetTabCtor = 16;
  CallOffsetGetSymbol = 67;

begin
  if Value then
  begin
    if CallAddrTSortedThingList_SetSortedP = nil then
    begin
      CompleteMethodSymbolTableIteratorP := FindMethodPtr(GetActualAddr(@TPascalClassCompleter_Complete), CompleteMethodSymbolTableIteratorBytes, $10000);
      CallAddrTSortedThingList_SetSortedP := FindMethodPtr(CompleteMethodSymbolTableIteratorP, CompleteSetSortedBytes, $1000);

      // Code-Search: Breakpoint in TClassSymbol_MethodAddPos_AlphSort, start, add method to class decl., press Ctrl+Shift+C, debug through function returns until you are in method "Complete"
      if (CallAddrTSortedThingList_SetSortedP = nil) and (DebugHook <> 0) then
        MessageBox(0, 'InstallDisableAlphaSortClassCompletion byte sequences not found', 'DDevExtensions', MB_OK or MB_ICONWARNING);

      if (CompleteMethodSymbolTableIteratorP <> nil) and (CallAddrTSortedThingList_SetSortedP <> nil) then
      begin
        OrgTTableIterator_Ctor := GetCallTargetAddress(@CompleteMethodSymbolTableIteratorP[CallOffsetTabCtor]);
        OrgTTableIterator_GetSymbol := GetCallTargetAddress(@CompleteMethodSymbolTableIteratorP[CallOffsetGetSymbol]);
        OrgTSortedThingList_SetSorted := GetCallTargetAddress(@CallAddrTSortedThingList_SetSortedP[CallOffsetSetSorted]);
      end
      else
      begin
        // No "disabled sorting" of the generated methods, but the insert position patch can still work
        CompleteMethodSymbolTableIteratorP := nil;
        CallAddrTSortedThingList_SetSortedP := nil;
      end;
    end;

    if (CompleteMethodSymbolTableIteratorP <> nil) and (CallAddrTSortedThingList_SetSortedP <> nil) then
    begin
      ReplaceRelCallOffset(@CompleteMethodSymbolTableIteratorP[CallOffsetTabCtor], @MethodSymbolTableIteratorFactory);
      ReplaceRelCallOffset(@CompleteMethodSymbolTableIteratorP[CallOffsetGetSymbol], @TTableIterator.GetSymbol);
      ReplaceRelCallOffset(@CallAddrTSortedThingList_SetSortedP[CallOffsetSetSorted], @TSortedThingList_SetSorted);
    end;

    if Assigned(OrgTClassSymbol_MethodAddPos) then
      RedirectOrg(@TClassSymbol_MethodAddPos, @TClassSymbol_MethodAddPos_AlphSort)
    else
      @OrgTClassSymbol_MethodAddPos := RedirectOrgCall(@TClassSymbol_MethodAddPos, @TClassSymbol_MethodAddPos_AlphSort);
  end
  else
  begin
    RestoreOrgCall(@TClassSymbol_MethodAddPos, @OrgTClassSymbol_MethodAddPos);
    if (CompleteMethodSymbolTableIteratorP <> nil) and (OrgTTableIterator_Ctor <> nil) then
      ReplaceRelCallOffset(@CompleteMethodSymbolTableIteratorP[CallOffsetTabCtor], OrgTTableIterator_Ctor);
    if (CompleteMethodSymbolTableIteratorP <> nil) and (OrgTTableIterator_GetSymbol <> nil) then
      ReplaceRelCallOffset(@CompleteMethodSymbolTableIteratorP[CallOffsetGetSymbol], OrgTTableIterator_GetSymbol);
    if (CallAddrTSortedThingList_SetSortedP <> nil) and (OrgTSortedThingList_SetSorted <> nil) then
      ReplaceRelCallOffset(@CallAddrTSortedThingList_SetSortedP[CallOffsetSetSorted], OrgTSortedThingList_SetSorted);
  end;
end;
{$ELSE}
begin
  {$IFDEF ALPHASORT_X64_WIP}
  // Win64 (Delphi 13): IAT-gated reorder + SetSorted no-op + MethodAddPos redirect
  // (see CPUX64 block above).
  InstallAlphaSortX64(Value);
  {$ELSE}
  // Win64 fallback: feature is a no-op when ALPHASORT_X64_WIP is undefined (the
  // define is set at the top of this unit). History: first wiring 65463f8 failed
  // because the internal TSortedThingList.SetSorted(True) call in Complete was
  // not yet located/no-opped (output stayed alphabetical) and the ReturnAddress
  // window overshot Complete's epilogue into GetClasses' class enumerator.
  {$ENDIF}
end;
{$ENDIF ~CPUX64}

{$IFEND}

end.
