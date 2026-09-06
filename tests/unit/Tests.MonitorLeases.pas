unit Tests.MonitorLeases;

interface

uses
  TestFramework;

type
  TMonitorLeaseTests = class(TTestCase)
  public
    procedure TestRejectsEmptyWorkerId;
    procedure TestRejectsInvalidBatchSize;
    procedure TestRejectsInvalidLeaseDuration;
  end;

implementation

uses
  Application.MonitorLeases;

procedure TMonitorLeaseTests.TestRejectsEmptyWorkerId;
begin
  try
    ValidateLeaseRequest('', 20, 300);
    Fail('Lease sem worker foi aceita.');
  except
    on E: EMonitorLeaseValidation do
      AssertTrue(True);
  end;
end;

procedure TMonitorLeaseTests.TestRejectsInvalidBatchSize;
begin
  try
    ValidateLeaseRequest('worker-1', 0, 300);
    Fail('Lote invalido foi aceito.');
  except
    on E: EMonitorLeaseValidation do
      AssertTrue(True);
  end;
end;

procedure TMonitorLeaseTests.TestRejectsInvalidLeaseDuration;
begin
  try
    ValidateLeaseRequest('worker-1', 20, 0);
    Fail('Lease invalida foi aceita.');
  except
    on E: EMonitorLeaseValidation do
      AssertTrue(True);
  end;
end;

initialization

TTestHelper.RegisterTest(TMonitorLeaseTests.Create);

end.
