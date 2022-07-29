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

{$IFDEF COMPILER10_UP}

uses
  SysUtils, Classes, Forms, Controls, IDEHooks, Hooking;

procedure SetRemoveTextHeightPropertyActive(Active: Boolean);

{$ENDIF COMPILER10_UP}

implementation

{$IFDEF COMPILER10_UP}

uses
  IDEUtils;

var
  HookTForm_DefineProperties: TRedirectCode;

type
  TFormEx = class(TForm)
  protected
    procedure IgnoreInteger(Reader: TReader);
    procedure DefineProperties(Filer: TFiler); override;
  end;

  TOpenForm = class(TForm);

procedure TFormEx.IgnoreInteger(Reader: TReader);
begin
  Reader.ReadInteger;
end;

procedure TFormEx.DefineProperties(Filer: TFiler);
begin
  Filer.DefineProperty('TextHeight', IgnoreInteger, nil, False);
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

{$ENDIF COMPILER10_UP}

end.
