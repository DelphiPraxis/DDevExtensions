{$SetPEFlags 1} // no reloc info in EXE

program DDevExtensionsReg;

{$IF CompilerVersion >= 21.0}
{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$IFEND}

{$R 'manifest.res' 'manifest.rc'}

uses
  Forms,
  {$IF CompilerVersion > 30}
  Vcl.Themes,
  Vcl.Styles,
  {$IFEND}     
  Main in 'Main.pas' {FormMain},
  AppConsts in '..\Source\AppConsts.pas';

{$R *.res}

begin
  Application.Initialize;
  {$IF CompilerVersion > 30}
  TStyleManager.TrySetStyle('Windows10');
  {$IFEND}       
  Application.Title := 'DDevExtensions Installer';
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
