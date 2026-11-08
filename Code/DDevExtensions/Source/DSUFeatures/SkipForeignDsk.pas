{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* Keep Delphi 7 from hanging on .dsk files written by newer IDEs             *}
{*                                                                            *}
{******************************************************************************}

unit SkipForeignDsk;

{
  When a project was last used in a BDS-based Delphi (2005+), its .dsk desktop
  file is written in the newer IDE's format. Loading such a project in Delphi 7
  sends the IDE into an endless busy-loop while it restores the desktop (still
  on the splash screen, one core at 100%, until it finally dies on what looks
  like a stack overflow). Measured with a Delphi 13 .dsk: the loop happens even
  after removing the .dproj module entry from the file, so no partial sanitizing
  helps - the whole file must be kept away from the D7 desktop reader. The .res
  and .dproj the newer IDE leaves behind are harmless, it is only the .dsk.

  Fix: before Delphi 7 reads a project's .dsk, check whether it came from a
  newer IDE and if so rename it to <name>.dsk.bak. The desktop layout in it is
  useless to D7 anyway (different window/dock model), and D7 simply writes a
  fresh .dsk on close. Detection is a content check: a newer-IDE .dsk always
  references its project file (.dproj/.groupproj/.bdsproj) - extensions a
  Delphi 7 .dsk cannot contain (D7 also writes ModuleType=SourceModule where
  BDS writes ModuleType=TSourceModule, but the extension check alone is
  unambiguous).

  Hooked via IOTAIDENotifier: ofnFileOpening for the .dpr handles the file
  before the project load touches it; ofnProjectDesktopLoad is the belt-and-
  braces path (rename again if still there, and Cancel the desktop load in
  case the rename fails on a locked/read-only file).
}

interface

procedure InitPlugin(Unload: Boolean);
procedure InstallSkipForeignDsk(Value: Boolean);

implementation

uses
  Windows, SysUtils, Classes, ToolsAPI;

type
  TForeignDskNotifier = class(TNotifierObject, IOTAIDENotifier)
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification;
      const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
    procedure AfterCompile(Succeeded: Boolean);
  end;

var
  GNotifierIndex: Integer = -1;

{ Diagnostic log, only active with environment variable DSKDIAG set: appends
  every IDE file notification to %TEMP%\SkipForeignDsk.log }
procedure DiagLog(const S: string);
var
  F: TextFile;
  LogFile: string;
begin
  if GetEnvironmentVariable('DSKDIAG') = '' then
    Exit;
  try
    LogFile := GetEnvironmentVariable('TEMP') + '\SkipForeignDsk.log';
    AssignFile(F, LogFile);
    if FileExists(LogFile) then
      Append(F)
    else
      Rewrite(F);
    try
      WriteLn(F, S);
    finally
      CloseFile(F);
    end;
  except
  end;
end;

{ True if the .dsk was written by a BDS-based IDE (references .dproj/.groupproj/
  .bdsproj files, which cannot occur in a Delphi 7 .dsk). Any read error counts
  as "not foreign" - then nothing is touched. }
function IsForeignDsk(const DskFile: string): Boolean;
var
  Stream: TFileStream;
  Data: string;
begin
  Result := False;
  try
    if not FileExists(DskFile) then
      Exit;
    Stream := TFileStream.Create(DskFile, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size <= 0 then
        Exit;
      SetLength(Data, Stream.Size);
      Stream.ReadBuffer(Data[1], Stream.Size);
    finally
      Stream.Free;
    end;
    Data := AnsiLowerCase(Data);
    Result := (Pos('.dproj', Data) > 0) or (Pos('.groupproj', Data) > 0) or
              (Pos('.bdsproj', Data) > 0);
  except
    // never break the project open
  end;
end;

{ Move the foreign .dsk out of the IDE's way; keep it as <name>.dsk.bak }
function ParkForeignDsk(const DskFile: string): Boolean;
var
  BakFile: string;
begin
  Result := False;
  try
    BakFile := DskFile + '.bak';
    if FileExists(BakFile) then
      DeleteFile(BakFile);
    Result := RenameFile(DskFile, BakFile);
  except
  end;
end;

{ TForeignDskNotifier }

procedure TForeignDskNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  DskFile: string;
begin
  DiagLog('notify=' + IntToStr(Ord(NotifyCode)) + ' file=' + FileName);
  case NotifyCode of
    ofnFileOpening:
      if SameText(ExtractFileExt(FileName), '.dpr') or
         SameText(ExtractFileExt(FileName), '.dpk') or
         SameText(ExtractFileExt(FileName), '.bpg') then
      begin
        DskFile := ChangeFileExt(FileName, '.dsk');
        if IsForeignDsk(DskFile) then
          ParkForeignDsk(DskFile);
      end;
    ofnProjectDesktopLoad:
      if IsForeignDsk(FileName) then
      begin
        Cancel := True; // skip the desktop load even if the rename fails
        ParkForeignDsk(FileName);
      end;
  end;
end;

procedure TForeignDskNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TForeignDskNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

procedure InitPlugin(Unload: Boolean);
begin
  if not Unload then
    DiagLog('InitPlugin cmdline=' + CmdLine);
  InstallSkipForeignDsk(not Unload);
end;

procedure InstallSkipForeignDsk(Value: Boolean);
begin
  if Value then
  begin
    if GNotifierIndex >= 0 then
      Exit; // already installed
    GNotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TForeignDskNotifier.Create);
  end
  else
  begin
    if GNotifierIndex >= 0 then
    begin
      // guarded: runs from the finalization too, where BorlandIDEServices may
      // already be nil during late IDE shutdown
      try
        if Assigned(BorlandIDEServices) then
          (BorlandIDEServices as IOTAServices).RemoveNotifier(GNotifierIndex);
      except
      end;
      GNotifierIndex := -1;
    end;
  end;
end;

initialization

finalization
  InstallSkipForeignDsk(False);

end.
