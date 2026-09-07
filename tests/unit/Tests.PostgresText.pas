unit Tests.PostgresText;

interface

uses
  TestFramework;

type
  TPostgresTextTests = class(TTestCase)
  public
    procedure TestRemoveByteNuloDeErroExterno;
    procedure TestLimitaTextoDepoisDaSanitizacao;
  end;

implementation

uses
  Persistence.PostgresText,
  System.SysUtils;

procedure TPostgresTextTests.TestRemoveByteNuloDeErroExterno;
var
  Texto: string;
  Bytes: TBytes;
  B: Byte;
begin
  Texto := TextoSeguroPostgres('erro'#0' sefaz');
  AssertEquals(10, Length(Texto));
  AssertEquals(0, Pos(#0, Texto));
  AssertEquals('erro sefaz', Texto);
  Bytes := TEncoding.UTF8.GetBytes(Texto);
  for B in Bytes do
    AssertTrue(B <> 0);
end;

procedure TPostgresTextTests.TestLimitaTextoDepoisDaSanitizacao;
begin
  AssertEquals('abcd', TextoSeguroPostgres('ab'#0'cdef', 4));
end;

initialization
  TTestHelper.RegisterTest(TPostgresTextTests.Create);

end.
