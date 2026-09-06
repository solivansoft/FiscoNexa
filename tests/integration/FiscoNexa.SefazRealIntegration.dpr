program FiscoNexa.SefazRealIntegration;

{$APPTYPE CONSOLE}

uses
  System.IOUtils,
  System.SysUtils,
  Application.BrazilianStates in '..\..\src\application\Application.BrazilianStates.pas',
  Application.CertificateIdentity in '..\..\src\application\Application.CertificateIdentity.pas',
  Application.CertificateMaterial in '..\..\src\application\Application.CertificateMaterial.pas',
  Application.MonitorCycle in '..\..\src\application\Application.MonitorCycle.pas',
  Integrations.AcbrSefaz in '..\..\src\integrations\Integrations.AcbrSefaz.pas',
  Integrations.OpenSslCertificate in '..\..\src\integrations\Integrations.OpenSslCertificate.pas';

type
  TFileCertificateProvider = class(TInterfacedObject, IActiveCertificateProvider)
  private
    FMaterial: TActiveCertificateMaterial;
  public
    constructor Create(const APfxPath, APassword, AState: string);
    destructor Destroy; override;
    function LoadActive(const ACompanyId: string): TActiveCertificateMaterial;
  end;

function RequiredEnvironmentValue(const AName: string): string;
begin
  Result := Trim(GetEnvironmentVariable(AName));
  if Result = '' then
    raise EInvalidOpException.Create('Variavel obrigatoria ausente: ' + AName);
end;

constructor TFileCertificateProvider.Create(const APfxPath, APassword,
  AState: string);
var
  Inspector: ICertificateInspector;
  Identity: TCertificateIdentity;
begin
  inherited Create;
  if not TFile.Exists(APfxPath) then
    raise EInvalidOpException.Create('Arquivo PFX nao encontrado.');
  FMaterial.Pfx := TFile.ReadAllBytes(APfxPath);
  FMaterial.Password := TEncoding.UTF8.GetBytes(APassword);
  Inspector := TOpenSslCertificateInspector.Create;
  Identity := Inspector.Inspect(FMaterial.Pfx, FMaterial.Password);
  FMaterial.Cnpj := Identity.Cnpj;
  FMaterial.State := UpperCase(Trim(AState));
  BrazilianStateCode(FMaterial.State);
end;

destructor TFileCertificateProvider.Destroy;
begin
  ClearActiveCertificateMaterial(FMaterial);
  inherited;
end;

function TFileCertificateProvider.LoadActive(
  const ACompanyId: string): TActiveCertificateMaterial;
begin
  if ACompanyId <> 'sefaz-real-test' then
    raise EInvalidOpException.Create('Identificador de teste inesperado.');
  Result.Cnpj := FMaterial.Cnpj;
  Result.State := FMaterial.State;
  Result.Pfx := Copy(FMaterial.Pfx);
  Result.Password := Copy(FMaterial.Password);
end;

procedure RequireRealConfirmation;
begin
  if GetEnvironmentVariable('FISCONEXA_SEFAZ_REAL_CONFIRMATION') <> 'YES' then
    raise EInvalidOpException.Create(
      'Defina FISCONEXA_SEFAZ_REAL_CONFIRMATION=YES para consultar a SEFAZ real.');
end;

var
  Provider: IActiveCertificateProvider;
  Gateway: IDistributionGateway;
  Response: TDistributionResponse;
begin
  RequireRealConfirmation;
  Provider := TFileCertificateProvider.Create(
    RequiredEnvironmentValue('FISCONEXA_TEST_PFX_PATH'),
    RequiredEnvironmentValue('FISCONEXA_TEST_PFX_PASSWORD'),
    RequiredEnvironmentValue('FISCONEXA_TEST_SEFAZ_UF'));
  Gateway := TAcbrSefazDistributionGateway.Create(Provider, False);
  Response := Gateway.QueryDistribution('sefaz-real-test', '0');
  if Response.CStat = 0 then
    raise EInvalidOpException.Create('SEFAZ nao retornou cStat.');
  Writeln('Consulta SEFAZ concluida: cStat=', Response.CStat,
    '; ultNSU=', Response.ReturnedNsu, '; maxNSU=', Response.MaxNsu,
    '; documentos=', Length(Response.Documents));
  Writeln('Nenhuma ciencia foi registrada; este teste executa somente distNSU.');
end.
