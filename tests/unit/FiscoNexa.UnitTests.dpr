program FiscoNexa.UnitTests;

{$APPTYPE CONSOLE}

uses
  TestFramework,
  Tests.Assinaturas in 'Tests.Assinaturas.pas',
  Tests.ErrorDescription in 'Tests.ErrorDescription.pas',
  Tests.PostgresText in 'Tests.PostgresText.pas',
  Tests.Licencas in 'Tests.Licencas.pas',
  Tests.MonitorCommands in 'Tests.MonitorCommands.pas',
  Tests.AwsSignature in 'Tests.AwsSignature.pas',
  Tests.BrazilianStates in 'Tests.BrazilianStates.pas',
  Tests.Authentication in 'Tests.Authentication.pas',
  Tests.AwsKms in 'Tests.AwsKms.pas',
  Tests.CertificateEnvelope in 'Tests.CertificateEnvelope.pas',
  Tests.CertificateIdentity in 'Tests.CertificateIdentity.pas',
  Tests.CompanyOnboarding in 'Tests.CompanyOnboarding.pas',
  Tests.Passwords in 'Tests.Passwords.pas',
  Tests.ErpIntegration in 'Tests.ErpIntegration.pas',
  Tests.ErpAdministration in 'Tests.ErpAdministration.pas',
  Tests.ErpKeys in 'Tests.ErpKeys.pas',
  Tests.ErpKeyReader in 'Tests.ErpKeyReader.pas',
  Tests.MonitorLeases in 'Tests.MonitorLeases.pas',
  Tests.MonitorCycle in 'Tests.MonitorCycle.pas',
  Tests.MonitorGaps in 'Tests.MonitorGaps.pas',
  Tests.OpenSslCipher in 'Tests.OpenSslCipher.pas',
  Tests.OpenSslCertificate in 'Tests.OpenSslCertificate.pas',
  Tests.SefazMonitoringPolicy in 'Tests.SefazMonitoringPolicy.pas',
  Tests.SchemaDefinition in 'Tests.SchemaDefinition.pas';

begin
  TTestRunner.RunTests;
end.
