{******************************************************************************}
{*                                                                            *}
{* DDevExtensions                                                             *}
{*                                                                            *}
{* (C) 2006 Andreas Hausladen                                                 *}
{*                                                                            *}
{******************************************************************************}

unit ProjectMgrShortCuts;

{$I ..\DelphiExtension.inc}

interface

{
  Adds Ctrl+Up / Ctrl+Down shortcuts to the Project Manager tree that move the
  selected project earlier / later in the build order (the "Build Sooner" /
  "Build Later" local-menu commands). Pre-2010 IDEs only - RAD Studio 2010+
  rebuilt the Project Manager and provides this itself.

  Re-created for the D7 port from the old (unpublished) v2.x line. The
  TProjectManagerForm.FormShow hook symbol and the TProjectManager.BuildSooner/
  BuildLater method symbols were recovered from coreide70.bpl. The two menu
  items are identified by their OnClick handler pointing at those methods
  (their component names are derived from the localized caption, so name
  matching would break on non-German IDEs).
}

procedure InitPlugin(Unload: Boolean);

implementation

{$IF CompilerVersion = 15.0} // Delphi 7 only (verified symbols)

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Menus,
  IDEHooks, Hooking;

const
  // all in coreide70.bpl
  FormShowSymbol = '@Projectfrm@TProjectManagerForm@FormShow$qqrp14System@TObject';
  BuildSoonerSymbol = '@Projectmgr@TProjectManager@BuildSooner$qqrp14System@TObject';
  BuildLaterSymbol = '@Projectmgr@TProjectManager@BuildLater$qqrp14System@TObject';
  sProjectTree = 'ProjectTree';

type
  { Subclasses the Project Manager tree's WindowProc to catch Ctrl+Up/Down. }
  TTreeKeyHook = class(TObject)
  private
    FForm: TCustomForm;
    FTree: TWinControl;
    FOrgWndProc: TWndMethod;
    procedure WndProc(var Message: TMessage);
  public
    constructor Create(AForm: TCustomForm; ATree: TWinControl);
    destructor Destroy; override;
  end;

var
  FormShowHook: TRedirectCode;
  Hook: TTreeKeyHook;
  BuildSoonerProc: Pointer;
  BuildLaterProc: Pointer;

function ItemInvokes(Item: TMenuItem; Proc: Pointer): Boolean;
var
  M: TMethod;
begin
  Result := False;
  if not Assigned(Item.OnClick) then
    Exit;
  M := TMethod(Item.OnClick);
  Result := GetActualAddr(M.Code) = GetActualAddr(Proc);
end;

function FindItemByProc(Item: TMenuItem; Proc: Pointer): TMenuItem;
var
  I: Integer;
begin
  for I := 0 to Item.Count - 1 do
  begin
    if ItemInvokes(Item[I], Proc) then
    begin
      Result := Item[I];
      Exit;
    end;
    Result := FindItemByProc(Item[I], Proc);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

{ Triggers the "Build Sooner"/"Build Later" command (identified by its OnClick
  handler) from the Project Manager's local menu. The menu's OnPopup is fired
  first so its command target and Enabled states match the current selection -
  the IDE only refreshes those when the menu actually pops up, so without this
  a second key press would act on a stale target / find the item disabled. }
function TriggerBuildOrder(Form: TCustomForm; Sooner: Boolean): Boolean;
var
  Proc: Pointer;
  Item: TMenuItem;
  Menu: TPopupMenu;
  I: Integer;
  C: TComponent;
begin
  Result := False;
  if Sooner then
    Proc := BuildSoonerProc
  else
    Proc := BuildLaterProc;
  if Proc = nil then
    Exit;

  { locate the popup menu that carries the command }
  Menu := nil;
  for I := 0 to Form.ComponentCount - 1 do
  begin
    C := Form.Components[I];
    if (C is TPopupMenu) and (FindItemByProc(TPopupMenu(C).Items, Proc) <> nil) then
    begin
      Menu := TPopupMenu(C);
      Break;
    end;
  end;
  if Menu = nil then
    Exit;

  { refresh it for the current selection, then re-find (items may be rebuilt) }
  if Assigned(Menu.OnPopup) then
    try
      Menu.OnPopup(Menu);
    except
    end;

  Item := FindItemByProc(Menu.Items, Proc);
  if (Item <> nil) and Item.Enabled then
  begin
    Item.Click;
    Result := True; // acted -> swallow the key
  end;
end;

{ TTreeKeyHook }

constructor TTreeKeyHook.Create(AForm: TCustomForm; ATree: TWinControl);
begin
  inherited Create;
  FForm := AForm;
  FTree := ATree;
  FOrgWndProc := ATree.WindowProc;
  ATree.WindowProc := WndProc;
end;

destructor TTreeKeyHook.Destroy;
begin
  if (FTree <> nil) and Assigned(FOrgWndProc) then
    FTree.WindowProc := FOrgWndProc;
  inherited Destroy;
end;

procedure TTreeKeyHook.WndProc(var Message: TMessage);
begin
  if (Message.Msg = WM_KEYDOWN) and
     ((Message.WParam = VK_UP) or (Message.WParam = VK_DOWN)) and
     (GetKeyState(VK_CONTROL) < 0) and
     (GetKeyState(VK_SHIFT) >= 0) and (GetKeyState(VK_MENU) >= 0) then
  begin
    // Up = build sooner. Only swallow the key if we actually acted, so plain
    // tree behavior is preserved when the command is unavailable.
    if TriggerBuildOrder(FForm, Message.WParam = VK_UP) then
    begin
      Message.Result := 0;
      Exit;
    end;
  end;
  FOrgWndProc(Message);
end;

procedure WireProjectManager(Form: TCustomForm);
var
  Tree: TComponent;
begin
  Tree := Form.FindComponent(sProjectTree);
  if not (Tree is TWinControl) then
    Exit;
  { PM form is created once and lives for the IDE session; re-wire only if the
    tree instance changed (defensive - normally it does not). }
  if (Hook <> nil) and (Hook.FTree = Tree) then
    Exit;
  FreeAndNil(Hook);
  Hook := TTreeKeyHook.Create(Form, TWinControl(Tree));
end;

procedure Hook_FormShow(Instance: TObject; Sender: TObject);
type
  TFormShowProc = procedure(Instance: TObject; Sender: TObject);
begin
  UnhookFunction(FormShowHook);
  try
    TFormShowProc(FormShowHook.RealProc)(Instance, Sender);
    if Instance is TCustomForm then
      WireProjectManager(TCustomForm(Instance));
  finally
    RehookFunction(@Hook_FormShow, FormShowHook);
  end;
end;

procedure InitPlugin(Unload: Boolean);
var
  CoreIde: HMODULE;
begin
  if not Unload then
  begin
    CoreIde := GetModuleHandle(PChar(coreide_bpl));
    BuildSoonerProc := GetProcAddress(CoreIde, PAnsiChar(BuildSoonerSymbol));
    BuildLaterProc := GetProcAddress(CoreIde, PAnsiChar(BuildLaterSymbol));
    HookFunction(coreide_bpl, FormShowSymbol, @Hook_FormShow, FormShowHook);
  end
  else
  begin
    UnhookFunction(FormShowHook);
    FreeAndNil(Hook);
  end;
end;

{$ELSE}

procedure InitPlugin(Unload: Boolean);
begin
  // RAD Studio 2010+ rebuilt the Project Manager and provides build-order
  // shortcuts itself; nothing to do here.
end;

{$IFEND}

end.
