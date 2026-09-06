unit Application.MonitorGaps;

interface

uses Application.MonitorCycle;

type
  TMonitorGapLease = record
    GapId: string;
    CompanyId: string;
    Cnpj: string;
    NextNsu: string;
    EndNsu: string;
  end;

  TMonitorGapOutcome = record
    NextNsu: string;
    Status: string;
    NextAttemptDelaySeconds: Integer;
    CStat: Integer;
    MessageText: string;
    BlocksPrimaryMonitor: Boolean;
  end;

  IMonitorGapRepository = interface
    ['{4E703E25-2BFF-4CD1-9E08-1A87C54FCF38}']
    function ClaimDue(const AWorkerId: string; const ABatchSize,
      ALeaseSeconds: Integer): TArray<TMonitorGapLease>;
    procedure CompleteLease(const AWorkerId: string; const ALease: TMonitorGapLease;
      const AOutcome: TMonitorGapOutcome; const ADocuments: TArray<TSefazDocument>);
    procedure FailLease(const AWorkerId: string; const ALease: TMonitorGapLease;
      const AMessage: string; const ADelaySeconds: Integer);
  end;

  TMonitorGapRecovery = class
  private
    FXmlStorage: IXmlStorage;
    FGateway: IDistributionGateway;
    FRepository: IMonitorGapRepository;
  public
    constructor Create(const AGateway: IDistributionGateway;
      const ARepository: IMonitorGapRepository; const AXmlStorage: IXmlStorage);
    procedure Execute(const AWorkerId: string; const ALease: TMonitorGapLease);
  end;

function BuildMonitorGapOutcome(const ALease: TMonitorGapLease;
  const AResponse: TDistributionResponse): TMonitorGapOutcome;

implementation

uses
  Application.SefazMonitoringPolicy,
  System.SysUtils;

function BuildMonitorGapOutcome(const ALease: TMonitorGapLease;
  const AResponse: TDistributionResponse): TMonitorGapOutcome;
var
  NextNsu: string;
begin
  Result := Default(TMonitorGapOutcome);
  Result.CStat := AResponse.CStat;
  Result.MessageText := AResponse.MessageText;
  if AResponse.CStat in [137, 138] then
  begin
    NextNsu := IncrementNsu(ALease.NextNsu);
    Result.NextNsu := NextNsu;
    if (NextNsu = '') or (NextNsu > NormalizeNsu(ALease.EndNsu)) then
      Result.Status := 'succeeded'
    else
      Result.Status := 'pending';
    Result.NextAttemptDelaySeconds := 0;
    Exit;
  end;
  Result.NextNsu := ALease.NextNsu;
  Result.Status := 'pending';
  Result.NextAttemptDelaySeconds := SefazWaitSeconds;
  Result.BlocksPrimaryMonitor := AResponse.CStat = 656;
end;

constructor TMonitorGapRecovery.Create(const AGateway: IDistributionGateway;
  const ARepository: IMonitorGapRepository; const AXmlStorage: IXmlStorage);
begin
  inherited Create;
  if AGateway = nil then
    raise EArgumentNilException.Create('Gateway SEFAZ nao informado.');
  if ARepository = nil then
    raise EArgumentNilException.Create('Repositorio de lacunas nao informado.');
  FGateway := AGateway;
  if AXmlStorage = nil then raise EArgumentNilException.Create('Storage nao informado.');
  FRepository := ARepository;
  FXmlStorage := AXmlStorage;
end;

procedure TMonitorGapRecovery.Execute(const AWorkerId: string;
  const ALease: TMonitorGapLease);
var
  Response: TDistributionResponse;
  Outcome: TMonitorGapOutcome;
begin
  if Trim(AWorkerId) = '' then
    raise EArgumentException.Create('Identificador do worker obrigatorio.');
  try
    Response := FGateway.QueryDistributionByNsu(ALease.CompanyId, ALease.NextNsu);
    StoreDistributionXml(FXmlStorage, ALease.Cnpj, Response.Documents);
    Outcome := BuildMonitorGapOutcome(ALease, Response);
    FRepository.CompleteLease(AWorkerId, ALease, Outcome, Response.Documents);
  except
    on E: Exception do
      FRepository.FailLease(AWorkerId, ALease, E.Message, SefazWaitSeconds);
  end;
end;

end.
