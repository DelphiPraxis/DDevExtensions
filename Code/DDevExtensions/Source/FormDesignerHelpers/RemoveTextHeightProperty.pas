{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2008 Andreas Hausladen                                                 *}
{*                                                                            *}
{******************************************************************************}

unit RemoveTextHeightProperty;

{$I ..\DelphiExtension.inc}

interface

{$IFDEF DELPHI28_UP}

uses
  SysUtils, Classes, Forms, Controls, IDEHooks, Hooking;

procedure SetRemoveTextHeightPropertyActive(Active: Boolean);

{$ENDIF DELPHI28_UP}

implementation

{$IFDEF DELPHI28_UP}

uses
  IDEUtils;

var
  HookTForm_DefineProperties: TRedirectCode;

type
  TFormEx = class(TCustomForm)
    procedure IgnoreInteger(Reader: TReader);
    procedure ReadIgnoreFontProperty(Reader: TReader);
    procedure IgnoreIdent(Reader: TReader);
    procedure DefineProperties(Filer: TFiler); override;
  end;

  TOpenForm = class(TCustomForm);

procedure TFormEx.IgnoreInteger(Reader: TReader);
begin
  Reader.ReadInteger;
end;

procedure TFormEx.ReadIgnoreFontProperty(Reader: TReader);
begin   // reroute BCB IgnoreFontProperty to use VCL locale font solution
  if Reader.ReadBoolean then
    ParentFont := True;
end;

procedure TFormEx.IgnoreIdent(Reader: TReader);
begin
  Reader.ReadIdent;
end;

type
  TDefinePropertiesProc = procedure(Filer: TFiler) of object;

procedure TFormEx.DefineProperties(Filer: TFiler);
begin
{$IF True}
  var DefinePropertiesProc: TDefinePropertiesProc;
  TMethod(DefinePropertiesProc).Code := @TScrollingWinControl.DefineProperties;
  TMethod(DefinePropertiesProc).Data := Self;
  DefinePropertiesProc(Filer);
{$ELSE}
  inherited DefineProperties(Filer);
{$ENDIF}

  Filer.DefineProperty('TextHeight', IgnoreInteger, nil, False);
  Filer.DefineProperty('IgnoreFontProperty', ReadIgnoreFontProperty, nil, False);
  Filer.DefineProperty('OldCreateOrder', IgnoreIdent, nil, False);
end;

var
  IsActive: Boolean;

procedure SetRemoveTextHeightPropertyActive(Active: Boolean);
begin
  if Active <> IsActive then
  begin
    IsActive := Active;
    if Active then
      CodeRedirect(@TOpenForm.DefineProperties, @TFormEx.DefineProperties, HookTForm_DefineProperties)
    else
      UnhookFunction(HookTForm_DefineProperties);
  end;
end;

{$ENDIF DELPHI28_UP}

end.
