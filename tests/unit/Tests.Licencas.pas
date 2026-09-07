unit Tests.Licencas;
interface
uses TestFramework;
type TLicencasTests = class(TTestCase)
public
  procedure TestAceitaPrazoComFuso;
  procedure TestRecusaPrazoSemFuso;
  procedure TestRecusaEmpresaInvalida;
  procedure TestRecusaSituacaoInvalida;
end;
implementation
uses Application.CommercialAccess;
function Atualizacao: TCommercialAccessUpdate;
begin
  Result := Default(TCommercialAccessUpdate);
  Result.CompanyId := '00000000-0000-0000-0000-000000000001';
  Result.Status := 'restrito';
  Result.Reference := 'teste';
end;
procedure TLicencasTests.TestAceitaPrazoComFuso;
var U: TCommercialAccessUpdate;
begin
  U := Atualizacao;
  U.AccessGrantedUntil := '2026-10-01T00:00:00-03:00';
  U.MonitoringProtectedUntil := '2026-11-01T00:00:00Z';
  ValidateCommercialAccessUpdate(U);
  AssertTrue(True);
end;
procedure TLicencasTests.TestRecusaPrazoSemFuso;
var U: TCommercialAccessUpdate;
begin
  U := Atualizacao;
  U.AccessGrantedUntil := '2026-10-01T00:00:00';
  try ValidateCommercialAccessUpdate(U); Fail('Prazo ambiguo aceito.');
  except on E: ELicenseValidation do AssertTrue(True); end;
end;
procedure TLicencasTests.TestRecusaEmpresaInvalida;
var U: TCommercialAccessUpdate;
begin
  U := Atualizacao; U.CompanyId := 'invalido';
  try ValidateCommercialAccessUpdate(U); Fail('Empresa invalida aceita.');
  except on E: ELicenseValidation do AssertTrue(True); end;
end;
procedure TLicencasTests.TestRecusaSituacaoInvalida;
var U: TCommercialAccessUpdate;
begin
  U := Atualizacao; U.Status := 'qualquer';
  try ValidateCommercialAccessUpdate(U); Fail('Situacao invalida aceita.');
  except on E: ELicenseValidation do AssertTrue(True); end;
end;
initialization
  TTestHelper.RegisterTest(TLicencasTests.Create);
end.
