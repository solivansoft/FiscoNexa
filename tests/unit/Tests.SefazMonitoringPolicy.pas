unit Tests.SefazMonitoringPolicy;

interface

uses
  TestFramework;

type
  TSefazMonitoringPolicyTests = class(TTestCase)
  public
    procedure Test137SchedulesWaitAndKeepsReturnedCursor;
    procedure Test138ContinuesWhileCursorIsBehindMaxNsu;
    procedure Test138SchedulesWaitWhenCursorReachesMaxNsu;
    procedure Test656CreatesGapAfterExternalAdvance;
    procedure Test656WithEmptyCursorAdoptsReturnedNsu;
    procedure TestPointQueryRejectsRecentQuery;
    procedure TestPointQueryRejectsHourlyLimit;
    procedure TestTechnicalFailureBackoffGrowsAndCapsAtSefazWindow;
  end;

implementation

uses
  System.DateUtils,
  Application.SefazMonitoringPolicy;

procedure TSefazMonitoringPolicyTests.Test137SchedulesWaitAndKeepsReturnedCursor;
var
  Decision: TSefazDistributionDecision;
begin
  Decision := DecideDistribution('10', '10', '10', 137);
  AssertTrue(Decision.MustWait);
  AssertFalse(Decision.ContinueNow);
  AssertEquals('000000000000010', Decision.NextNsu);
end;

procedure TSefazMonitoringPolicyTests.Test138ContinuesWhileCursorIsBehindMaxNsu;
var
  Decision: TSefazDistributionDecision;
begin
  Decision := DecideDistribution('10', '20', '30', 138);
  AssertTrue(Decision.ContinueNow);
  AssertFalse(Decision.MustWait);
  AssertEquals('000000000000020', Decision.NextNsu);
end;

procedure TSefazMonitoringPolicyTests.Test138SchedulesWaitWhenCursorReachesMaxNsu;
var
  Decision: TSefazDistributionDecision;
begin
  Decision := DecideDistribution('10', '30', '30', 138);
  AssertFalse(Decision.ContinueNow);
  AssertTrue(Decision.MustWait);
end;

procedure TSefazMonitoringPolicyTests.Test656CreatesGapAfterExternalAdvance;
var
  Decision: TSefazDistributionDecision;
begin
  Decision := DecideDistribution('100', '150', '', 656);
  AssertTrue(Decision.MustWait);
  AssertTrue(Decision.ExternalAdvance);
  AssertEquals('000000000000150', Decision.NextNsu);
  AssertEquals('000000000000101', Decision.GapStartNsu);
  AssertEquals('000000000000150', Decision.GapEndNsu);
end;

procedure TSefazMonitoringPolicyTests.TestPointQueryRejectsRecentQuery;
var
  NowValue: TDateTime;
  NextQueryAt: TDateTime;
begin
  NowValue := EncodeDateTime(2026, 9, 5, 12, 0, 0, 0);
  AssertFalse(IsPointQueryAllowed(NowValue, 0, 0,
    IncSecond(NowValue, -60), NextQueryAt));
  AssertTrue(NextQueryAt = IncSecond(NowValue, 240));
end;

procedure TSefazMonitoringPolicyTests.TestPointQueryRejectsHourlyLimit;
var
  NowValue: TDateTime;
  NextQueryAt: TDateTime;
begin
  NowValue := EncodeDateTime(2026, 9, 5, 12, 0, 0, 0);
  AssertFalse(IsPointQueryAllowed(NowValue, SefazPointLimitPerHour,
    IncSecond(NowValue, -3000), IncSecond(NowValue, -600), NextQueryAt));
  AssertTrue(NextQueryAt = IncSecond(NowValue, 630));
end;

procedure TSefazMonitoringPolicyTests.TestTechnicalFailureBackoffGrowsAndCapsAtSefazWindow;
begin
  AssertEquals(60, TechnicalFailureDelaySeconds(0));
  AssertEquals(120, TechnicalFailureDelaySeconds(1));
  AssertEquals(960, TechnicalFailureDelaySeconds(4));
  AssertEquals(SefazWaitSeconds, TechnicalFailureDelaySeconds(6));
end;

procedure TSefazMonitoringPolicyTests.Test656WithEmptyCursorAdoptsReturnedNsu;
var Decision: TSefazDistributionDecision;
begin
  Decision := DecideDistribution('', '150', '', 656);
  AssertEquals('000000000000150', Decision.NextNsu);
  AssertEquals('000000000000001', Decision.GapStartNsu);
  AssertTrue(Decision.MustWait);
  AssertFalse(Decision.ContinueNow);
end;

initialization

TTestHelper.RegisterTest(TSefazMonitoringPolicyTests.Create);

end.
