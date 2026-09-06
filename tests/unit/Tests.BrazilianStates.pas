unit Tests.BrazilianStates;

interface

uses TestFramework;

type
  TBrazilianStatesTests = class(TTestCase)
  public
    procedure TestReturnsIbgeCodeForState;
    procedure TestRejectsUnknownState;
  end;

implementation

uses
  Application.BrazilianStates,
  System.SysUtils;

procedure TBrazilianStatesTests.TestReturnsIbgeCodeForState;
begin
  AssertEquals(15, BrazilianStateCode('pa'));
  AssertEquals(35, BrazilianStateCode('SP'));
end;

procedure TBrazilianStatesTests.TestRejectsUnknownState;
begin
  try
    BrazilianStateCode('XX');
    Fail('UF inexistente foi aceita.');
  except
    on E: EArgumentException do AssertTrue(True);
  end;
end;

initialization

TTestHelper.RegisterTest(TBrazilianStatesTests.Create);

end.
