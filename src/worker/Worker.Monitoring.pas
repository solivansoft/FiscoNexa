unit Worker.Monitoring;

interface

uses
  Application.MonitorCycle,
  Application.MonitorCommands,
  Application.MonitorGaps,
  Application.MonitorLeases;

type
  TMonitoringWorker = class
  private
    FCommandRepository: IMonitorCommandRepository;
    FCommandProcessor: TMonitorCommandProcessor;
    FLeaseRepository: IMonitorLeaseRepository;
    FCycle: TMonitorCycle;
    FGapRepository: IMonitorGapRepository;
    FGapRecovery: TMonitorGapRecovery;
  public
    constructor Create(const ALeaseRepository: IMonitorLeaseRepository;
      const ACycle: TMonitorCycle; const AGapRepository: IMonitorGapRepository;
      const AGapRecovery: TMonitorGapRecovery; const ACommandRepository: IMonitorCommandRepository;
      const ACommandProcessor: TMonitorCommandProcessor);
    function RunOnce(const AWorkerId: string; const ABatchSize,
      ALeaseSeconds: Integer): Integer;
  end;

implementation

uses
  System.SysUtils;

constructor TMonitoringWorker.Create(const ALeaseRepository: IMonitorLeaseRepository;
  const ACycle: TMonitorCycle; const AGapRepository: IMonitorGapRepository;
  const AGapRecovery: TMonitorGapRecovery; const ACommandRepository: IMonitorCommandRepository;
  const ACommandProcessor: TMonitorCommandProcessor);
begin
  inherited Create;
  if ALeaseRepository = nil then
    raise EArgumentNilException.Create('Repositorio de leases nao informado.');
  if ACycle = nil then
    raise EArgumentNilException.Create('Ciclo de monitoramento nao informado.');
  if AGapRepository = nil then
    raise EArgumentNilException.Create('Repositorio de lacunas nao informado.');
  if AGapRecovery = nil then
    raise EArgumentNilException.Create('Recuperacao de lacunas nao informada.');
  if (ACommandRepository = nil) or (ACommandProcessor = nil) then
    raise EArgumentNilException.Create('Processamento de comandos nao informado.');
  FCommandRepository := ACommandRepository;
  FCommandProcessor := ACommandProcessor;
  FLeaseRepository := ALeaseRepository;
  FCycle := ACycle;
  FGapRepository := AGapRepository;
  FGapRecovery := AGapRecovery;
end;

function TMonitoringWorker.RunOnce(const AWorkerId: string; const ABatchSize,
  ALeaseSeconds: Integer): Integer;
var
  Leases: TArray<TMonitorLease>;
  Gaps: TArray<TMonitorGapLease>;
  Commands: TArray<TMonitorCommandLease>;
  Index: Integer;
begin
  ValidateLeaseRequest(AWorkerId, ABatchSize, ALeaseSeconds);
  Result := 0;
  // Reclama apenas o trabalho que sera executado agora.
  for Index := 1 to ABatchSize do
  begin
    Leases := FLeaseRepository.ClaimDue(AWorkerId, 1, ALeaseSeconds);
    if Length(Leases) > 0 then
      FCycle.Execute(AWorkerId, Leases[0], Now)
    else
    begin
      Commands := FCommandRepository.ClaimDue(AWorkerId, 1, ALeaseSeconds);
      if Length(Commands) > 0 then
        FCommandProcessor.Execute(AWorkerId, Commands[0])
      else
      begin
        Gaps := FGapRepository.ClaimDue(AWorkerId, 1, ALeaseSeconds);
        if Length(Gaps) = 0 then Break;
        FGapRecovery.Execute(AWorkerId, Gaps[0]);
      end;
    end;
    Inc(Result);
  end;
end;

end.
