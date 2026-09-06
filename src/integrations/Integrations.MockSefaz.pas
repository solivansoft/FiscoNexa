unit Integrations.MockSefaz;

interface

uses Application.MonitorCycle;

type
  TMockDistributionGateway = class(TInterfacedObject, IDistributionGateway, IXmlRetrievalGateway)
  private
    FResponse: TDistributionResponse;
  public
    function QueryDocument(const ACompanyId, AAccessKey: string): TDistributionResponse;
    constructor Create(const AResponse: TDistributionResponse);
    function QueryDistribution(const ACompanyId, ALastNsu: string): TDistributionResponse;
    function QueryDistributionByNsu(const ACompanyId, ANsu: string): TDistributionResponse;
  end;

implementation

constructor TMockDistributionGateway.Create(const AResponse: TDistributionResponse);
begin
  inherited Create;
  FResponse := AResponse;
end;

function TMockDistributionGateway.QueryDistribution(const ACompanyId,
  ALastNsu: string): TDistributionResponse;
begin
  Result := FResponse;
end;

function TMockDistributionGateway.QueryDistributionByNsu(const ACompanyId,
  ANsu: string): TDistributionResponse;
begin
  Result := FResponse;
end;

function TMockDistributionGateway.QueryDocument(const ACompanyId, AAccessKey: string): TDistributionResponse;
begin
  Result := FResponse;
end;

end.
