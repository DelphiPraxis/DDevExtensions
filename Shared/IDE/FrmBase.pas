{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2008 Andreas Hausladen                                                 *}
{*                                                                            *}
{******************************************************************************}
{$A+,B-,C+,D+,E-,F-,G+,H+,I+,J-,K-,L+,M-,N-,O+,P+,Q-,R-,S-,T-,U-,V+,W-,X+,Y+,Z1}

unit FrmBase;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ComCtrls
  {$IF CompilerVersion > 30}
  ,Vcl.Themes
  ,Vcl.Styles
  {$IFEND}
  ;

type
  TFormBase = class(TForm)
  private
    { Private-Deklarationen }
    {$IF (CompilerVersion >= 32.0) and (CompilerVersion < 34.0)}
    procedure ThemeTreeAdvancedCustomDrawItem(Sender: TCustomTreeView;
      Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage;
      var PaintImages, DefaultDraw: Boolean);
    {$IFEND}
  protected
    procedure DoClose(var Action: TCloseAction); override;
    procedure DoShow; override;
  public
    { Public-Deklarationen }
    constructor Create(AOwner: TComponent); override;
    procedure FormCreate(Sender: TObject);
    procedure ApplyIDETheme;
    {$IF CompilerVersion >= 32.0}
    { Public: FrmTreePages must run this over option page frames that are
      created after the dialog's ApplyIDETheme }
    procedure ThemeFixupControls(AParent: TWinControl);
    {$IFEND}
    function ShowModal: Integer; override;
  end;

var
  FormBase: TFormBase;

implementation

uses
  {$IF CompilerVersion >= 32.0}
  ToolsAPI, // IDE theming services (10.2.2+)
  {$IFEND}
  {$IF (CompilerVersion >= 32.0) and (CompilerVersion < 34.0)}
  UxTheme,
  {$IFEND}
  {$IF (CompilerVersion >= 34.0) and (CompilerVersion < 37.0)}
  Menus, // ShortCutToText for the hotkey client paint
  {$IFEND}
  HtHint;

{$R *.dfm}

type
  PPointer = ^Pointer;
  {$IF not declared(SIZE_T)}
  SIZE_T = DWORD;
  {$IFEND}

  TControlAccess = class(TControl);

function GetVirtualMethod(AClass: TClass; const Index: Integer): Pointer;
begin
  Result := PPointer(PAnsiChar(AClass) + Index * SizeOf(Pointer))^;
end;

procedure SetVirtualMethod(AClass: TClass; const Index: Integer; const Method: Pointer);
var
  WrittenBytes: SIZE_T;
  PatchAddress: PPointer;
begin
  PatchAddress := Pointer(PAnsiChar(AClass) + Index * SizeOf(Pointer));
  WriteProcessMemory(GetCurrentProcess, PatchAddress, @Method, SizeOf(Method), WrittenBytes);
end;

procedure ReaderError(Self: TObject; Reader: TReader; const Message: string; var Handled: Boolean);
begin
  Handled := True;
end;

function IgnoreReader_NewInstance(AClass: TClass): TObject;
var
  M: TMethod;
begin
  M.Code := @ReaderError;
  M.Data := nil;
  Result := TReader.NewInstance;
  TReader(Result).OnError := TReaderError(M);
end;

{ TFormBase }

constructor TFormBase.Create(AOwner: TComponent);
const
  {$WARNINGS OFF}
  Index = vmtNewInstance div SizeOf(Pointer);
  {$WARNINGS ON}
var
  NewInst: procedure;
begin
  NewInst := GetVirtualMethod(TReader, Index);
  try
    SetVirtualMethod(TReader, Index, @IgnoreReader_NewInstance);
    inherited Create(AOwner);
  finally
    SetVirtualMethod(TReader, Index, @NewInst);
  end;
  Font.Name := {$IFDEF UNICODE}UTF8ToString{$ENDIF}(DefFontData.Name);
  Font.Height := DefFontData.Height;

  { In the constructor (not in the OnCreate event): several descendants assign
    their own OnCreate handler without calling inherited, which silently
    skipped the theming for those dialogs (e.g. the options dialog). }
  ApplyIDETheme;
end;

procedure TFormBase.DoClose(var Action: TCloseAction);
begin
  inherited DoClose(Action);
  if Action <> caNone then
  begin
    // Save state
  end;
end;

procedure TFormBase.DoShow;

  // Set the dialogs base font name to every control that uses "Tahoma" (all MS Sans Serif were eliminated)
  procedure SetControlFonts(ParentControl: TWinControl);
  var
    I: Integer;
    Control: TControl;
  begin
    for I := 0 to ParentControl.ControlCount - 1 do
    begin
      Control := ParentControl.Controls[I];
      if TControlAccess(Control).Font.Name = 'Tahoma' then
        TControlAccess(Control).Font.Name := Self.Font.Name;
      if Control is TWinControl then
        SetControlFonts(TWinControl(Control));
    end;
  end;

begin
  // restore state
  inherited DoShow;

  if Self.Font.Name <> 'Tahoma' then
    SetControlFonts(Self);
end;

procedure TFormBase.FormCreate(Sender: TObject);
begin
  // theming happens in Create/ApplyIDETheme - descendants may replace this
  // handler without calling inherited
end;

procedure TFormBase.ApplyIDETheme;
{$IF CompilerVersion >= 34.0} // 10.4+: TControl.StyleName does not exist earlier (10 Seattle: E2003)
var
  ThemingServices: IOTAIDEThemingServices250;
  sName: string;
{$ELSE}
  {$IF CompilerVersion >= 32.0} // 10.2.2 Tokyo/10.3 Rio: no per-control styles yet
var
  ThemingServices: IOTAIDEThemingServices250;
  {$IFEND}
{$IFEND}
begin
  {$IF CompilerVersion >= 34.0}
  // 10.4+: let the IDE's theming engine apply its active style to the dialog.
  // Do NOT rely on looking the style up by name: the 'Win10IDE_*' style names
  // used up to Delphi 11 are gone in Delphi 12/13, which left the dialogs
  // unthemed (bright dialog on a dark IDE).
  if Supports(BorlandIDEServices, IOTAIDEThemingServices250, ThemingServices) and
     ThemingServices.IDEThemingEnabled then
  begin
    ThemingServices.RegisterFormClass(TCustomFormClass(ClassType));
    ThemeFixupControls(Self); // ApplyTheme + hotkey-control repair
  end;
  if StyleName = '' then
  begin
    // fallback if the theming services are unavailable: adopt the IDE-look
    // style by its 10.4/11 name (no-op when nothing matches)
    for sName in TStyleManager.StyleNames do
      if sName.StartsWith('Win10IDE_') then
        Self.StyleName := sName;
  end;
  {$ELSE}
  {$IF CompilerVersion >= 32.0}
  // 10.2.2/10.3 have no per-control styles; register the form class with the
  // IDE's theming engine and let it restyle the whole dialog
  if Supports(BorlandIDEServices, IOTAIDEThemingServices250, ThemingServices) and
     ThemingServices.IDEThemingEnabled then
  begin
    ThemingServices.RegisterFormClass(TCustomFormClass(ClassType));
    ThemeFixupControls(Self); // runs ApplyTheme + the manual color fixups
  end;
  {$IFDEF THEMEDEBUG}
  // temporary diagnostics: DDevExtensions_ThemeDebug.log in %TEMP%
  with TStringList.Create do
  try
    if FileExists(GetEnvironmentVariable('TEMP') + '\DDevExtensions_ThemeDebug.log') then
      LoadFromFile(GetEnvironmentVariable('TEMP') + '\DDevExtensions_ThemeDebug.log');
    Add(Format('%s Form=%s Supports250=%s', [DateTimeToStr(Now), ClassName,
      BoolToStr(Supports(BorlandIDEServices, IOTAIDEThemingServices250, ThemingServices), True)]));
    if ThemingServices <> nil then
      Add(Format('  Enabled=%s ActiveTheme="%s" Color=%d',
        [BoolToStr(ThemingServices.IDEThemingEnabled, True), ThemingServices.ActiveTheme, Integer(Color)]));
    SaveToFile(GetEnvironmentVariable('TEMP') + '\DDevExtensions_ThemeDebug.log');
  finally
    Free;
  end;
  {$ENDIF}
  {$IFEND}
  {$IFEND}
end;

{$IF (CompilerVersion >= 34.0) and (CompilerVersion < 37.0)}
type
  { On Delphi 10.4..12 the stock TEditStyleHook themes the hotkey control's
    non-client area (the border) but leaves the client (text) background at
    native white: the native msctls_hotkey32 never sends WM_CTLCOLOR, so the
    style hook's colour path (and any manual TControl.Color) is dead - a
    diagnostic build confirmed the hook runs but CN_CTLCOLOREDIT never arrives.
    Delphi 13 fixed this NOT in the style hook but by giving TCustomHotKey a
    TWinControlMessageHandler (THotKeyHandler) that paints the client itself on
    WM_PAINT. That infrastructure does not exist before D13, so this hook does
    the same WM_PAINT client paint (a direct port of D13's THotKeyHandler).
    D13 (>=37) already paints itself, so the hook is not compiled there. }
  TDDevHotKeyStyleHook = class(TEditStyleHook)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;

procedure TDDevHotKeyStyleHook.WndProc(var Message: TMessage);
const
  cColor: array[Boolean] of TStyleColor = (scEditDisabled, scEdit);
  cFont: array[Boolean] of TStyleFont = (sfEditBoxTextDisabled, sfEditBoxTextNormal);
var
  DC: HDC;
  PS: TPaintStruct;
  LCanvas: TCanvas;
  LText: string;
  LStyle: TCustomStyleServices;
begin
  // Port of D13 THotKeyHandler.HandleMessage: take over WM_PAINT and draw the
  // client with the IDE style's edit colours (the native control paints white).
  if (Message.Msg = WM_PAINT) and Control.IsCustomStyleActive and
     (seClient in Control.StyleElements) then
  begin
    DC := HDC(Message.WParam);
    LCanvas := TCanvas.Create;
    try
      if DC = 0 then
        LCanvas.Handle := BeginPaint(Handle, PS)
      else
        LCanvas.Handle := DC;
      LText := StringReplace(ShortCutToText(THotKey(Control).HotKey),
        '+', ' + ', [rfReplaceAll]);
      LStyle := StyleServices;
      LCanvas.Font := TControlAccess(Control).Font;
      LCanvas.Brush.Color := LStyle.GetStyleColor(cColor[Control.Enabled]);
      LCanvas.Font.Color := LStyle.GetStyleFontColor(cFont[Control.Enabled]);
      LCanvas.FillRect(Control.ClientRect); // whole client dark, then the text
      LCanvas.TextOut(2, 2, LText);
      if Control.Focused then
        SetCaretPos(LCanvas.TextWidth(LText) + 2, 1);
    finally
      LCanvas.Handle := 0;
      LCanvas.Free;
      if DC = 0 then
        EndPaint(Handle, PS);
    end;
    Handled := True;
    Exit;
  end;

  inherited WndProc(Message);
end;

procedure TFormBase.ThemeFixupControls(AParent: TWinControl);
var
  ThemingServices: IOTAIDEThemingServices250;
begin
  // 10.4+: option page frames are created after the dialog's ApplyIDETheme
  // ran; apply the IDE style to the late-created control tree as well (the
  // style engine and the registered hooks handle the control colors)
  if Supports(BorlandIDEServices, IOTAIDEThemingServices250, ThemingServices) and
     ThemingServices.IDEThemingEnabled then
    ThemingServices.ApplyTheme(AParent);
end;
{$IFEND}

{$IF CompilerVersion >= 37.0}
procedure TFormBase.ThemeFixupControls(AParent: TWinControl);
var
  ThemingServices: IOTAIDEThemingServices250;
begin
  // Delphi 13: the IDE theming (incl. the hotkey client) works out of the box
  if Supports(BorlandIDEServices, IOTAIDEThemingServices250, ThemingServices) and
     ThemingServices.IDEThemingEnabled then
    ThemingServices.ApplyTheme(AParent);
end;
{$IFEND}

{$IF (CompilerVersion >= 32.0) and (CompilerVersion < 34.0)}
type
  TTreeViewAccess = class(TCustomTreeView);

function GetIDEStyle(out Style: TCustomStyleServices): Boolean;
var
  ThemingServices: IOTAIDEThemingServices;
begin
  Style := nil;
  Result := Supports(BorlandIDEServices, IOTAIDEThemingServices, ThemingServices) and
    ThemingServices.IDEThemingEnabled;
  if Result then
  begin
    Style := ThemingServices.StyleServices;
    Result := Style <> nil;
  end;
end;

procedure TFormBase.ThemeTreeAdvancedCustomDrawItem(Sender: TCustomTreeView;
  Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage;
  var PaintImages, DefaultDraw: Boolean);
var
  Style: TCustomStyleServices;
  R: TRect;
begin
  { The tree control ignores custom draw text colors for the SELECTED item
    (both with and without the Explorer window theme), so the item is
    repainted here after the control's own item paint. }
  DefaultDraw := True;
  if (Stage = cdPostPaint) and (cdsSelected in State) and GetIDEStyle(Style) then
  begin
    R := Node.DisplayRect(True);
    Sender.Canvas.Brush.Style := bsSolid;
    Sender.Canvas.Brush.Color := Style.GetSystemColor(clHighlight);
    Sender.Canvas.FillRect(R);
    Sender.Canvas.Font.Color := Style.GetSystemColor(clHighlightText);
    Sender.Canvas.Brush.Style := bsClear;
    Sender.Canvas.TextOut(R.Left + 2,
      R.Top + (R.Bottom - R.Top - Sender.Canvas.TextHeight(Node.Text)) div 2, Node.Text);
    Sender.Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TFormBase.ThemeFixupControls(AParent: TWinControl);
var
  ThemingServices: IOTAIDEThemingServices;
  Style: TCustomStyleServices;

  procedure Walk(Parent: TWinControl);
  var
    I: Integer;
    C: TControl;
  begin
    for I := 0 to Parent.ControlCount - 1 do
    begin
      C := Parent.Controls[I];
      // ApplyTheme leaves controls that default to clWindow (and do not
      // inherit ParentColor) with a light client area.
      // THotKey is deliberately NOT recolored: the native hotkey control only
      // honors the background brush and keeps drawing black-on-white text.
      if (C is TCustomEdit) or (C is TCustomComboBox) or (C is TCustomListBox) or
         (C is TCustomListView) or (C is TCustomTreeView) then
      begin
        TControlAccess(C).Color := Style.GetSystemColor(clWindow);
        TControlAccess(C).Font.Color := Style.GetSystemColor(clWindowText);
      end
      // belt and braces for labels the engine's ApplyTheme leaves black;
      // link labels (hand cursor, e.g. the homepage URL) get the style's
      // hyperlink blue instead of plain window text
      else if (C is TCustomLabel) or (C is TCustomStaticText) then
      begin
        if C.Cursor = crHandPoint then
          TControlAccess(C).Font.Color := Style.GetSystemColor(clHotLight)
        else
          TControlAccess(C).Font.Color := Style.GetSystemColor(clWindowText);
      end;
      if C is TCustomTreeView then
      begin
        // classic selection (the Explorer theme paints its own selection
        // visuals under/around our post-paint rectangle)
        SetWindowTheme(TWinControl(C).Handle, '', '');
        if not Assigned(TTreeViewAccess(C).OnAdvancedCustomDrawItem) then
          TTreeViewAccess(C).OnAdvancedCustomDrawItem := ThemeTreeAdvancedCustomDrawItem;
      end;
      if C is TWinControl then
        Walk(TWinControl(C));
    end;
  end;

begin
  if not (Supports(BorlandIDEServices, IOTAIDEThemingServices, ThemingServices) and
          ThemingServices.IDEThemingEnabled) then
    Exit;
  Style := ThemingServices.StyleServices;
  if Style = nil then
    Exit;
  // the engine's recursive pass (labels, panels, the frame/form itself) -
  // option page frames are created after the dialog's own ApplyTheme ran
  ThemingServices.ApplyTheme(AParent);
  Walk(AParent);
end;
{$IFEND}

function TFormBase.ShowModal: Integer;
var
  HintClass: THintWindowClass;
  HintHidePause: Integer;
begin
  HintHidePause := Application.HintHidePause;
  HintClass := HintWindowClass;
  try
    HintWindowClass := THtHintWindow;
    Application.HintHidePause := 30000;
    Result := inherited ShowModal;
  finally
    Application.HintHidePause := HintHidePause;
    HintWindowClass := HintClass;
  end;
end;

{$IF (CompilerVersion >= 34.0) and (CompilerVersion < 37.0)}
initialization
  // Replace the stock hotkey style hook with our buffered-print variant. The
  // engine uses the last-registered hook for a class, so this takes precedence
  // over the VCL's own TEditStyleHook registration for these classes.
  TCustomStyleEngine.RegisterStyleHook(TCustomHotKey, TDDevHotKeyStyleHook);
  TCustomStyleEngine.RegisterStyleHook(THotKey, TDDevHotKeyStyleHook);
finalization
  TCustomStyleEngine.UnRegisterStyleHook(THotKey, TDDevHotKeyStyleHook);
  TCustomStyleEngine.UnRegisterStyleHook(TCustomHotKey, TDDevHotKeyStyleHook);
{$IFEND}

end.
 
