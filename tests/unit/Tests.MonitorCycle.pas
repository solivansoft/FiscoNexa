unit Tests.MonitorCycle;

interface

uses
  TestFramework;

type
  TMonitorCycleTests = class(TTestCase)
  public
    procedure Test138SchedulesImmediateContinuation;
    procedure Test656CreatesPersistentGapOutcome;
    procedure TestDistributionResponsePreservesSefazDocuments;
    procedure TestTechnicalFailurePersistsBackoffAndReleasesLease;
    procedure TestStorageFailureAfterFiscalResponseWaitsFullWindow;
  end;

implementation

uses
  Application.MonitorCycle,
  Application.MonitorLeases,
  System.DateUtils,
  System.SysUtils,
  Integrations.MockSefaz;

type
  TFailingGateway = class(TInterfacedObject, IDistributionGateway)
  public
    function QueryDistribution(const ACompanyId, ALastNsu: string): TDistributionResponse;
    function QueryDistributionByNsu(const ACompanyId, ANsu: string): TDistributionResponse;
  end;

  TRecordingWriter = class(TInterfacedObject, IMonitorCycleWriter)
  public
    FailureCalled: Boolean;
    FailureDelaySeconds: Integer;
    FailureMessage: string;
    procedure CompleteLease(const AWorkerId: string; const ALease: TMonitorLease;
      const AOutcome: TMonitorCycleOutcome;
      const ADocuments: TArray<TSefazDocument>);
    procedure FailLease(const AWorkerId: string; const ALease: TMonitorLease;
      const AMessage: string; const ADelaySeconds: Integer);
  end;

  TUnusedStorage = class(TInterfacedObject, IXmlStorage)
  public
    function Put(const ACompanyCnpj, AAccessKey, AXml: string): TStoredXml;
  end;

function TFailingGateway.QueryDistribution(const ACompanyId,
  ALastNsu: string): TDistributionResponse;
begin
  raise Exception.Create('Falha de rede simulada');
end;

function TFailingGateway.QueryDistributionByNsu(const ACompanyId,
  ANsu: string): TDistributionResponse;
begin
  raise Exception.Create('Falha de rede simulada');
end;

procedure TRecordingWriter.CompleteLease(const AWorkerId: string;
  const ALease: TMonitorLease; const AOutcome: TMonitorCycleOutcome;
  const ADocuments: TArray<TSefazDocument>);
begin
  raise Exception.Create('Nao deveria concluir uma lease com gateway indisponivel.');
end;

procedure TRecordingWriter.FailLease(const AWorkerId: string;
  const ALease: TMonitorLease; const AMessage: string;
  const ADelaySeconds: Integer);
begin
  FailureCalled := True;
  FailureDelaySeconds := ADelaySeconds;
  FailureMessage := AMessage;
end;

function TUnusedStorage.Put(const ACompanyCnpj, AAccessKey,
  AXml: string): TStoredXml;
begin
  raise Exception.Create('Storage nao deveria ser chamado.');
end;

procedure TMonitorCycleTests.Test138SchedulesImmediateContinuation;
var
  Lease: TMonitorLease;
  Response: TDistributionResponse;
  Outcome: TMonitorCycleOutcome;
  NowValue: TDateTime;
begin
  NowValue := EncodeDateTime(2026, 9, 5, 12, 0, 0, 0);
  Lease.CompanyId := 'company-1';
  Lease.LastNsu := '10';
  Lease.LastCStat := 0;
  Lease.BlockedCount := 0;
  Response.CStat := 138;
  Response.ReturnedNsu := '20';
  Response.MaxNsu := '30';
  Response.MessageText := 'Lote encontrado';
  Outcome := BuildMonitorCycleOutcome(Lease, Response, NowValue);
  AssertEquals('000000000000020', Outcome.LastNsu);
  AssertTrue(Outcome.NextCheckAt = NowValue);
  AssertEquals(0, Outcome.BlockedCount);
end;

procedure TMonitorCycleTests.TestDistributionResponsePreservesSefazDocuments;
var
  Response: TDistributionResponse;
begin
  SetLength(Response.Documents, 1);
  Response.Documents[0].SefazNsu := '000000000000123';
  Response.Documents[0].AccessKey := '35260912345678000190550010000000011000000010';
  Response.Documents[0].IsCompleteXml := True;
  Response.Documents[0].Xml := '<nfeProc/>';
  AssertEquals(1, Length(Response.Documents));
  AssertEquals('000000000000123', Response.Documents[0].SefazNsu);
  AssertTrue(Response.Documents[0].IsCompleteXml);
  AssertEquals('<nfeProc/>', Response.Documents[0].Xml);
end;

procedure TMonitorCycleTests.Test656CreatesPersistentGapOutcome;
var
  Lease: TMonitorLease;
  Response: TDistributionResponse;
  Outcome: TMonitorCycleOutcome;
  NowValue: TDateTime;
begin
  NowValue := EncodeDateTime(2026, 9, 5, 12, 0, 0, 0);
  Lease.CompanyId := 'company-1';
  Lease.LastNsu := '100';
  Lease.LastCStat := 2;
  Lease.BlockedCount := 2;
  Response.CStat := 656;
  Response.ReturnedNsu := '150';
  Response.MaxNsu := '';
  Response.MessageText := 'Consumo indevido';
  Outcome := BuildMonitorCycleOutcome(Lease, Response, NowValue);
  AssertEquals('000000000000150', Outcome.LastNsu);
  AssertEquals('000000000000101', Outcome.GapStartNsu);
  AssertEquals('000000000000150', Outcome.GapEndNsu);
  AssertEquals(3, Outcome.BlockedCount);
  AssertTrue(Outcome.NextCheckAt = IncSecond(NowValue, 3630));
end;

procedure TMonitorCycleTests.TestTechnicalFailurePersistsBackoffAndReleasesLease;
var
  Gateway: IDistributionGateway;
  Writer: TRecordingWriter;
  Storage: IXmlStorage;
  Cycle: TMonitorCycle;
  Lease: TMonitorLease;
begin
  Gateway := TFailingGateway.Create;
  Writer := TRecordingWriter.Create;
  Storage := TUnusedStorage.Create;
  Cycle := TMonitorCycle.Create(Gateway, Writer, Storage);
  try
    Lease.CompanyId := 'company-1';
    Lease.Cnpj := '12345678000190';
    Lease.FailureCount := 1;
    Cycle.Execute('worker-1', Lease, Now);
    AssertTrue(Writer.FailureCalled);
    AssertEquals(3630, Writer.FailureDelaySeconds);
    AssertEquals('Exception: Falha de rede simulada', Writer.FailureMessage);
  finally
    Cycle.Free;
  end;
end;

procedure TMonitorCycleTests.TestStorageFailureAfterFiscalResponseWaitsFullWindow;
var
  Response: TDistributionResponse;
  Gateway: IDistributionGateway;
  Writer: TRecordingWriter;
  Storage: IXmlStorage;
  Cycle: TMonitorCycle;
  Lease: TMonitorLease;
begin
  Response := Default(TDistributionResponse);
  Response.CStat := 138;
  Response.ReturnedNsu := '10';
  Response.MaxNsu := '10';
  SetLength(Response.Documents, 1);
  Response.Documents[0].IsCompleteXml := True;
  Response.Documents[0].Xml := '<nfeProc/>';
  Gateway := TMockDistributionGateway.Create(Response);
  Writer := TRecordingWriter.Create;
  Storage := TUnusedStorage.Create;
  Cycle := TMonitorCycle.Create(Gateway, Writer, Storage);
  try
    Lease := Default(TMonitorLease);
    Lease.CompanyId := 'company-1';
    Cycle.Execute('worker-1', Lease, Now);
    AssertTrue(Writer.FailureCalled);
    AssertEquals(3630, Writer.FailureDelaySeconds);
  finally Cycle.Free; end;
end;

initialization

TTestHelper.RegisterTest(TMonitorCycleTests.Create);

end.
