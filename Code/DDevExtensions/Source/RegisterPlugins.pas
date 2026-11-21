{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006-2011 Andreas Hausladen                                            *}
{*                                                                            *}
{******************************************************************************}

unit RegisterPlugins;

{$I DelphiExtension.inc}

interface

procedure RegisterIDEPlugins;

implementation

uses
  SysUtils, Classes, Main,
  {$IF CompilerVersion < 21.0} // pre-2010 only (PM was rebuilt in RAD Studio 2010)
  ProjectMgrShortCuts,
  {$IFEND}
  {$IF CompilerVersion < 16.0} // Delphi 7: shield against BDS-written .dsk files
  SkipForeignDsk,
  {$IFEND}
  FrmeOptionPageFormDesigner,
  FrmProjectSettingsSetVersioninfo, FocusEditor, CompileProgress,
  IDEMenuHandler, FrmeOptionPageKeybindings,
  FrmeOptionPageFileCleaner, FrmeOptionPageCompileBackup,
  {$IFDEF INCLUDE_COMPILERENHANCEMENTS}
  FrmeOptionPageCompilerEnhancements,
  {$ENDIF INCLUDE_COMPILERENHANCEMENTS}
  {$IFDEF INCLUDE_STARTPARAMETERTEAM}
  FrmeOptionPageStartParameterTeam, // XE2 made the parameter configuration-aware
  {$ENDIF INCLUDE_STARTPARAMETERTEAM}
  FrmeOptionPageDSUFeatures, ComponentSelector, StrucViewSearch,
  {$IF CompilerVersion <= 32.0} // 10.2 Tokyo-
  FrmeOptionPageOldPalette,
  {$IFEND}
  StartParameterManagerReg, FrmReloadFiles{, PrjDesktopState},
  CodeInsightHandling;

procedure RegisterIDEPlugins;
var
  DisabledPlugins: TStringList;
  I: Integer;
begin
  DisabledPlugins := TStringList.Create;
  DisabledPlugins.Delimiter := ';';
  DisabledPlugins.DelimitedText := GetEnvironmentVariable('DDevExtensions.DisabledFeatures');
  for I := 0 to DisabledPlugins.Count - 1 do
    DisabledPlugins[I] := Trim(DisabledPlugins[I]);
  DisabledPlugins.Sorted := True;
  try
    if DisabledPlugins.IndexOf('DSUFeatures') = -1 then
      RegisterLateLoader(FrmeOptionPageDSUFeatures.InitPlugin);

    {$IF CompilerVersion < 16.0} // Delphi 7: a .dsk written by a newer IDE hangs the
    // project open, which happens BEFORE the late loaders run (splash) - so this
    // must go through the early expert loader
    if DisabledPlugins.IndexOf('SkipForeignDsk') = -1 then
      RegisterExpertLoader(SkipForeignDsk.InitPlugin);
    {$IFEND}

    {$IFDEF INCLUDE_FOCUSEDITOR}
    if DisabledPlugins.IndexOf('FocusEditor') = -1 then
      RegisterLateLoader(FocusEditor.InitPlugin); // Set focus to editor after debugging
    {$ENDIF}

//    if DisabledPlugins.IndexOf('ProjectDesktopState') = -1 then
//      RegisterLateLoader(PrjDesktopState.InitPlugin);

    {$IFDEF INCLUDE_IDEMENUHANDLER}
    if DisabledPlugins.IndexOf('IDEMenuHandler') = -1 then
      RegisterLateLoader(IDEMenuHandler.InitPlugin);
    {$ENDIF}

    {$IFDEF INCLUDE_FORMDESIGNER}
    if DisabledPlugins.IndexOf('FormDesigner') = -1 then
      RegisterLateLoader(FrmeOptionPageFormDesigner.InitPlugin);
    {$ENDIF}

    {$IFDEF INCLUDE_COMPONENTSELECTOR}
    if DisabledPlugins.IndexOf('ComponentSelector') = -1 then
      RegisterLateLoader(ComponentSelector.InitPlugin);
    {$ENDIF}

  {------------------------------------------------------------------------------}

    if DisabledPlugins.IndexOf('ProjectSettingsSetVersioninfo') = -1 then
      RegisterLateLoader(FrmProjectSettingsSetVersioninfo.InitPlugin);

    {$IFDEF INCLUDE_COMPILEPROGRESS}
    if DisabledPlugins.IndexOf('CompileProgress') = -1 then
      RegisterLateLoader(CompileProgress.InitPlugin);
    {$ENDIF}

    {$IFDEF INCLUDE_COMPILERENHANCEMENTS}
    if DisabledPlugins.IndexOf('CompilerEnhancements') = -1 then
      RegisterLateLoader(FrmeOptionPageCompilerEnhancements.InitPlugin);
    {$ENDIF}

    // UnitSelector removed 2026-07: FrmUnitSelector never made it into this
    // source line and CnWizards covers the feature
    {$IFDEF INCLUDE_FILECLEANER}
    if DisabledPlugins.IndexOf('FileCleaner') = -1 then
      RegisterLateLoader(FrmeOptionPageFileCleaner.InitPlugin);
    {$ENDIF}

    {$IFDEF INCLUDE_COMPILEBACKUP}
    if DisabledPlugins.IndexOf('CompileBackup') = -1 then
      RegisterLateLoader(FrmeOptionPageCompileBackup.InitPlugin);
    {$ENDIF}

    {$IF CompilerVersion <= 32.0} // 10.2 Tokyo-
    {$IFDEF INCLUDE_OLDPALETTE}
    if DisabledPlugins.IndexOf('OldPalette') = -1 then
      RegisterLateLoader(FrmeOptionPageOldPalette.InitPlugin);
    {$ENDIF}
    {$IFEND}

    {$IFDEF INCLUDE_KEYBINDINGS}
    if DisabledPlugins.IndexOf('Keybindings') = -1 then
      RegisterLateLoader(FrmeOptionPageKeybindings.InitPlugin);
    {$ENDIF}

    {$IFDEF INCLUDE_EDITOR}
    if DisabledPlugins.IndexOf('Editor') = -1 then
      RegisterLateLoader(FrmeOptionPageEditor.InitPlugin); // Delphi 2006+
    {$ENDIF}

    {$IFDEF INCLUDE_STARTPARAMETERTEAM}
    if DisabledPlugins.IndexOf('StartParameterTeam') = -1 then
      RegisterLateLoader(FrmeOptionPageStartParameterTeam.InitPlugin);
    {$ENDIF}

    {$IFDEF INCLUDE_STRUCVIEWSEARCH}
    if DisabledPlugins.IndexOf('StrucViewSearch') = -1 then
      RegisterLateLoader(StrucViewSearch.InitPlugin);
    {$ENDIF}

    {$IF CompilerVersion < 21.0} // pre-2010: PM build-order shortcuts (no-op unit otherwise)
    if DisabledPlugins.IndexOf('ProjectMgrShortCuts') = -1 then
      RegisterLateLoader(ProjectMgrShortCuts.InitPlugin);
    {$IFEND}

    if DisabledPlugins.IndexOf('StartParameter') = -1 then
      RegisterExpertLoader(StartParameterManagerReg.InitPlugin);

    if DisabledPlugins.IndexOf('ReloadFiles') = -1 then
      RegisterExpertLoader(FrmReloadFiles.InitPlugin);

    if DisabledPlugins.IndexOf('CodeInsightHandling') = -1 then
      RegisterLateLoader(CodeInsightHandling.InitPlugin);

  finally
    DisabledPlugins.Free;
  end;
end;

end.
