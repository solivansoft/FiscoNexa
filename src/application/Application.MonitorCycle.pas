unit Application.MonitorCycle;

interface

uses
  Application.MonitorLeases;

type
  TSefazDocument = record
    SefazNsu: string;
    AccessKey: string;
    IssuedAt: TDateTime;
    IssuerCnpj: string;
    IssuerName: string;
    OperationType: string;
    FiscalStatus: string;
    TotalAmount: Currency;
    IsCompleteXml: Boolean;
    Xml: string;
    XmlObjectKey: string;
    XmlSha256: string;
    AwarenessAccepted: Boolean;
    AwarenessCStat: Integer;
  end;

  TStoredXml = record
    ObjectKey: string;
    Sha256: string;
  end;

  IXmlStorage = interface
    ['{B71CB07E-4A94-42A8-9F49-6A0B61FA1BCE}']
    function Put(const ACompanyCnpj, AAccessKey, AXml: string): TStoredXml;
  end;

  TDistributionResponse = record
    CStat: Integer;
    ReturnedNsu: string;
    MaxNsu: string;
    MessageText: string;
    Documents: TArray<TSefazDocument>;
  end;

  TMonitorCycleOutcome = record
    LastNsu: string;
    LastCStat: Integer;
    LastMessage: string;
    NextCheckAt: TDateTime;
    NextCheckDelaySeconds: Integer;
    BlockedCount: Integer;
    FailureCount: Integer;
    GapStartNsu: string;
    GapEndNsu: string;
  end;

  IDistributionGateway = interface
    ['{D9D6F0A1-B31B-4A2C-86B6-D0B6BD3F0A0D}']
    function QueryDistribution(const ACompanyId, ALastNsu: string): TDistributionResponse;
    function QueryDistributionByNsu(const ACompanyId, ANsu: string): TDistributionResponse;
  end;

  IXmlRetrievalGateway = interface
    ['{0A865D06-D165-4431-9575-136F00319441}']
    function QueryDocument(const ACompanyId, AAccessKey: string): TDistributionResponse;
  end;

  IMonitorCycleWriter = interface
    ['{B5E6B18C-BA2A-47C4-A1EA-77409E5139BB}']
    procedure CompleteLease(const AWorkerId: string; const ALease: TMonitorLease;
      const AOutcome: TMonitorCycleOutcome;
      const ADocuments: TArray<TSefazDocument>);
    procedure FailLease(const AWorkerId: string; const ALease: TMonitorLease;
      const AMessage: string; const ADelaySeconds: Integer);
  end;

  TMonitorCycle = class
  private
    FGateway: IDistributionGateway;
    FWriter: IMonitorCycleWriter;
    FXmlStorage: IXmlStorage;
  public
    constructor Create(const AGateway: IDistributionGateway;
      const AWriter: IMonitorCycleWriter; const AXmlStorage: IXmlStorage);
    procedure Execute(const AWorkerId: string; const ALease: TMonitorLease;
      const ANow: TDateTime);
  end;

procedure StoreDistributionXml(const AStorage: IXmlStorage; const ACnpj: string;
  var ADocuments: TArray<TSefazDocument>);

function BuildMonitorCycleOutcome(const ALease: TMonitorLease;
  const AResponse: TDistributionResponse; const ANow: TDateTime): TMonitorCycleOutcome;

implementation

uses
  Application.SefazMonitoringPolicy,
  System.DateUtils,
  System.SysUtils;

procedure StoreDistributionXml(const AStorage: IXmlStorage; const ACnpj: string;
  var ADocuments: TArray<TSefazDocument>);
var Index: Integer; Stored: TStoredXml;
begin
  for Index := 0 to High(ADocuments) do
    if ADocuments[Index].IsCompleteXml then
    begin
      if ADocuments[Index].Xml = '' then
        raise EInvalidOpException.Create('XML completo retornado vazio.');
      Stored := AStorage.Put(ACnpj, ADocuments[Index].AccessKey, ADocuments[Index].Xml);
      if (Stored.ObjectKey = '') or (Stored.Sha256 = '') then
        raise EInvalidOpException.Create('Storage nao confirmou chave e hash do XML.');
      ADocuments[Index].XmlObjectKey := Stored.ObjectKey;
      ADocuments[Index].XmlSha256 := Stored.Sha256;
    end;
end;

function BuildMonitorCycleOutcome(const ALease: TMonitorLease;
  const AResponse: TDistributionResponse; const ANow: TDateTime): TMonitorCycleOutcome;
var
  Decision: TSefazDistributionDecision;
begin
  Decision := DecideDistribution(ALease.LastNsu, AResponse.ReturnedNsu,
    AResponse.MaxNsu, AResponse.CStat);
  Result.LastNsu := Decision.NextNsu;
  if Result.LastNsu = '' then
    Result.LastNsu := NormalizeNsu(ALease.LastNsu);
  Result.LastCStat := AResponse.CStat;
  Result.LastMessage := AResponse.MessageText;
  Result.GapStartNsu := Decision.GapStartNsu;
  Result.GapEndNsu := Decision.GapEndNsu;
  if Decision.ContinueNow then
  begin
    Result.NextCheckAt := ANow;
    Result.NextCheckDelaySeconds := 0;
  end
  else
  begin
    Result.NextCheckAt := IncSecond(ANow, SefazWaitSeconds);
    Result.NextCheckDelaySeconds := SefazWaitSeconds;
  end;
  if AResponse.CStat = 656 then
    Result.BlockedCount := ALease.BlockedCount + 1
  else
    Result.BlockedCount := 0;
  Result.FailureCount := 0;
end;

constructor TMonitorCycle.Create(const AGateway: IDistributionGateway;
  const AWriter: IMonitorCycleWriter; const AXmlStorage: IXmlStorage);
begin
  inherited Create;
  if AGateway = nil then
    raise EArgumentNilException.Create('Gateway SEFAZ nao informado.');
  if AWriter = nil then
    raise EArgumentNilException.Create('Persistencia do ciclo nao informada.');
  if AXmlStorage = nil then
    raise EArgumentNilException.Create('Storage de XML nao informado.');
  FGateway := AGateway;
  FWriter := AWriter;
  FXmlStorage := AXmlStorage;
end;

procedure TMonitorCycle.Execute(const AWorkerId: string;
  const ALease: TMonitorLease; const ANow: TDateTime);
var
  Response: TDistributionResponse;
  Outcome: TMonitorCycleOutcome;
  RetrySeconds: Integer;
begin
  ValidateLeaseRequest(AWorkerId, 1, 1);
  if Trim(ALease.CompanyId) = '' then
    raise EMonitorLeaseValidation.Create('CNPJ da lease obrigatorio.');
  try
    Response := FGateway.QueryDistribution(ALease.CompanyId, ALease.LastNsu);
    Outcome := BuildMonitorCycleOutcome(ALease, Response, ANow);
    StoreDistributionXml(FXmlStorage, ALease.Cnpj, Response.Documents);
    FWriter.CompleteLease(AWorkerId, ALease, Outcome, Response.Documents);
  except
    on E: Exception do
    begin
      RetrySeconds := TechnicalFailureDelaySeconds(ALease.FailureCount);
      // Gateway pode falhar durante a ciencia depois de consultar distribuicao.
      if RetrySeconds < SefazWaitSeconds then
        RetrySeconds := SefazWaitSeconds;
      FWriter.FailLease(AWorkerId, ALease, E.Message, RetrySeconds);
    end;
  end;
end;

end.
