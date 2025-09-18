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
    FRemoveTextHeightProperty: Boolean;
    procedure SetActive(const Value: Boolean);
    procedure SetLabelMargin(const Value: Boolean);
    procedure SetRemoveExplicitProperty(const Value: Boolean);
    procedure SetRemoveTextHeightProperty(const Value: Boolean);
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
    property RemoveTextHeightProperty: Boolean read FRemoveTextHeightProperty write SetRemoveTextHeightProperty;
  end;

  TFrameOptionPageFormDesigner = class(TFrameBase, ITreePageComponent)
    cbxActive: TCheckBox;
    cbxLabelMargin: TCheckBox;
    chkRemoveExplicitProperties: TCheckBox;
    chkRemoveTextHeightProperty: TCheckBox;
    procedure cbxActiveClick(Sender: TObject);
  private
    { Private-Deklarationen }
    FFormDesigner: TFormDesigner;
  public
    { Public-Deklarationen }
    constructor Create(AOwner: TComponent); override;
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
  Main, LabelMarginHelper, RemoveExplicitProperty, RemoveTextHeightProperty;

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

constructor TFrameOptionPageFormDesigner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  {$IFNDEF DELPHI28_UP}
  chkRemoveTextHeightProperty.Visible := False;
  {$ENDIF}
end;

procedure TFrameOptionPageFormDesigner.cbxActiveClick(Sender: TObject);
begin
  cbxLabelMargin.Enabled := cbxActive.Checked;
  chkRemoveExplicitProperties.Enabled := cbxActive.Checked;
  chkRemoveTextHeightProperty.Enabled := cbxActive.Checked;
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
  chkRemoveTextHeightProperty.Checked := FFormDesigner.RemoveTextHeightProperty;

  cbxActiveClick(cbxActive);
end;

procedure TFrameOptionPageFormDesigner.SaveData;
begin
  FFormDesigner.LabelMargin := cbxLabelMargin.Checked;
  FFormDesigner.RemoveExplicitProperty := chkRemoveExplicitProperties.Checked;
  FFormDesigner.RemoveTextHeightProperty := chkRemoveTextHeightProperty.Checked;

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
  RemoveTextHeightProperty := False;
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

procedure TFormDesigner.SetRemoveTextHeightProperty(const Value: Boolean);
begin
  if Value <> FRemoveTextHeightProperty then
  begin
    FRemoveTextHeightProperty := Value;
    if Active then
      UpdateHooks;
  end;
end;

procedure TFormDesigner.UpdateHooks;
begin
  {$IFDEF INCLUDE_FORMDESIGNER}
  SetLabelMarginActive(Active and LabelMargin);
  SetRemoveExplicitPropertyActive(Active and RemoveExplicitProperty);
    {$IFDEF DELPHI28_UP}
  SetRemoveTextHeightPropertyActive(Active and RemoveTextHeightProperty);
    {$ENDIF}
  {$ENDIF INCLUDE_FORMDESIGNER}
end;

function TFormDesigner.GetOptionPages: TTreePage;
begin
  Result := TTreePage.Create('Form Designer', TFrameOptionPageFormDesigner, Self);
end;

end.
