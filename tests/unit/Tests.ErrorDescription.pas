unit Tests.ErrorDescription;

interface

uses
  TestFramework;

type
  TErrorDescriptionTests = class(TTestCase)
  public
    procedure TestConverteMensagemExternaParaAscii;
  end;

implementation

uses
  Application.ErrorDescription,
  System.SysUtils;

procedure TErrorDescriptionTests.TestConverteMensagemExternaParaAscii;
var
  E: Exception;
  Texto: string;
  C: Char;
begin
  E := EInvalidOpException.Create('falha'#0' conexao ' + Char($00E7));
  try
    Texto := DescricaoErroPersistivel(E);
    AssertTrue(Pos(#0, Texto) = 0);
    AssertTrue(Pos('EInvalidOpException: falha conexao ', Texto) = 1);
    for C in Texto do
      AssertTrue((Ord(C) >= 32) and (Ord(C) <= 126));
  finally
    E.Free;
  end;
end;

initialization
  TTestHelper.RegisterTest(TErrorDescriptionTests.Create);

end.
