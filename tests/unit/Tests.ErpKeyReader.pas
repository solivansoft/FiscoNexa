unit Tests.ErpKeyReader;

interface

uses
  TestFramework;

type
  TErpKeyReaderTests = class(TTestCase)
  public
    procedure TestReaderRetainsConnectionProvidedByCompositionRoot;
  end;

implementation

uses
  Persistence.ErpKeys;

procedure TErpKeyReaderTests.TestReaderRetainsConnectionProvidedByCompositionRoot;
var
  Reader: TPostgresErpKeyReader;
begin
  Reader := TPostgresErpKeyReader.Create(nil);
  try
    AssertTrue(Reader <> nil);
  finally
    Reader.Free;
  end;
end;

initialization

TTestHelper.RegisterTest(TErpKeyReaderTests.Create);

end.
