unit Tests.CertificateIdentity;

interface

uses
  TestFramework;

type
  TCertificateIdentityTests = class(TTestCase)
  public
    procedure TestExtractCnpjFromBrazilianOid;
    procedure TestExtractCnpjFromCommonName;
    procedure TestExtractCnpjRejectsMissingOid;
    procedure TestExtractCnpjRejectsShortValue;
  end;

implementation

uses
  Application.CertificateIdentity;

procedure TCertificateIdentityTests.TestExtractCnpjFromBrazilianOid;
begin
  AssertEquals('12345678000190', ExtractCnpjFromCertificateSubject(
    'CN=EMPRESA TESTE:12345678000190,2.16.76.1.3.3=12345678000190,O=ICP-Brasil'));
end;

procedure TCertificateIdentityTests.TestExtractCnpjFromCommonName;
begin
  AssertEquals('15682606000121', ExtractCnpjFromCertificateSubject(
    'CN=EMPRESA TESTE:15682606000121,OU=e-CNPJ A1,O=ICP-Brasil'));
end;

procedure TCertificateIdentityTests.TestExtractCnpjRejectsMissingOid;
begin
  AssertEquals('', ExtractCnpjFromCertificateSubject('CN=Empresa 12345678000190'));
end;

procedure TCertificateIdentityTests.TestExtractCnpjRejectsShortValue;
begin
  AssertEquals('', ExtractCnpjFromCertificateSubject('2.16.76.1.3.3=12345678'));
end;

initialization

TTestHelper.RegisterTest(TCertificateIdentityTests.Create);

end.
