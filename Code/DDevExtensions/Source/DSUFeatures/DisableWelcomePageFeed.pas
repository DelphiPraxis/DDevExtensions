{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006-2011 Andreas Hausladen                                            *}
{*                                                                            *}
{******************************************************************************}

unit DisableWelcomePageFeed;

{$I ..\DelphiExtension.inc}

interface

{ The IDE's welcome page pulls a news feed on startup. When that fetch fails -
  firewall block, or a feed URL that has simply gone dead on the older IDEs -
  the fetcher dereferences a nil result and every single IDE start greets you
  with an access violation:

    EAccessViolation in 'WelcomePage.Plugin.GetItFeed370.bpl'
    TGetItFeedThread.Execute (WPPlugin.GetItFeed.Model)

  That code sits in a closed-source Embarcadero package with no exported entry
  points, so there is nothing to hook and nothing to guard. The only lever is
  to keep the IDE from loading the package in the first place, by taking it out
  of the "Known IDE Packages" registry list.

  Taking the card out of the welcome page layout is NOT enough: the package is
  still loaded and the feed thread still runs. }

{ True if the IDE will load the feed package on its next start }
function WelcomePageFeedRegistered: Boolean;
{ True if the feed package is parked and not registered }
function WelcomePageFeedDisabled: Boolean;
procedure SetWelcomePageFeedDisabled(Value: Boolean);

implementation

uses
  Windows, SysUtils, Classes, Registry, ToolsAPI;

const
  { Matched as a substring of the value name, which is the bpl path. The version
    suffix is not derivable from the compiler version - Delphi 11 is 280,
    Delphi 12 is 290, but Delphi 13 jumps to 370 - so the name is never built,
    only recognized. }
  FeedPackages: array[0..1] of string = (
    'WelcomePage.Plugin.GetItFeed', // Delphi 11+: just the GetIt feed card
    'startpageide'                  // Delphi 2009 - 10.4: the whole start page
  );

  PackageKeys: array[0..1] of string = (
    '\Known IDE Packages',
    '\Known IDE Packages x64' // Delphi 12+ only, skipped where it does not exist
  );

  { Disabled entries are parked in a sibling key rather than deleted. The value
    name carries the version suffix above, so a deleted entry could not be
    reconstructed to restore it. The IDE ignores keys it does not know. }
  DisabledKeySuffix = ' Disabled by DDevExtensions';

function BaseRegKey: string;
begin
  Result := '';
  if BorlandIDEServices <> nil then
  begin
    Result := (BorlandIDEServices as IOTAServices).GetBaseRegistryKey;
    if (Result <> '') and (Result[1] = '\') then
      Delete(Result, 1, 1);
  end;
end;

function IsFeedPackage(const ValueName: string): Boolean;
var
  I: Integer;
  LowerName: string;
begin
  LowerName := AnsiLowerCase(ValueName);
  for I := Low(FeedPackages) to High(FeedPackages) do
    if Pos(AnsiLowerCase(FeedPackages[I]), LowerName) > 0 then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ Moves every feed package entry from SrcKey to DstKey. The value is written to
  the target before it is dropped from the source: a move that loses the entry
  half way through would take the package registration with it for good. }
procedure MoveFeedPackages(const SrcKey, DstKey: string);
var
  Src, Dst: TRegistry;
  Names: TStringList;
  I: Integer;
begin
  Names := TStringList.Create;
  Src := TRegistry.Create;
  Dst := TRegistry.Create;
  try
    Src.RootKey := HKEY_CURRENT_USER;
    Dst.RootKey := HKEY_CURRENT_USER;
    if not Src.KeyExists(SrcKey) or not Src.OpenKey(SrcKey, False) then
      Exit;
    Src.GetValueNames(Names);
    for I := 0 to Names.Count - 1 do
    begin
      if not IsFeedPackage(Names[I]) then
        Continue;
      if not Dst.OpenKey(DstKey, True) then
        Exit;
      Dst.WriteString(Names[I], Src.ReadString(Names[I]));
      if Dst.ValueExists(Names[I]) then
        Src.DeleteValue(Names[I]);
    end;
  finally
    Dst.Free;
    Src.Free;
    Names.Free;
  end;
end;

{ KeySuffix = '': the lists the IDE loads from; DisabledKeySuffix: the parked entries }
function HasFeedPackage(const KeySuffix: string): Boolean;
var
  Reg: TRegistry;
  Names: TStringList;
  Base, Key: string;
  I, K: Integer;
begin
  Result := False;
  Base := BaseRegKey;
  if Base = '' then
    Exit;

  Names := TStringList.Create;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    for K := Low(PackageKeys) to High(PackageKeys) do
    begin
      Key := Base + PackageKeys[K] + KeySuffix;
      if not Reg.KeyExists(Key) or not Reg.OpenKeyReadOnly(Key) then
        Continue;
      Names.Clear;
      Reg.GetValueNames(Names);
      for I := 0 to Names.Count - 1 do
        if IsFeedPackage(Names[I]) then
        begin
          Result := True;
          Exit;
        end;
    end;
  finally
    Reg.Free;
    Names.Free;
  end;
end;

function WelcomePageFeedRegistered: Boolean;
begin
  Result := HasFeedPackage('');
end;

function WelcomePageFeedDisabled: Boolean;
begin
  // an IDE update can put the package back while the parked entry is still there
  Result := HasFeedPackage(DisabledKeySuffix) and not HasFeedPackage('');
end;

procedure SetWelcomePageFeedDisabled(Value: Boolean);
var
  Base: string;
  K: Integer;
begin
  Base := BaseRegKey;
  if Base = '' then
    Exit;

  for K := Low(PackageKeys) to High(PackageKeys) do
    if Value then
      MoveFeedPackages(Base + PackageKeys[K], Base + PackageKeys[K] + DisabledKeySuffix)
    else
      MoveFeedPackages(Base + PackageKeys[K] + DisabledKeySuffix, Base + PackageKeys[K]);
end;

end.
