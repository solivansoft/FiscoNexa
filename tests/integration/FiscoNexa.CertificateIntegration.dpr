program FiscoNexa.CertificateIntegration;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  Application.CertificateIdentity in '..\..\src\application\Application.CertificateIdentity.pas',
  Integrations.OpenSslCertificate in '..\..\src\integrations\Integrations.OpenSslCertificate.pas';

var
  Inspector: ICertificateInspector;
  Identity: TCertificateIdentity;
  PfxPath: string;
  Password: string;
  ExpectedCnpj: string;
begin
  try
    PfxPath := GetEnvironmentVariable('FISCONEXA_TEST_PFX_PATH');
    Password := GetEnvironmentVariable('FISCONEXA_TEST_PFX_PASSWORD');
    ExpectedCnpj := GetEnvironmentVariable('FISCONEXA_TEST_CNPJ');
    if (PfxPath = '') or (Password = '') or (ExpectedCnpj = '') then
      raise EInvalidOpException.Create('Fixture de certificado nao configurada.');
    Inspector := TOpenSslCertificateInspector.Create;
    Identity := Inspector.Inspect(TFile.ReadAllBytes(PfxPath),
      TEncoding.UTF8.GetBytes(Password));
    if Identity.Cnpj <> ExpectedCnpj then
      raise EInvalidOpException.Create('CNPJ extraido diferente da fixture.');
    if Identity.ValidUntil <= Now then
      raise EInvalidOpException.Create('Validade da fixture nao foi extraida.');
    Writeln('Smoke certificado aprovado: PFX, senha, CNPJ e validade validados.');
  except
    on E: Exception do
    begin
      Writeln('Smoke certificado recusado: ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
