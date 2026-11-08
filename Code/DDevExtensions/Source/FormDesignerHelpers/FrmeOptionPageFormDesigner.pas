{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2007 Andreas Hausladen                                                 *}
{*                                                                            *}
{******************************************************************************}

unit FrmeOptionPageFormDesigner;

{$I ..\DelphiExtension.inc}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  Dialogs, ToolsAPI, FrmTreePages, PluginConfig, StdCtrls,
  ModuleData, FrmeBase, ExtCtrls;

type
  TFormDesigner = class(TPluginConfig)
  private
    FActive: Boolean;
    FLabelMargin: Boolean;
    FRemoveExplicitProperty: Boolean;
    FRemovePixelsPerInchProperty: Boolean;
    FRemoveTextHeightProperty: Boolean;
    FFixAlphaControlsPNG: Boolean;
    FPreferProperPNG: Boolean;
    FIDEPngSupport: Boolean;
    procedure SetActive(const Value: Boolean);
    procedure SetLabelMargin(const Value: Boolean);
    procedure SetRemoveExplicitProperty(const Value: Boolean);
    procedure SetRemovePixelsPerInchProperty(const Value: Boolean);
    procedure SetRemoveTextHeightProperty(const Value: Boolean);
    procedure SetFixAlphaControlsPNG(const Value: Boolean);
    procedure SetPreferProperPNG(const Value: Boolean);
    procedure SetIDEPngSupport(const Value: Boolean);
  protected
    function GetOptionPages: TTreePage; override;
    procedure Init; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure UpdateHooks;
  published
    property Active: Boolean read FActive write SetActive;
    property LabelMargin: Boolean read FLabelMargin write SetLabelMargin;
    property RemoveExplicitProperty: Boolean read FRemoveExplicitProperty write SetRemoveExplicitProperty;
    property RemovePixelsPerInchProperty : Boolean read FRemovePixelsPerInchProperty write SetRemovePixelsPerInchProperty;
    property RemoveTextHeightProperty: Boolean read FRemoveTextHeightProperty write SetRemoveTextHeightProperty;
    property FixAlphaControlsPNG : Boolean read FFixAlphaControlsPNG write SetFixAlphaControlsPNG;
    property PreferProperPNG: Boolean read FPreferProperPNG write SetPreferProperPNG;
    property IDEPngSupport: Boolean read FIDEPngSupport write SetIDEPngSupport;
  end;

  TFrameOptionPageFormDesigner = class(TFrameBase, ITreePageComponent)
    cbxActive: TCheckBox;
    cbxLabelMargin: TCheckBox;
    chkRemoveExplicitProperties: TCheckBox;
    chkRemovePixelsPerInchProperties: TCheckBox;
    chkRemoveTextHeightProperty: TCheckBox;
    chkFixAlphaControlsPNG: TCheckBox;
    chkPreferProperPNG: TCheckBox;
    chkIDEPngSupport: TCheckBox;
    procedure cbxActiveClick(Sender: TObject);
  private
    { Private-Deklarationen }
    FFormDesigner: TFormDesigner;
  public
    { Public-Deklarationen }
    procedure SetUserData(UserData: TObject);
    procedure LoadData;
    procedure SaveData;
    procedure Selected;
    procedure Unselected;
  end;

{$IFDEF INCLUDE_FORMDESIGNER}

procedure InitPlugin(Unload: Boolean);

{$ENDIF INCLUDE_FORMDESIGNER}

implementation

uses
  Main, LabelMarginHelper, PreferProperPNG,
  {$IFDEF INCLUDE_ACPNGFIX}FixAlphaControlsPNG,{$ENDIF}
  {$IFDEF DELPHI28_UP}RemovePixelsPerInchProperty,{$ENDIF}
  RemoveExplicitProperty,
  RemoveTextHeightProperty;

{$R *.dfm}

{$IFDEF INCLUDE_FORMDESIGNER}

var
  FormDesigner: TFormDesigner;

procedure InitPlugin(Unload: Boolean);
begin
  if not Unload then
    FormDesigner := TFormDesigner.Create
  else
    FreeAndNil(FormDesigner);
end;

{$ENDIF INCLUDE_FORMDESIGNER}

{ TFrameOptionPageFormDesigner }

procedure TFrameOptionPageFormDesigner.cbxActiveClick(Sender: TObject);
begin
  // LabelMarginHelper and RemoveExplicitProperty are whole-unit {$IFDEF COMPILER10_UP}
  // (empty on Delphi 7), so their hooks do nothing there - grey the controls out
  cbxLabelMargin.Enabled := {$IFDEF COMPILER10_UP}cbxActive.Checked{$ELSE}False{$ENDIF};
  chkRemoveExplicitProperties.Enabled := {$IFDEF COMPILER10_UP}cbxActive.Checked{$ELSE}False{$ENDIF};
  chkRemovePixelsPerInchProperties.Enabled := {$IFDEF DELPHI28_UP}cbxActive.Checked{$ELSE}False{$ENDIF};
  chkRemoveTextHeightProperty.Enabled := {$IFDEF DELPHI28_UP}cbxActive.Checked{$ELSE}False{$ENDIF};
  chkFixAlphaControlsPNG.Enabled := {$IFDEF INCLUDE_ACPNGFIX}cbxActive.Checked{$ELSE}False{$ENDIF};
  chkPreferProperPNG.Enabled := cbxActive.Checked;
  chkIDEPngSupport.Enabled := {$IF Defined(INCLUDE_ACPNGFIX) and not Defined(COMPILER12_UP)}cbxActive.Checked{$ELSE}False{$IFEND};
end;

procedure TFrameOptionPageFormDesigner.SetUserData(UserData: TObject);
begin
  FFormDesigner := UserData as TFormDesigner;
end;

procedure TFrameOptionPageFormDesigner.LoadData;
begin
  cbxActive.Checked := FFormDesigner.Active;
  cbxLabelMargin.Checked := FFormDesigner.LabelMargin;
  chkRemoveExplicitProperties.Checked := FFormDesigner.RemoveExplicitProperty;
  chkRemovePixelsPerInchProperties.Checked := FFormDesigner.RemovePixelsPerInchProperty;
  chkRemoveTextHeightProperty.Checked := FFormDesigner.RemoveTextHeightProperty;
  chkFixAlphaControlsPNG.Checked := FFormDesigner.FixAlphaControlsPNG;
  chkPreferProperPNG.Checked := FFormDesigner.PreferProperPNG;
  chkIDEPngSupport.Checked := FFormDesigner.IDEPngSupport;

  cbxActiveClick(cbxActive);
end;

procedure TFrameOptionPageFormDesigner.SaveData;
begin
  FFormDesigner.LabelMargin := cbxLabelMargin.Checked;
  FFormDesigner.RemoveExplicitProperty := chkRemoveExplicitProperties.Checked;
  FFormDesigner.RemovePixelsPerInchProperty := chkRemovePixelsPerInchProperties.Checked;
  FFormDesigner.RemoveTextHeightProperty := chkRemoveTextHeightProperty.Checked;
  FFormDesigner.FixAlphaControlsPNG := chkFixAlphaControlsPNG.Checked;
  FFormDesigner.PreferProperPNG := chkPreferProperPNG.Checked;
  FFormDesigner.IDEPngSupport := chkIDEPngSupport.Checked;

  FFormDesigner.Active := cbxActive.Checked;
  FFormDesigner.Save;
end;

procedure TFrameOptionPageFormDesigner.Selected;
begin
end;

procedure TFrameOptionPageFormDesigner.Unselected;
begin
end;

{ TFormDesigner }

constructor TFormDesigner.Create;
begin
  inherited Create(AppDataDirectory + '\FormDesigner.xml', 'FormDesigner');
end;

destructor TFormDesigner.Destroy;
begin
  Active := False;
  inherited Destroy;
end;

procedure TFormDesigner.Init;
begin
  inherited Init;
  LabelMargin := True;
  RemoveExplicitProperty := False;
  RemovePixelsPerInchProperty := False;
  RemoveTextHeightProperty := False;
  FixAlphaControlsPNG := True;
  PreferProperPNG := False;
  IDEPngSupport := False;
  Active := True;
end;

procedure TFormDesigner.SetActive(const Value: Boolean);
begin
  if Value <> FActive then
  begin
    FActive := Value;
    UpdateHooks;
  end;
end;

procedure TFormDesigner.SetLabelMargin(const Value: Boolean);
begin
  if Value <> FLabelMargin then
  begin
    FLabelMargin := Value;
    if Active then
      UpdateHooks;
  end;
end;

procedure TFormDesigner.SetRemoveExplicitProperty(const Value: Boolean);
begin
  if Value <> FRemoveExplicitProperty then
  begin
    FRemoveExplicitProperty := Value;
    if Active then
      UpdateHooks;
  end;
end;

procedure TFormDesigner.SetRemovePixelsPerInchProperty(const Value: Boolean);
begin
  if Value <> FRemovePixelsPerInchProperty then
  begin
    FRemovePixelsPerInchProperty := Value;
    if Active then
      UpdateHooks;
  end;
end;

procedure TFormDesigner.SetRemoveTextHeightProperty(const Value: Boolean);
begin
  if Value <> FRemoveTextHeightProperty then
  begin
    FRemoveTextHeightProperty := Value;
    if Active then
      UpdateHooks;
  end;
end;

procedure TFormDesigner.SetFixAlphaControlsPNG(const Value: Boolean);
begin
  if Value <> FFixAlphaControlsPNG then
  begin
    FFixAlphaControlsPNG := Value;
    if Active then
      UpdateHooks;
  end;
end;

procedure TFormDesigner.SetPreferProperPNG(const Value: Boolean);
begin
  if Value <> FPreferProperPNG then
  begin
    FPreferProperPNG := Value;
    if Active then
      UpdateHooks;
  end;
end;

procedure TFormDesigner.SetIDEPngSupport(const Value: Boolean);
begin
  if Value <> FIDEPngSupport then
  begin
    FIDEPngSupport := Value;
    if Active then
      UpdateHooks;
  end;
end;

procedure TFormDesigner.UpdateHooks;
begin
  {$IFDEF INCLUDE_FORMDESIGNER}

  {$IFDEF COMPILER10_UP}
  SetLabelMarginActive(Active and LabelMargin);
  SetRemoveExplicitPropertyActive(Active and RemoveExplicitProperty);
  {$ENDIF COMPILER10_UP}

  {$IFDEF INCLUDE_ACPNGFIX}
  SetFixAlphaControlsPNGActive(Active and FixAlphaControlsPNG);
  {$IF not Defined(COMPILER12_UP)}
  SetIDEPngSupportActive(Active and IDEPngSupport);
  {$IFEND}
  {$ENDIF}

  SetPreferProperPNGActive(Active and PreferProperPNG);
  
  {$IFDEF COMPILER28_UP}
  SetRemovePixelsPerInchPropertyActive(Active and RemovePixelsPerInchProperty);
  SetRemoveTextHeightPropertyActive(Active and RemoveTextHeightProperty);
  {$ENDIF COMPILER28_UP}

  {$ENDIF INCLUDE_FORMDESIGNER}
end;

function TFormDesigner.GetOptionPages: TTreePage;
begin
  Result := TTreePage.Create('Form Designer', TFrameOptionPageFormDesigner, Self);
end;

end.
