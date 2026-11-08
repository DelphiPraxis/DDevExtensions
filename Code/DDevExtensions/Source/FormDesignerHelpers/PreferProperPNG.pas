{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* Prefer the proper TPNGGraphic over AlphaControls' acPNG (order arbiter)    *}
{*                                                                            *}
{******************************************************************************}

unit PreferProperPNG;

{$I ..\DelphiExtension.inc}

{
  AlphaControls' acPNG unit and the proper PNG implementation both register a
  graphic class NAMED 'TPNGGraphic' in the VCL's global TFileFormatsList. A
  DFM stores only that class-name string; TPicture.ReadData resolves it via
  FileFormats.FindClassName, which iterates "for I := Count-1 downto 0" - so
  the LAST registered class wins (verified in D7 and D13 Graphics.pas alike).
  Package load order is not guaranteed, so sometimes acPNG wins and pictures
  stay acPNG's fake PNG (a BMP stored under the PNG class name, not portable).

  acPNG additionally registers its TPNGGraphic with extension 'png' (seen in
  the D7 dump), so it also competes with the proper TPngImage for the
  FindExt('png') lookup - not just for the class-name lookup.

  This feature arbitrates the registration ORDER instead of fighting the
  registration itself: it locates the global list via the FileFormatsListHack
  disassembler hack, identifies ALL proper PNG entries - those from the
  pngimage unit (pre-2009: the user's pngimage package; XE2+: also the native
  Vcl.Imaging.pngimage) or DDev's own FixAlphaControlsPNG class (D2009+, when
  that fix is compiled in) - and moves them to the END of the list, keeping
  their relative order, so they win both last-wins lookups (TPNGGraphic wins
  FindClassName, TPngImage stays behind it and wins FindExt('png')).
  Non-destructive (acPNG stays registered, AlphaControls' runtime behavior is
  untouched) and idempotent, so it can run any number of times.

  It runs when the feature is activated and again on every
  ofnPackageInstalled/ofnPackageUninstalled notification, which catches an
  AlphaControls package that is (re)loaded after DDevExtensions.

  Diagnostics: whenever a run sees a list state it has not logged yet, it
  appends a dump of the whole file-format list (index, class, unit, extension)
  plus the action taken to %APPDATA%\DDevExtensions\PNGArbiter.log - the dump
  of the pre-move state is written BEFORE the list is mutated.
}

interface

procedure SetPreferProperPNGActive(Active: Boolean);

implementation

uses
  Windows, SysUtils, Classes, TypInfo, Graphics, Forms, ToolsAPI,
  FileFormatsListHack
  {$IFDEF INCLUDE_ACPNGFIX}
  , FixAlphaControlsPNG
  {$ENDIF};

const
  SPNGGraphicClassName = 'TPNGGraphic';
  // The proper PNG unit. Pre-2009 this is the user's pngimage package (kept in
  // sync with the retail pngimage and never renamed); 2009+ a third-party
  // package built from pngimage would match, too.
  SProperPngUnitName = 'pngimage';

type
  TPngArbiterNotifier = class(TNotifierObject, IOTAIDENotifier)
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification;
      const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
    procedure AfterCompile(Succeeded: Boolean);
  end;

var
  GNotifierIndex: Integer = -1;
  GLastLoggedState: string; // last logged list signature - suppresses log spam

{ Classic RTTI (works from D7 on): the unit a class was declared in. }
function ClassUnitName(AClass: TClass): string;
begin
  Result := '';
  if (AClass <> nil) and (AClass.ClassInfo <> nil) then
    Result := string(GetTypeData(AClass.ClassInfo)^.UnitName);
end;

{ Last dot-segment of a unit name: the native pngimage lives in
  'Vcl.Imaging.pngimage' from XE2 on, plain 'pngimage' before. }
function UnitBaseName(const AUnitName: string): string;
var
  i: Integer;
begin
  Result := AUnitName;
  for i := Length(Result) downto 1 do
    if Result[i] = '.' then
    begin
      Result := Copy(Result, i + 1, MaxInt);
      Break;
    end;
end;

{ Is this one of the PNG classes that should win? The arbiter does not need to
  know acPNG - it only promotes "ours"; everything else simply loses. }
function IsProperPNGClass(AClass: TGraphicClass): Boolean;
begin
  Result := SameText(UnitBaseName(ClassUnitName(AClass)), SProperPngUnitName);
  {$IFDEF INCLUDE_ACPNGFIX}
  Result := Result or (AClass = FixAlphaControlsPNG.TPNGGraphic);
  {$ENDIF}
end;

{.$DEFINE PNGDIAG} // diagnostic dumps to %APPDATA%\DDevExtensions\PNGArbiter.log (dot = off)

procedure AppendLog(const Text: string);
{$IFDEF PNGDIAG}
var
  Dir, Fn: string;
  F: TextFile;
begin
  try
    Dir := GetEnvironmentVariable('APPDATA') + '\DDevExtensions';
    ForceDirectories(Dir);
    Fn := Dir + '\PNGArbiter.log';
    AssignFile(F, Fn);
    if FileExists(Fn) then
      Append(F)
    else
      Rewrite(F);
    try
      Write(F, Text);
    finally
      CloseFile(F);
    end;
  except
    // diagnostics must never break the IDE
  end;
end;
{$ELSE}
begin
  // diagnostics disabled - re-enable PNGDIAG above when investigating the
  // graphic-format registration on a new IDE / package constellation
end;
{$ENDIF}

{ Signature of the current list ordering; also used to decide whether the
  state is worth logging again. }
function ListSignature(List: TFileFormatsListHack): string;
var
  i: Integer;
  GC: TGraphicClass;
begin
  Result := '';
  for i := 0 to List.Count - 1 do
  begin
    GC := List[i]^.GraphicClass;
    if GC = nil then
      Result := Result + IntToStr(i) + ':<nil>|'
    else
      Result := Result + IntToStr(i) + ':' + GC.ClassName + ':' +
        ClassUnitName(GC) + '|';
  end;
end;

procedure Arbitrate(const Trigger: string);
var
  List: TFileFormatsListHack;
  Dump: TStringList;
  State, Action, MovedNames, AfterNames: string;
  i, MinProper, MaxForeign, MovedCount: Integer;
  GC: TGraphicClass;
begin
  try
    if not Assigned(GetFileFormats) then
    begin
      if GLastLoggedState <> '<no-hack>' then
      begin
        GLastLoggedState := '<no-hack>';
        AppendLog('[' + DateTimeToStr(Now) + '] ' + Trigger + ': ' +
          'GetFileFormats hack failed (unexpected TPicture.RegisterFileFormat' +
          ' code layout) - PNG arbiter inactive' + sLineBreak);
      end;
      Exit;
    end;

    List := GetFileFormats();
    if List = nil then
      Exit;

    // find the FIRST proper PNG entry and the LAST foreign entry that
    // competes with us - by class name (TPNGGraphic) or extension ('png',
    // acPNG registers with ext='png'). If every proper entry already sits
    // behind every competing foreign one, there is nothing to do.
    MinProper := -1;
    MaxForeign := -1;
    MovedNames := ''; // pre-move indexes of the proper entries, for the log
    for i := 0 to List.Count - 1 do
    begin
      GC := List[i]^.GraphicClass;
      if GC = nil then
        Continue;
      if IsProperPNGClass(GC) then
      begin
        if MinProper < 0 then
          MinProper := i;
        if MovedNames <> '' then
          MovedNames := MovedNames + ', ';
        MovedNames := MovedNames + '[' + IntToStr(i) + '] ' + GC.ClassName;
      end
      else if (GC.ClassName = SPNGGraphicClassName) or
              SameText(List[i]^.Extension, 'png') then
        MaxForeign := i;
    end;

    // log the pre-move state BEFORE mutating (once per distinct state)
    State := ListSignature(List);
    if State <> GLastLoggedState then
    begin
      Dump := TStringList.Create;
      try
        Dump.Add('================ PNG arbiter [' + DateTimeToStr(Now) +
          '] trigger: ' + Trigger + ' ================');
        Dump.Add('file-format list before (last entry wins, Count=' +
          IntToStr(List.Count) + '):');
        for i := 0 to List.Count - 1 do
        begin
          GC := List[i]^.GraphicClass;
          if GC = nil then
            Dump.Add(Format('  [%2d] <nil>', [i]))
          else
            Dump.Add(Format('  [%2d] %-16s unit=%-24s ext=''%s''',
              [i, GC.ClassName, ClassUnitName(GC), List[i]^.Extension]));
        end;
        AppendLog(Dump.Text);
      finally
        Dump.Free;
      end;
    end;

    if (MinProper >= 0) and (MaxForeign > MinProper) then
    begin
      // move ALL proper PNG entries to the end, keeping their relative order:
      // TPngImage ends up last (wins FindExt('png')), the TPNGGraphic
      // converter right before it (wins FindClassName('TPNGGraphic'))
      MovedCount := 0;
      i := 0;
      while i < List.Count - MovedCount do
      begin
        GC := List[i]^.GraphicClass;
        if (GC <> nil) and IsProperPNGClass(GC) then
        begin
          List.Move(i, List.Count - 1);
          Inc(MovedCount);
        end
        else
          Inc(i);
      end;
      AfterNames := '';
      for i := 0 to List.Count - 1 do
      begin
        GC := List[i]^.GraphicClass;
        if (GC <> nil) and IsProperPNGClass(GC) then
        begin
          if AfterNames <> '' then
            AfterNames := AfterNames + ', ';
          AfterNames := AfterNames + '[' + IntToStr(i) + '] ' + GC.ClassName;
        end;
      end;
      Action := Format('moved proper PNG entries (%s) to the end - now at %s, ' +
        'winning over the foreign entry that was at [%d]',
        [MovedNames, AfterNames, MaxForeign]);
    end
    else if MinProper < 0 then
    begin
      if MaxForeign >= 0 then
        Action := 'foreign TPNGGraphic/''png'' entry at [' +
          IntToStr(MaxForeign) + '] but no proper PNG registered - nothing to promote'
      else
        Action := 'no PNG entries - nothing to do';
    end
    else
      Action := 'proper PNG entries (first at [' + IntToStr(MinProper) +
        ']) already win - no change';

    if State <> GLastLoggedState then
      AppendLog('action: ' + Action + sLineBreak + sLineBreak);

    // remember the RESULTING state so an unchanged follow-up run stays silent
    GLastLoggedState := ListSignature(List);
  except
    // arbitrating must never break the IDE (e.g. if the disassembled
    // GetFileFormats address turns out to be bogus)
  end;
end;

{ TPngArbiterNotifier }

procedure TPngArbiterNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
begin
  // IDE shutdown: packages unload in droves and their graphic classes may
  // already be gone - never walk the list then
  if Application.Terminated then
    Exit;
  case NotifyCode of
    ofnPackageInstalled:
      Arbitrate('package installed: ' + ExtractFileName(FileName));
    ofnPackageUninstalled:
      Arbitrate('package uninstalled: ' + ExtractFileName(FileName));
  end;
end;

procedure TPngArbiterNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TPngArbiterNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

procedure SetPreferProperPNGActive(Active: Boolean);
begin
  if Active then
  begin
    if GNotifierIndex >= 0 then
      Exit; // already installed
    GNotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TPngArbiterNotifier.Create);
    Arbitrate('feature activated');
  end
  else
  begin
    if GNotifierIndex >= 0 then
    begin
      // guarded: during late IDE shutdown BorlandIDEServices may already be
      // gone ("as" on a nil interface yields nil - calling it would AV)
      try
        if Assigned(BorlandIDEServices) then
          (BorlandIDEServices as IOTAServices).RemoveNotifier(GNotifierIndex);
      except
      end;
      GNotifierIndex := -1;
    end;
    // deliberately no "undo": the reorder is non-destructive and harmless
  end;
end;

initialization

finalization
  SetPreferProperPNGActive(False);

end.
