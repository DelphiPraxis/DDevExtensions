{
  TetzkatLipHoka 2015-2025

  uTLH: FileFormatsList
  Last updated: 05/24/2025

  DDevExtensions note: renamed from uTLH.FileFormatsList to FileFormatsListHack
  (Delphi 7 does not accept dotted unit names). Gives access to the VCL's
  private global TFileFormatsList (TPicture's registered graphic formats) by
  disassembling the call to the internal GetFileFormats function that both
  TPicture.RegisterFileFormat and RegisterFileFormatRes start with.
}

unit FileFormatsListHack;

interface

uses 
  Classes, Contnrs, Graphics;

type
  // from VCL.Graphics
  TFileFormat = record
    GraphicClass: TGraphicClass;
    Extension: string;
    Description: string;
    DescResID: Integer;
  end;
  PFileFormat = ^TFileFormat;

  TFileFormatsListHack = class( TList )
  private
    function  Get( Index: Integer ) : PFileFormat; reintroduce;
    procedure Put( Index: Integer; Item: PFileFormat ); reintroduce;
  public
//    constructor Create;
//    destructor Destroy; override;
    procedure Add( const Ext, Desc: String; DescID: Integer; AClass: TGraphicClass );
    function  FindExt( Ext: string ): TGraphicClass;
    function  FindClassName( const ClassName: string ): TGraphicClass;
    procedure Remove( AClass: TGraphicClass );
    procedure RemoveExactClass( AClass: TGraphicClass ); // = only, no InheritsFrom
    procedure RemoveByName( ClassName : string );
    procedure RemoveByExt( Ext : string );
    procedure RemoveByDescription( Description : string );
    procedure BuildFilterStrings( GraphicClass: TGraphicClass; var Descriptions, Filters: string );

    procedure ListExtensions( List: TStrings ); // Extracts the file extension + the description;
    procedure ListClassNames( List: TStrings ); // This returns the list of TGraphicClass.ClassName registered
    procedure ListClasses( List: TClassList ); // This returns the list of TGraphicClass registered
    property  Items[Index: Integer]: PFileFormat read Get write Put; default;
  end;
  TGetFileFormats = function : TFileFormatsListHack; // TList;
var
  GetFileFormats : TGetFileFormats = nil;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
implementation

uses
  SysUtils, Consts;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
{$IF CompilerVersion <= 20}
type
  NativeUInt = Cardinal;
{$IFEND}
{$IF NOT Declared( PNativeUInt )}
type
  PNativeUInt = ^NativeUInt;  
{$IFEND}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
(*
constructor TFileFormatsListHack.Create;
begin
  inherited Create;
  Add('wmf', SVMetafiles, 0, TMetafile);
  Add('emf', SVEnhMetafiles, 0, TMetafile);
  Add('ico', SVIcons, 0, TIcon);
  Add('bmp', SVBitmaps, 0, TBitmap);
end;

destructor TFileFormatsListHack.Destroy;
var
  I: Integer;
begin
  for I := 0 to Count-1 do
    Dispose(PFileFormat(Items[I]));
  inherited Destroy;
end;
*)

procedure TFileFormatsListHack.Add( const Ext, Desc: String; DescID: Integer; AClass: TGraphicClass );
var
  NewRec: PFileFormat;
begin
  New( NewRec );
  NewRec^.Extension    := AnsiLowerCase( Ext );
  NewRec^.GraphicClass := AClass;
  NewRec^.Description  := Desc;
  NewRec^.DescResID    := DescID;

  inherited Add( NewRec );
end;

function TFileFormatsListHack.FindExt( Ext: string ): TGraphicClass;
var
  I: Integer;
begin
  Ext := AnsiLowerCase( Ext );
  for I := Count-1 downto 0 do
    with PFileFormat(Items[I])^ do
      if Extension = Ext then
      begin
        Result := GraphicClass;
        Exit;
      end;
  Result := nil;
end;

function TFileFormatsListHack.FindClassName( const ClassName: string ): TGraphicClass;
var
  I: Integer;
begin
  for I := Count-1 downto 0 do
  begin
    Result := PFileFormat(Items[I])^.GraphicClass;
    if Result.ClassName = ClassName then Exit;
  end;
  Result := nil;
end;

procedure TFileFormatsListHack.Remove( AClass: TGraphicClass);
var
  I: Integer;
  P: PFileFormat;
begin
  for I := Count-1 downto 0 do
  begin
    P := PFileFormat(Items[I]);
    if P^.GraphicClass.InheritsFrom(AClass) then
    begin
      Dispose(P);
      Delete(I);
    end;
  end;
end;

// unlike Remove, this matches the exact class only - entries of DESCENDANT
// classes (e.g. a converter subclassing the removed graphic class) survive
procedure TFileFormatsListHack.RemoveExactClass( AClass: TGraphicClass );
var
  I: Integer;
  P: PFileFormat;
begin
  for I := Count-1 downto 0 do
  begin
    P := PFileFormat(Items[I]);
    if P^.GraphicClass = AClass then
    begin
      Dispose(P);
      Delete(I);
    end;
  end;
end;

procedure TFileFormatsListHack.BuildFilterStrings( GraphicClass: TGraphicClass; var Descriptions, Filters: string );
var
  C, I: Integer;
  P: PFileFormat;
begin
  Descriptions := '';
  Filters := '';
  C := 0;
  for I := Count-1 downto 0 do
  begin
    P := PFileFormat(Items[I]);
    if P^.GraphicClass.InheritsFrom(GraphicClass) and (P^.Extension <> '') then
      with P^ do
      begin
        if C <> 0 then
        begin
          Descriptions := Descriptions + '|';
          Filters := Filters + ';';
        end;
        if (Description = '') and (DescResID <> 0) then
          Description := LoadStr(DescResID);
        FmtStr(Descriptions, '%s%s (*.%s)|*.%2:s', [Descriptions, Description, Extension]);
        FmtStr(Filters, '%s*.%s', [Filters, Extension]);
        Inc(C);
      end;
  end;
  if C > 1 then
    FmtStr(Descriptions, '%s (%s)|%1:s|%s', [sAllFilter, Filters, Descriptions]);
end;

function TFileFormatsListHack.Get( Index: Integer ) : PFileFormat;
begin
  Result := inherited Get( Index );
end;

procedure TFileFormatsListHack.Put( Index: Integer; Item: PFileFormat );
begin
  inherited Put( Index, Item );
end;

procedure TFileFormatsListHack.RemoveByName( ClassName : string );
var
  I : Integer;
  P : PFileFormat;
begin
  for I := Count-1 downto 0 do
  begin
    P := PFileFormat(Items[I]);

    if ( CompareText( P^.GraphicClass.ClassName, ClassName ) = 0 ) then
    begin
      Dispose(P);
      Delete(I);
    end;
  end;
end;

procedure TFileFormatsListHack.RemoveByExt( Ext : string );
var
  I : Integer;
  P : PFileFormat;
begin
  Ext := LowerCase( Ext );
  for I := Count-1 downto 0 do
  begin
    P := PFileFormat(Items[I]);

    if ( CompareText( P^.Extension, Ext ) = 0 ) then
    begin
      Dispose(P);
      Delete(I);
    end;
  end;
end;

procedure TFileFormatsListHack.RemoveByDescription( Description : string );
var
  I : Integer;
  P : PFileFormat;
begin
  for I := Count-1 downto 0 do
  begin
    P := PFileFormat(Items[I]);

    if ( CompareText( P^.Description, Description ) = 0 ) then
    begin
      Dispose(P);
      Delete(I);
    end;
  end;
end;

procedure TFileFormatsListHack.ListExtensions( List: TStrings );
var
  i: Integer;
begin
  for i := 0 to Count-1 do
    List.Add( Items[ i ]^.Extension + '=' + Items[ i ]^.Description );
end;

procedure TFileFormatsListHack.ListClassNames( List: TStrings );
var
  i: Integer;
begin
  for i := 0 to Count-1 do
    List.Add( Items[ i ]^.GraphicClass.ClassName );
end;

procedure TFileFormatsListHack.ListClasses( List: TClassList );
var
  i: Integer;
begin
  for i := 0 to Count-1 do
    List.Add( Items[ i ]^.GraphicClass );
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
procedure FindGetFileFormatsFunc(out ProcAddr: TGetFileFormats);
  function FindFirstRelativeCallOpcode(StartOffset: NativeUInt): NativeUInt;
  type
    TLongAbsoluteJumpOpcode = packed record
      OpCode: array [0 .. 1] of Byte;
      Destination: Cardinal;
    end;
    PLongAbsoluteJumpOpcode = ^TLongAbsoluteJumpOpcode;

    TRelativeCallOpcode = packed record
      OpCode: Byte;
      Offset: Integer;
    end;
    PRelativeCallOpcode = ^TRelativeCallOpcode;
  var
    Ram: PByte;
    i: Integer;
    PLongJump: PLongAbsoluteJumpOpcode;
  begin
    Ram := nil;
    PLongJump := PLongAbsoluteJumpOpcode( NativeUInt( Ram ) + StartOffset );
    if (PLongJump^.OpCode[0] = $FF) and (PLongJump^.OpCode[1] = $25) then
    {$IF Defined(WIN32)}
      Result := FindFirstRelativeCallOpcode(PNativeUInt(PLongJump^.Destination)^)
    {$ELSEIF Defined(Win64)}
      // RIP-relative displacement is SIGNED; Cardinal would zero-extend a
      // negative disp32 and compute a wrong IAT address
      Result := FindFirstRelativeCallOpcode(PNativeUInt(NativeUInt(Int64(StartOffset) + Integer(PLongJump^.Destination) + SizeOf(PLongJump^)))^)
    {$ELSE}
      {$MESSAGE Fatal 'Architecture not supported'}
    {$IFEND}
    else
      begin
      for i := 0 to 64 do
        begin
        if PRelativeCallOpcode( NativeUInt( Ram ) + StartOffset + Cardinal( i ) )^.OpCode = $E8 then
          begin
          result := StartOffset + Cardinal( i ) + PRelativeCallOpcode( NativeUInt( Ram ) + StartOffset + Cardinal( i ) )^.Offset + 5;
          Exit;
          end;
        end;
      Result := 0;
      end;
  end;
var
  Offset_from_RegisterFileFormat    : NativeUInt;
  Offset_from_RegisterFileFormatRes : NativeUInt;
begin
  Offset_from_RegisterFileFormat    := FindFirstRelativeCallOpcode( NativeUInt( @TPicture.RegisterFileFormat ) );
  Offset_from_RegisterFileFormatRes := FindFirstRelativeCallOpcode( NativeUInt( @TPicture.RegisterFileFormatRes ) );

  if (Offset_from_RegisterFileFormat = Offset_from_RegisterFileFormatRes) then
    ProcAddr := TGetFileFormats( Offset_from_RegisterFileFormat )
  else
    ProcAddr := nil;
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
initialization
  try
    FindGetFileFormatsFunc( GetFileFormats );
  except
    // an unexpected code layout must never break loading the IDE plugin;
    // callers check GetFileFormats = nil
    GetFileFormats := nil;
  end;

end.