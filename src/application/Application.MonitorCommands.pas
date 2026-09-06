unit Application.MonitorCommands;

interface

uses
  Application.MonitorCycle;

type
  TMonitorCommandLease = record
    CommandId: string;
    CompanyId: string;
    Cnpj: string;
    AccessKey: string;
    AttemptCount: Integer;
  end;

  TMonitorCommandOutcome = record
    Status: string;
    NextAttemptDelaySeconds: Integer;
    CStat: Integer;
    MessageText: string;
    BlocksPrimaryMonitor: Boolean;
  end;

  IMonitorCommandRepository = interface
    ['{A4C8F4C6-E94C-4D82-8317-68BFB8A53B99}']
    function ClaimDue(const AWorkerId: string; const ABatchSize,
      ALeaseSeconds: Integer): TArray<TMonitorCommandLease>;
    procedure CompleteLease(const AWorkerId: string; const ALease: TMonitorCommandLease;
      const AOutcome: TMonitorCommandOutcome;
      const ADocuments: TArray<TSefazDocument>);
    procedure FailLease(const AWorkerId: string; const ALease: TMonitorCommandLease;
      const AMessage: string; const ADelaySeconds: Integer);
  end;

  TMonitorCommandProcessor = class
  private
    FGateway: IXmlRetrievalGateway;
    FRepository: IMonitorCommandRepository;
    FXmlStorage: IXmlStorage;
  public
    constructor Create(const AGateway: IXmlRetrievalGateway;
      const ARepository: IMonitorCommandRepository; const AXmlStorage: IXmlStorage);
    procedure Execute(const AWorkerId: string; const ALease: TMonitorCommandLease);
  end;

function BuildMonitorCommandOutcome(const AResponse: TDistributionResponse): TMonitorCommandOutcome;

implementation

uses
  Application.SefazMonitoringPolicy,
  System.SysUtils;

function BuildMonitorCommandOutcome(const AResponse: TDistributionResponse): TMonitorCommandOutcome;
var Document: TSefazDocument;
begin
  Result := Default(TMonitorCommandOutcome);
  Result.CStat := AResponse.CStat;
  Result.MessageText := AResponse.MessageText;
  Result.Status := 'pending';
  if AResponse.CStat = 656 then
  begin
    Result.NextAttemptDelaySeconds := SefazWaitSeconds;
    Result.BlocksPrimaryMonitor := True;
    Exit;
  end;
  for Document in AResponse.Documents do
    if (Document.AwarenessCStat = 596) or (Document.AwarenessCStat = 655) then
    begin
      Result.Status := 'failed';
      Result.NextAttemptDelaySeconds := 0;
      Exit;
    end;
  Result.NextAttemptDelaySeconds := SefazPointIntervalSeconds;
  if AResponse.CStat = 138 then
    for Document in AResponse.Documents do
      if Document.IsCompleteXml and (Document.XmlObjectKey <> '') and
        (Document.XmlSha256 <> '') then
      begin
        Result.Status := 'succeeded';
        Result.NextAttemptDelaySeconds := 0;
        Exit;
      end;
end;

constructor TMonitorCommandProcessor.Create(const AGateway: IXmlRetrievalGateway;
  const ARepository: IMonitorCommandRepository; const AXmlStorage: IXmlStorage);
begin
  inherited Create;
  if AGateway = nil then
    raise EArgumentNilException.Create('Gateway SEFAZ nao informado.');
  if ARepository = nil then
    raise EArgumentNilException.Create('Repositorio de comandos nao informado.');
  if AXmlStorage = nil then
    raise EArgumentNilException.Create('Storage de XML nao informado.');
  FGateway := AGateway;
  FRepository := ARepository;
  FXmlStorage := AXmlStorage;
end;

procedure TMonitorCommandProcessor.Execute(const AWorkerId: string;
  const ALease: TMonitorCommandLease);
var
  Response: TDistributionResponse;
  Outcome: TMonitorCommandOutcome;
begin
  try
    Response := FGateway.QueryDocument(ALease.CompanyId, ALease.AccessKey);
    StoreDistributionXml(FXmlStorage, ALease.Cnpj, Response.Documents);
    Outcome := BuildMonitorCommandOutcome(Response);
    FRepository.CompleteLease(AWorkerId, ALease, Outcome, Response.Documents);
  except
    on E: Exception do
      FRepository.FailLease(AWorkerId, ALease, E.Message,
        TechnicalFailureDelaySeconds(ALease.AttemptCount));
  end;
end;

end.
