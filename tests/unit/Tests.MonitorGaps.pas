unit Tests.MonitorGaps;

interface

uses TestFramework;

type
  TMonitorGapTests = class(TTestCase)
  public
    procedure Test138AdvancesGapAndKeepsItPending;
    procedure Test137CompletesLastGapNsu;
    procedure Test656WaitsAndBlocksMainMonitor;
  end;

implementation

uses
  Application.MonitorCycle,
  Application.MonitorGaps;

procedure TMonitorGapTests.Test138AdvancesGapAndKeepsItPending;
var
  Lease: TMonitorGapLease;
  Response: TDistributionResponse;
  Outcome: TMonitorGapOutcome;
begin
  Lease.NextNsu := '100';
  Lease.EndNsu := '102';
  Response.CStat := 138;
  Outcome := BuildMonitorGapOutcome(Lease, Response);
  AssertEquals('000000000000101', Outcome.NextNsu);
  AssertEquals('pending', Outcome.Status);
end;

procedure TMonitorGapTests.Test137CompletesLastGapNsu;
var
  Lease: TMonitorGapLease;
  Response: TDistributionResponse;
  Outcome: TMonitorGapOutcome;
begin
  Lease.NextNsu := '102';
  Lease.EndNsu := '102';
  Response.CStat := 137;
  Outcome := BuildMonitorGapOutcome(Lease, Response);
  AssertEquals('succeeded', Outcome.Status);
end;

procedure TMonitorGapTests.Test656WaitsAndBlocksMainMonitor;
var
  Lease: TMonitorGapLease;
  Response: TDistributionResponse;
  Outcome: TMonitorGapOutcome;
begin
  Lease.NextNsu := '100';
  Lease.EndNsu := '102';
  Response.CStat := 656;
  Outcome := BuildMonitorGapOutcome(Lease, Response);
  AssertEquals('pending', Outcome.Status);
  AssertEquals(3630, Outcome.NextAttemptDelaySeconds);
  AssertTrue(Outcome.BlocksPrimaryMonitor);
end;

initialization

TTestHelper.RegisterTest(TMonitorGapTests.Create);

end.
