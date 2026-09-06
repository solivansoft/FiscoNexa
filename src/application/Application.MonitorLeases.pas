unit Application.MonitorLeases;

interface

uses
  System.SysUtils;

type
  EMonitorLeaseValidation = class(Exception);

  TMonitorLease = record
    CompanyId: string;
    Cnpj: string;
    LastNsu: string;
    LastCStat: Integer;
    BlockedCount: Integer;
    FailureCount: Integer;
  end;

  IMonitorLeaseRepository = interface
    ['{8398F0FE-BA40-4EE7-BA3E-1EBF8D4A61CB}']
    function ClaimDue(const AWorkerId: string; const ABatchSize,
      ALeaseSeconds: Integer): TArray<TMonitorLease>;
  end;

procedure ValidateLeaseRequest(const AWorkerId: string; const ABatchSize,
  ALeaseSeconds: Integer);

implementation

procedure ValidateLeaseRequest(const AWorkerId: string; const ABatchSize,
  ALeaseSeconds: Integer);
begin
  if Trim(AWorkerId) = '' then
    raise EMonitorLeaseValidation.Create('Identificador do worker obrigatorio.');
  if ABatchSize <= 0 then
    raise EMonitorLeaseValidation.Create('Lote do worker deve ser positivo.');
  if ALeaseSeconds <= 0 then
    raise EMonitorLeaseValidation.Create('Duracao da lease deve ser positiva.');
end;

end.
