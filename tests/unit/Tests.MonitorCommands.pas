unit Tests.MonitorCommands;
interface
uses TestFramework;
type TMonitorCommandTests = class(TTestCase)
public
  procedure TestSummaryDoesNotCompleteDownload;
  procedure TestStoredXmlCompletesDownload;
  procedure Test656BlocksMonitor;
  procedure TestFinalAwarenessRejectionStopsDownload;
end;
implementation
uses Application.MonitorCommands, Application.MonitorCycle;
procedure TMonitorCommandTests.TestSummaryDoesNotCompleteDownload;
var R: TDistributionResponse; O: TMonitorCommandOutcome;
begin
  R := Default(TDistributionResponse); R.CStat := 138;
  SetLength(R.Documents,1); R.Documents[0].AwarenessAccepted := True;
  O := BuildMonitorCommandOutcome(R);
  AssertEquals('pending', O.Status); AssertEquals(300,O.NextAttemptDelaySeconds);
  AssertFalse(O.BlocksPrimaryMonitor);
end;
procedure TMonitorCommandTests.TestStoredXmlCompletesDownload;
var R: TDistributionResponse; O: TMonitorCommandOutcome;
begin
  R := Default(TDistributionResponse); R.CStat := 138;
  SetLength(R.Documents,1); R.Documents[0].IsCompleteXml := True;
  O := BuildMonitorCommandOutcome(R); AssertEquals('pending',O.Status);
  R.Documents[0].XmlObjectKey := 'xml'; R.Documents[0].XmlSha256 := 'hash';
  O := BuildMonitorCommandOutcome(R); AssertEquals('succeeded',O.Status);
  AssertFalse(O.BlocksPrimaryMonitor);
end;
procedure TMonitorCommandTests.Test656BlocksMonitor;
var R: TDistributionResponse; O: TMonitorCommandOutcome;
begin
  R := Default(TDistributionResponse); R.CStat := 656;
  O := BuildMonitorCommandOutcome(R);
  AssertEquals('pending',O.Status); AssertEquals(3630,O.NextAttemptDelaySeconds);
  AssertTrue(O.BlocksPrimaryMonitor);
end;
procedure TMonitorCommandTests.TestFinalAwarenessRejectionStopsDownload;
var R: TDistributionResponse; O: TMonitorCommandOutcome;
begin
  R := Default(TDistributionResponse); R.CStat := 138;
  SetLength(R.Documents, 1); R.Documents[0].AwarenessCStat := 596;
  O := BuildMonitorCommandOutcome(R);
  AssertEquals('failed', O.Status); AssertEquals(0, O.NextAttemptDelaySeconds);
  R.Documents[0].AwarenessCStat := 655;
  O := BuildMonitorCommandOutcome(R);
  AssertEquals('failed', O.Status); AssertEquals(0, O.NextAttemptDelaySeconds);
end;
initialization
TTestHelper.RegisterTest(TMonitorCommandTests.Create);
end.
