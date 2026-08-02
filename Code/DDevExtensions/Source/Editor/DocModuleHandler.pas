unit DocModuleHandler;

interface

uses
  Windows, SysUtils, Classes, ToolsAPI, Dialogs, Hooking, IDEHooks, ToolsAPIHelpers;

type
  TVirtualStream = class(TObject);

  TVirtualFileSystem = class
  private
    FFilter: IOTAFileFilter;
  public
    function GetFileStream(const FileName: string; Mode: Integer): TVirtualStream; virtual; abstract;
    function FileAge(const FileName: string): Longint; virtual; abstract;
    function RenameFile(const OldName, NewName: string): Boolean; virtual; abstract;
    function IsReadonly(const FileName: string): Boolean; virtual; abstract;
    function IsFileBased: Boolean; virtual; abstract;
    function DeleteFile(const FileName: string): Boolean; virtual; abstract;
    function FileExists(const FileName: string): Boolean; virtual; abstract;
    function GetTempFileName(const FileName: string): string; virtual; abstract;
    function GetBackupFileName(const FileName: string): string; virtual; abstract;
    function GetIDString: string; virtual; abstract;
    function GetFilter: IOTAFileFilter; virtual; abstract;
    //procedure SetFilter(const AFilter: IOTAFileFilter);
    //property Filter: IOTAFileFilter read GetFilter write SetFilter;
    property Filter: IOTAFileFilter read FFilter;
  end;

  TDocModule = class(TObject)
  public
    function IsDormant: Boolean;
  public
    function CheckFileDate: Boolean;
    function CanReloadFile: Boolean;
    function GetModified: Boolean;
    procedure ReloadFile;
    function GetFileName: string;
    function GetModuleName: string;
    function GetFormName: string;
    function HasForm: Boolean;
    function SwapSourceFormView: Boolean;
    function GetCanFree: Boolean;
    {$IF CompilerVersion >= 22.0} // XE+
    function CanFreeOrGoDormant(const DormantOk: Boolean): Boolean;
    {$IFEND}
    procedure GetDependentModules(List: TList);
    procedure GetModuleDependencies(List: TList);
    function GoDormant: Boolean;
    procedure ShowEditor(Activate: Boolean);
    procedure ShowEditorName(const FileName: string; Activate: Boolean);
    procedure Activate(IsExternalViewer: Boolean);
    procedure Modified;
    function GetFileSystem: TVirtualFileSystem;
    function GetCodeIDocModule: TInterfacedObject;

    property IsModified: Boolean read GetModified;
    property FileName: string read GetFileName;
    property FileSystem: TVirtualFileSystem read GetFileSystem;
    property CanFree: Boolean read GetCanFree;
  end;

  TEditorViewDataArray = Pointer;
  IFileAge = IInterface;
  TEditBuffer = class(TObject);
  IModuleUpdater = IInterface;
  IFormUpdater = IInterface;

  IDocStream = interface
    ['{B7B8F53F-2A84-4CDD-97D9-B7D9CDAC33F8}']
    function Read(var Buffer; Length: Int64): Int64;
    function Write(var Buffer; Length: Int64): Int64;
    function Seek(Offset: Int64; Origin: Integer): Int64;
    procedure SetSize(Size: Int64);
  end;

  IDatedStream = interface(IDocStream)
    ['{A8613563-3389-4BA7-9A8A-5A8FF324F317}']
    function GetModifyTime: Longint;
    procedure SetModifyTime(Time: Longint);
  end;

  IFile = interface
    ['{346E7BA0-D47E-11D3-BA96-0080C78ADCDB}']
    function FormFileOpen: IDocStream;
    function GetFileName: string;
    function GetTimeAtLoad: Longint;
    function GetModifyTime: Longint;
    function CheckFileDate: Boolean;
    procedure Rename(const NewFileName: string);
    procedure Save;

    property FileName: string read GetFileName;
    property TimeAtLoad: Longint read GetTimeAtLoad;
    property ModifyTime: Longint read GetModifyTime;
  end;

  IDesignerModule = interface
    ['{7ED7BF27-E349-11D3-AB4A-00C04FB17A72}']
    // ...
  end;

  IDesigner = interface
  end;

  IInternalPaletteItem = interface
  end;

  ICompInfo = interface
  end;

  TGetRootProc = procedure;

  TShowState = (ssNormal, ssMinimized, ssMaximized);
  TDesignerState = set of (dsVisible, dsIconic, dsZoomed);

  IRoot = interface(IFile)
    ['{76023428-77C4-4E10-B210-2DE6536C04E7}']
    procedure Close;
    procedure CreateComponent(Item: IInternalPaletteItem);
    procedure CreateComponentPos(Item: IInternalPaletteItem; X, Y: Integer);
    function FindCompClass(const CompName: string): string;
    {$IF CompilerVersion >= 23.0} // XE2+
    procedure FreezeProperties;
    {$IFEND}
    function GetAncestorName: string;
    function GetCompCount: Integer;
    procedure GetDependentRoots(Proc: TGetRootProc);
    function GetDesignClassName: string;
    procedure GetDependencies(Proc: TGetRootProc);
    function GetCompInfo(Index: Integer): ICompInfo;
    function GetModule: IDesignerModule;
    function GetCompName(Index: Integer): string;
    function GetCompType(Index: Integer): string;
    {$IF CompilerVersion >= 24.0} // XE3+
    function GetFormFamilyName: string;
    {$IFEND}
    function GetFileSystem: string;
    function GetRoot: TComponent;
    function GetRootName: string;
    procedure GetUnits(Proc: TGetStrProc);
    function GetState: TDesignerState;
    procedure Hide;
    procedure GoDormant;
    procedure RenameRootMethod(const CurName, NewName: string);
    function RenameComponent(const CurName, NewName: string): Boolean;
    procedure RemoveDependentLinks;
    procedure SetFileSystem(const FileSystem: string);
    procedure SetRootName(const AName: string);
    procedure SetSelection(const Name: string);
    procedure Show;
    procedure ShowAs(ShowState: TShowState);
    procedure ShowComponentHelp;
    function SpecialPropertyHelp(const Member: string; out HelpFile, Context: string; out HelpType: THelpType): Boolean;
    {$IF CompilerVersion >= 23.0} // XE2+
    procedure ThawProperties;
    {$IFEND}
    function GetDesigner: IDesigner;
    function GetFormEditor: IOTAFormEditor;
    property Root: TComponent read GetRoot;
    property Module: IDesignerModule read GetModule;
  end;

  IBaseComponentDesigner = interface
    ['{6EBEF997-E986-41B3-8E70-3112112F1AB7}']
    function CreateRoot(const AModule: IDesignerModule; const AFileName: string;
      Existing: Boolean; const ARootName, AAncestor,
      AFileSystem: string): IRoot;
    {function CreateFromStream(const AModule: IDesignerModule; const AFileName,
      AFileSystem: string; const Stream: IDatedStream): IRoot;
    function CreateNewRoot(const AModule: IDesignerModule;
      const AFileName: string; const Creator: IUnknown): IRoot;
    function GetExtension: string;}
  end;

  TSourceModule = class(TDocModule)
  end;

  TPascalCodeMgrModHandler = class(TNotifierObject, IDesignerModule)
  protected
    FNotifierIndex: Integer;
    FSourceModulesFormName: string;
    FSourceModules: IInterfaceList;
    FEditorViewData: TEditorViewDataArray;
    FAdditionalFilesData: TEditorViewDataArray;
    {$IF CompilerVersion >= 27.0} // XE6+
    FDesignerViewStreams: TEditorViewDataArray;
    {$IFEND}
    FTempFile: IFileAge;
    {$IF CompilerVersion >= 22.0} // XE+
    FReloadingFile: Boolean;
    FAncestorNotifier: TModuleNotifierObject;
    {$IFEND}
  protected
    FEditBuffer: TEditBuffer;
    FDesigner: IBaseComponentDesigner;
    FHasFormChecked: Boolean;
    FModuleUpdater: IModuleUpdater;
    FIsFormModified: Boolean;
    {$IF CompilerVersion >= 21.0} // Delphi 2010+
    FWasFormModifiedAtLoading: Boolean;
    {$IFEND}
    FFormIsTopmost: Boolean;
    FAncestorModule: TSourceModule;
    FSourceModule: TSourceModule;
    FOldFormFileName: string;
    FFormName: string;
    FFormClassName: string;
    FAncestorClassName: string;
    FUnitNames: TStrings;
    FInQI: Boolean;
    FDependList: TList;
    FForm: IRoot;
//    FFormUpdater: IFormUpdater;
//    FSaveFileName: string;
//    FSquelchModifiedNotification: Boolean;
//    FOldBaseFileName: string;
  public
    procedure ResurrectForm;
    procedure ReloadFile;
  end;

var
  ModuleListP: ^TList;

function InitDocModuleHandler: Boolean;
function IsEmbeddedDesigner: Boolean;

implementation

{$IF CompilerVersion >= 21.0}
uses
  Rtti;
{$IFEND}

var
  DocModuleIsDormantOffset: Integer;

{$IFDEF CPUX86}
procedure Docmodul_ModuleListAddr;
  external coreide_bpl name '@Docmodul@ModuleList';
{$ENDIF}
{$IFDEF CPUX64}
procedure Docmodul_ModuleListAddr;
  external coreide_bpl name '_ZN8Docmodul10ModuleListE';
{$ENDIF}

{$IFDEF CPUX64}
procedure EnvironmentOptionsAddr;
  external coreide_bpl name '_ZN10Envoptions18EnvironmentOptionsE';
{$ENDIF}

{$IF CompilerVersion >= 25.0} // XE4+
function IsEmbeddedDesigner: Boolean;
begin
  Result := True;
end;
{$ELSE}
procedure EnvironmentOptionsAddr;
  external coreide_bpl name '@Envoptions@EnvironmentOptions';

function IsEmbeddedDesigner: Boolean;
const
  sEmbeddedDesigner = 'EmbeddedDesigner';
var
  EmbeddedDesignerProp: TPropField;
begin
  EmbeddedDesignerProp := TPropField( (TObject(PPointer(GetActualAddr(@EnvironmentOptionsAddr))^) as TComponent).FindComponent(sEmbeddedDesigner));
  if EmbeddedDesignerProp <> nil then
    Result := EmbeddedDesignerProp.Value
  else
    Result := True;
end;
{$IFEND}

type
  TDocModuleVirtMethodType = (
    mCheckFileDate,
    mCanReloadFile,
    mGetModified,
    mReloadFile,
    mGetFileName,
    mGetModuleName,
    mHasForm,
    mGetFormName,
    mSwapSourceFormView,
    mGetDependentModules,
    mGetModuleDependencies,
    mGoDormant,
    mShowEditor,
    mShowEditorName,
    mGetFileSystem,
    mActivate,
    mModified
  );

  TDocModuleVirtMethodRec = record
  public
    Import: PAnsiChar;
    VmtOffset: Integer;
    Addr: Pointer;
    function CallBoolean(Instance: TDocModule): Boolean;
    function CallString(Instance: TDocModule): string;
    function CallObject(Instance: TDocModule): TObject;
    procedure Call(Instance: TDocModule);
    procedure Call1(Instance: TDocModule; P1: Pointer);
    procedure Call2(Instance: TDocModule; P1, P2: Pointer);
  end;

{$J+}
const
  {$IFDEF CPUX86}
  DocModuleVirtMethods: array[TDocModuleVirtMethodType] of TDocModuleVirtMethodRec = (
    (Import: '@Docmodul@TDocModule@CheckFileDate$qqrv'),
    (Import: '@Docmodul@TDocModule@CanReloadFile$qqrv'),
    (Import: '@Docmodul@TDocModule@GetModified$qqrv'),
    (Import: '@Docmodul@TDocModule@ReloadFile$qqrv'),
    (Import: '@Docmodul@TDocModule@GetFileName$qqrv'),
    (Import: '@Docmodul@TDocModule@GetModuleName$qqrv'),
    (Import: '@Docmodul@TDocModule@HasForm$qqrv'),
    (Import: '@Docmodul@TDocModule@GetFormName$qqrv'),
    (Import: '@Docmodul@TDocModule@SwapSourceFormView$qqrv'),
    (Import: '@Docmodul@TDocModule@GetDependentModules$qqrp' + System_Classes_TList),
    (Import: '@Docmodul@TDocModule@GetModuleDependencies$qqrp' + System_Classes_TList),
    (Import: '@Docmodul@TDocModule@GoDormant$qqrv'),
    (Import: '@Docmodul@TDocModule@ShowEditor$qqro'),
    (Import: '@Docmodul@TDocModule@ShowEditorName$qqrx20System@UnicodeStringo'),
    (Import: '@Docmodul@TDocModule@GetFileSystem$qqrv'),
    (Import: '@Docmodul@TDocModule@Activate$qqro'),
    (Import: '@Docmodul@TDocModule@Modified$qqrv')
  );
  {$ENDIF CPUX86}
  {$IFDEF CPUX64}
  DocModuleVirtMethods: array[TDocModuleVirtMethodType] of TDocModuleVirtMethodRec = (
    (Import: '_ZN8Docmodul10TDocModule13CheckFileDateEv'),
    (Import: '_ZN8Docmodul10TDocModule13CanReloadFileEv'),
    (Import: '_ZN8Docmodul10TDocModule11GetModifiedEv'),
    (Import: '_ZN8Docmodul10TDocModule10ReloadFileEv'),
    (Import: '_ZN8Docmodul10TDocModule11GetFileNameEv'),
    (Import: '_ZN8Docmodul10TDocModule13GetModuleNameEv'),
    (Import: '_ZN8Docmodul10TDocModule7HasFormEv'),
    (Import: '_ZN8Docmodul10TDocModule11GetFormNameEv'),
    (Import: '_ZN8Docmodul10TDocModule18SwapSourceFormViewEv'),
    (Import: '_ZN8Docmodul10TDocModule19GetDependentModulesEPN6System7Classes5TListE'),
    (Import: '_ZN8Docmodul10TDocModule21GetModuleDependenciesEPN6System7Classes5TListE'),
    (Import: '_ZN8Docmodul10TDocModule9GoDormantEv'),
    (Import: '_ZN8Docmodul10TDocModule10ShowEditorEb'),
    (Import: '_ZN8Docmodul10TDocModule14ShowEditorNameEN6System13UnicodeStringEb'),
    (Import: '_ZN8Docmodul10TDocModule13GetFileSystemEv'),
    (Import: '_ZN8Docmodul10TDocModule8ActivateEb'),
    (Import: '_ZN8Docmodul10TDocModule8ModifiedEv')
  );
  {$ENDIF CPUX64}
{$J-}

{ TPascalCodeMgrModHandler }

{$IFDEF CPUX86}
procedure ClassTPascalCodeMgrModHandler;
  external delphicoreide_bpl name '@Delphimodule@TPascalCodeMgrModHandler@';
{$ENDIF}
{$IFDEF CPUX64}
procedure ClassTPascalCodeMgrModHandler;
  external delphicoreide_bpl name '_ZTVN12Delphimodule24TPascalCodeMgrModHandlerE';
{$ENDIF}

{$IFDEF CPUX86}
procedure TPascalCodeMgrModHandler.ResurrectForm;
  external delphicoreide_bpl name '@Delphimodule@TPascalCodeMgrModHandler@ResurrectForm$qqrv';
{$ENDIF}
{$IFDEF CPUX64}
procedure TPascalCodeMgrModHandler.ResurrectForm;
  external delphicoreide_bpl name '_ZN12Delphimodule24TPascalCodeMgrModHandler13ResurrectFormEv';
{$ENDIF}

{$IFDEF CPUX86}
procedure TPascalCodeMgrModHandler.ReloadFile;
  external delphicoreide_bpl name '@Delphimodule@TPascalCodeMgrModHandler@ReloadFile$qqrv';
{$ENDIF}
{$IFDEF CPUX64}
procedure TPascalCodeMgrModHandler.ReloadFile;
  external delphicoreide_bpl name '_ZN12Delphimodule24TPascalCodeMgrModHandler10ReloadFileEv';
{$ENDIF}

{ TDocModule }

{$IFDEF CPUX86}
procedure ClassTDocModule;
  external coreide_bpl name '@Docmodul@TDocModule@';
{$ENDIF}
{$IFDEF CPUX64}
procedure ClassTDocModule;
  external coreide_bpl name '_ZTVN8Docmodul10TDocModuleE';
{$ENDIF}

{$IFDEF CPUX86}
procedure TDocModule_GoDormant;
  external coreide_bpl name '@Docmodul@TDocModule@GoDormant$qqrv';
{$ENDIF}
{$IFDEF CPUX64}
procedure TDocModule_GoDormant;
  external coreide_bpl name '_ZN8Docmodul10TDocModule9GoDormantEv';
{$ENDIF}

{$IFDEF CPUX86}
function TDocModule.GetCanFree: Boolean;
  external coreide_bpl name '@Docmodul@TDocModule@GetCanFree$qqrv';
{$ENDIF}
{$IFDEF CPUX64}
function TDocModule.GetCanFree: Boolean;
  external coreide_bpl name '_ZN8Docmodul10TDocModule10GetCanFreeEv';
{$ENDIF}

{$IF (CompilerVersion >= 22.0) and Defined(CPUX86)} // XE+
function TDocModule.CanFreeOrGoDormant(const DormantOk: Boolean): Boolean;
  external coreide_bpl name '@Docmodul@TDocModule@CanFreeOrGoDormant$qqrxo';
{$IFEND}
{$IFDEF CPUX64}
function TDocModule.CanFreeOrGoDormant(const DormantOk: Boolean): Boolean;
  external coreide_bpl name '_ZN8Docmodul10TDocModule18CanFreeOrGoDormantEb';
{$ENDIF}

{$IFDEF CPUX86}
function TDocModule.GetCodeIDocModule: TInterfacedObject;
  external coreide_bpl name '@Docmodul@TDocModule@GetCodeIDocModule$qqrv';
{$ENDIF}
{$IFDEF CPUX64}
function TDocModule.GetCodeIDocModule: TInterfacedObject;
  external coreide_bpl name '_ZN8Docmodul10TDocModule17GetCodeIDocModuleEv';
{$ENDIF}

function TDocModule.IsDormant: Boolean;
begin
  Result := PBoolean(PByte(Self) + DocModuleIsDormantOffset)^;
end;

function TDocModule.CanReloadFile: Boolean;
begin
  Result := DocModuleVirtMethods[mCanReloadFile].CallBoolean(Self);
end;

function TDocModule.CheckFileDate: Boolean;
begin
  Result := DocModuleVirtMethods[mCheckFileDate].CallBoolean(Self);
end;

function TDocModule.GetFileName: string;
begin
  Result := DocModuleVirtMethods[mGetFileName].CallString(Self);
end;

function TDocModule.GetFormName: string;
begin
  Result := DocModuleVirtMethods[mGetFormName].CallString(Self);
end;

function TDocModule.GetModified: Boolean;
begin
  Result := DocModuleVirtMethods[mGetModified].CallBoolean(Self);
end;

function TDocModule.GetModuleName: string;
begin
  Result := DocModuleVirtMethods[mGetModuleName].CallString(Self);
end;

function TDocModule.HasForm: Boolean;
begin
  Result := DocModuleVirtMethods[mHasForm].CallBoolean(Self);
end;

procedure TDocModule.ReloadFile;
begin
  DocModuleVirtMethods[mReloadFile].Call(Self);
end;

function TDocModule.SwapSourceFormView: Boolean;
begin
  Result := DocModuleVirtMethods[mSwapSourceFormView].CallBoolean(Self);
end;

procedure TDocModule.GetDependentModules(List: TList);
begin
  DocModuleVirtMethods[mGetDependentModules].Call1(Self, List);
end;

procedure TDocModule.GetModuleDependencies(List: TList);
begin
  DocModuleVirtMethods[mGetModuleDependencies].Call1(Self, List);
end;

function TDocModule.GoDormant: Boolean;
begin
  Result := DocModuleVirtMethods[mGoDormant].CallBoolean(Self);
end;

procedure TDocModule.ShowEditor(Activate: Boolean);
begin
  DocModuleVirtMethods[mShowEditor].Call1(Self, Pointer(Activate));
end;

procedure TDocModule.ShowEditorName(const FileName: string; Activate: Boolean);
begin
  DocModuleVirtMethods[mShowEditorName].Call2(Self, Pointer(FileName), Pointer(Activate));
end;

procedure TDocModule.Activate(IsExternalViewer: Boolean);
begin
  DocModuleVirtMethods[mActivate].Call1(Self, Pointer(IsExternalViewer));
end;

procedure TDocModule.Modified;
begin
  DocModuleVirtMethods[mModified].Call(Self);
end;

function TDocModule.GetFileSystem: TVirtualFileSystem;
begin
  Result := TVirtualFileSystem(DocModuleVirtMethods[mGetFileSystem].CallObject(Self));
end;

{ TDocModuleVirtMethodRec }

{$IFDEF CPUX86}
function TDocModuleVirtMethodRec.CallBoolean(Instance: TDocModule): Boolean;
asm
  jmp TDocModuleVirtMethodRec.Call
end;

function TDocModuleVirtMethodRec.CallString(Instance: TDocModule): string;
asm
  jmp TDocModuleVirtMethodRec.Call1 // String is passed as second parameter (EDX)
end;

function TDocModuleVirtMethodRec.CallObject(Instance: TDocModule): TObject;
asm
  jmp TDocModuleVirtMethodRec.Call
end;

procedure TDocModuleVirtMethodRec.Call(Instance: TDocModule);
asm
  xchg eax, edx
  mov edx, [edx].TDocModuleVirtMethodRec.&VmtOffset
  mov ecx, [eax]
  jmp [ecx+edx]
end;

procedure TDocModuleVirtMethodRec.Call1(Instance: TDocModule; P1: Pointer);
asm
  push ebx
  mov ebx, [edx]
  add ebx, [eax].TDocModuleVirtMethodRec.&VmtOffset

  mov eax, edx
  mov edx, ecx
  call [ebx]

  pop ebx
end;

procedure TDocModuleVirtMethodRec.Call2(Instance: TDocModule; P1, P2: Pointer);
asm
  push ebx
  mov ebx, [edx]
  add ebx, [eax].TDocModuleVirtMethodRec.&VmtOffset

  mov eax, edx
  mov edx, ecx
  mov ecx, [esp+$08]
  call [ebx]

  pop ebx
end;
{$ENDIF CPUX86}

{$IFDEF CPUX64}
function TDocModuleVirtMethodRec.CallBoolean(Instance: TDocModule): Boolean;
asm
  jmp TDocModuleVirtMethodRec.Call
end;

function TDocModuleVirtMethodRec.CallString(Instance: TDocModule): string;
asm
  jmp TDocModuleVirtMethodRec.Call1 // String result is passed as hidden last parameter
end;

function TDocModuleVirtMethodRec.CallObject(Instance: TDocModule): TObject;
asm
  jmp TDocModuleVirtMethodRec.Call
end;

procedure TDocModuleVirtMethodRec.Call(Instance: TDocModule);
asm
  // RCX = Self (rec), RDX = Instance
  mov eax, [rcx].TDocModuleVirtMethodRec.&VmtOffset  // RAX = VmtOffset (zero-extended)
  mov rcx, rdx         // RCX = Instance (Self for target method)
  mov r9, [rcx]        // R9 = VMT pointer
  jmp [r9+rax]         // jump to VMT[VmtOffset]
end;

procedure TDocModuleVirtMethodRec.Call1(Instance: TDocModule; P1: Pointer);
asm
  // RCX = Self (rec), RDX = Instance, R8 = P1
  mov eax, [rcx].TDocModuleVirtMethodRec.&VmtOffset  // RAX = VmtOffset (zero-extended)
  mov rcx, rdx         // RCX = Instance (Self for target method)
  mov rdx, r8          // RDX = P1 (second param for target method)
  mov r9, [rcx]        // R9 = VMT pointer
  jmp [r9+rax]         // jump to VMT[VmtOffset]
end;

procedure TDocModuleVirtMethodRec.Call2(Instance: TDocModule; P1, P2: Pointer);
asm
  // RCX = Self (rec), RDX = Instance, R8 = P1, R9 = P2
  mov eax, [rcx].TDocModuleVirtMethodRec.&VmtOffset  // RAX = VmtOffset (zero-extended)
  mov rcx, rdx         // RCX = Instance (Self for target method)
  mov rdx, r8          // RDX = P1 (second param for target method)
  mov r8, r9           // R8 = P2 (third param for target method)
  mov r9, [rcx]        // R9 = VMT pointer
  jmp [r9+rax]         // jump to VMT[VmtOffset]
end;
{$ENDIF CPUX64}


function InitDocModuleHandler: Boolean;
{$IFDEF CPUX86}
const
  GoDormantBytes: array[0..12] of SmallInt = (
    $B3, $01,            // mov bl,$01                  //  0
    $80, $7E, -1, $00,   // cmp byte ptr [esi+$49],$00  //  2 // IsDormantOffset
    $75, -1,             // jnz $2084517a               //  6
    $8D, $55, $FC,       // lea edx,[ebp-$04]           //  8
    $8B, $C6             // mov eax,esi                 // 11
  );
{$ENDIF CPUX86}
var
  DocModuleClass: TClass;
  CoreIdeLib: THandle;
  MethTyp: TDocModuleVirtMethodType;
  VmtIndex: Integer;
  P: PByte;
  {$IF CompilerVersion >= 21.0}
  PascalCodeMgrModHandlerClass: TClass;
  Context: TRttiContext;
  Typ: TRttiType;
  Fld: TRttiField;
  {$IFEND}
begin
  Result := False;

  ModuleListP := GetActualAddr(@Docmodul_ModuleListAddr);
  DocModuleClass := TClass(GetActualAddr(@ClassTDocModule));

  {$IF CompilerVersion >= 21.0}
  PascalCodeMgrModHandlerClass := TClass(GetActualAddr(@ClassTPascalCodeMgrModHandler));
  // (Un)Fortunately there are no updates for older Delphi versions, only for the newest. So we
  // can assume that older versions without RichRTTI never change.
  Context := TRttiContext.Create;
  try
    Typ := Context.GetType(PascalCodeMgrModHandlerClass);
    Fld := nil;
    if Typ <> nil then
    begin
      {AllocConsole;
      for Fld in Typ.GetFields do
        WriteLn(Fld.ToString);}

      Fld := Typ.GetField('FForm');
      if (Fld <> nil) and (Fld.Offset <> NativeInt(@TPascalCodeMgrModHandler(nil).FForm)) then
        Fld := nil;
    end;
    if Fld = nil then
    begin
      MessageDlg('DDevExtensions: TPascalCodeMgrModHandler InstanceSize doesn''t match', mtError, [mbOk], 0);
      Exit;
    end;
  finally
    Context.Free;
  end;
  {$IFEND}

  CoreIdeLib := GetModuleHandle(coreide_bpl);
  for MethTyp := Low(DocModuleVirtMethods) to High(DocModuleVirtMethods) do
  begin
    DocModuleVirtMethods[MethTyp].Addr := GetProcAddress(CoreIdeLib, DocModuleVirtMethods[MethTyp].Import);
    if DocModuleVirtMethods[MethTyp].Addr = nil then
    begin
      MessageDlg(Format('DDevExtensions: Import symbol "%s" not found in "%s"', [AnsiString(DocModuleVirtMethods[MethTyp].Import), coreide_bpl]), mtError, [mbOk], 0);
      Exit;
    end;
  end;

  for VmtIndex := 0 to GetVirtualMethodCount(DocModuleClass) - 1 do
    for MethTyp := Low(DocModuleVirtMethods) to High(DocModuleVirtMethods) do
      if GetVirtualMethod(DocModuleClass, VmtIndex) = DocModuleVirtMethods[MethTyp].Addr then
        DocModuleVirtMethods[MethTyp].VmtOffset := VmtIndex * SizeOf(Pointer);

  for MethTyp := Low(DocModuleVirtMethods) to High(DocModuleVirtMethods) do
  begin
    if DocModuleVirtMethods[MethTyp].VmtOffset = 0 then
    begin
      MessageDlg('DDevExtensions: Error getting VMT offsets for TDocModule', mtError, [mbOk], 0);
      Exit;
    end;
  end;

  {$IFDEF CPUX86}
  P := FindMethodPtr(THandle(GetActualAddr(@TDocModule_GoDormant)), GoDormantBytes, $40);
  if P = nil then
  begin
    MessageDlg('DDevExtensions: Error finding TDocModule.IsDormant', mtError, [mbOk], 0);
    Exit;
  end;
  DocModuleIsDormantOffset := P[4];
  {$ELSE}
  // Win64: Scan GoDormant machine code for "cmp byte ptr [reg+disp8], 0" to find IsDormant offset.
  // On x64, Delphi saves Self (RCX) to a register and then does: cmp byte ptr [reg+offset], 0
  // Encoding: $80 ModR/M(01_111_rrr) disp8 $00  or with REX prefix
  begin
    var GoDormantAddr: PByte := PByte(GetActualAddr(@TDocModule_GoDormant));
    var FoundOffset: Boolean := False;
    var I: Integer;
    var ScanByte: Byte;
    for I := 0 to 127 do
    begin
      // Look for: $80 $7x offset $00 (cmp byte ptr [reg+disp8], 0)
      // ModR/M = 01_111_rrr where rrr = register (rcx=1, rbx=3, rsi=6, etc.)
      // So ModR/M range: $79..$7F (excluding $7C which needs SIB)
      ScanByte := GoDormantAddr[I];
      if (ScanByte = $80) and (I + 3 <= 127) then
      begin
        var ModRM: Byte := GoDormantAddr[I + 1];
        // mod=01, reg=111(/7=cmp), rm != 100(SIB)
        if ((ModRM and $F8) = $78) and ((ModRM and $07) <> $04) then
        begin
          if GoDormantAddr[I + 3] = $00 then // imm8 = 0
          begin
            DocModuleIsDormantOffset := GoDormantAddr[I + 2]; // disp8
            FoundOffset := True;
            Break;
          end;
        end;
      end;
      // Also check with REX prefix (40-4F): REX $80 $7x offset $00
      if (ScanByte >= $40) and (ScanByte <= $4F) and (I + 4 <= 127) then
      begin
        if GoDormantAddr[I + 1] = $80 then
        begin
          var ModRM: Byte := GoDormantAddr[I + 2];
          if ((ModRM and $F8) = $78) and ((ModRM and $07) <> $04) then
          begin
            if GoDormantAddr[I + 4] = $00 then
            begin
              DocModuleIsDormantOffset := GoDormantAddr[I + 3];
              FoundOffset := True;
              Break;
            end;
          end;
        end;
      end;
    end;
    if not FoundOffset then
    begin
      MessageDlg('DDevExtensions: Error finding TDocModule.IsDormant offset in GoDormant x64 code', mtError, [mbOk], 0);
      Exit;
    end;
  end;
  {$ENDIF}


  Result := True;
end;

end.
