unit Tests.OpenSslCertificate;

interface

uses
  TestFramework;

type
  TOpenSslCertificateTests = class(TTestCase)
  public
    procedure TestInspectRejectsInvalidPfx;
  end;

implementation

uses
  System.SysUtils,
  Application.CertificateIdentity,
  Integrations.OpenSslCertificate;

procedure TOpenSslCertificateTests.TestInspectRejectsInvalidPfx;
var
  Inspector: TOpenSslCertificateInspector;
begin
  Inspector := TOpenSslCertificateInspector.Create;
  try
    try
      Inspector.Inspect(TBytes.Create(1, 2, 3), TBytes.Create(4));
      Fail('PFX invalido foi aceito.');
    except
      on E: ECertificateInvalid do
        AssertTrue(True);
    end;
  finally
    Inspector.Free;
  end;
end;

initialization

TTestHelper.RegisterTest(TOpenSslCertificateTests.Create);

end.
