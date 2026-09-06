program FiscoNexa.S3Integration;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Application.MonitorCycle in '..\..\src\application\Application.MonitorCycle.pas',
  Integrations.AwsSignature in '..\..\src\integrations\Integrations.AwsSignature.pas',
  Integrations.AwsS3Xml in '..\..\src\integrations\Integrations.AwsS3Xml.pas';

var
  Storage: TAwsS3XmlStorage;
  Stored: TStoredXml;
  AccessKey: string;
  Xml: string;
begin
  AccessKey := 's3smoke' + FormatDateTime('yyyymmddhhnnsszzz', Now);
  Storage := TAwsS3XmlStorage.CreateFromEnvironment;
  try
    Xml := '<fisconexa-smoke>xml-assinado</fisconexa-smoke>';
    Stored := Storage.Put('00000000000000', AccessKey, Xml);
    if (Stored.ObjectKey = '') or (Stored.Sha256 = '') then
      raise EInvalidOpException.Create('S3 nao retornou a identidade do objeto.');
    if Storage.Get(Stored.ObjectKey) <> Xml then
      raise EInvalidOpException.Create('S3 nao devolveu o XML enviado.');
    Writeln('Smoke S3 aprovado: ', Stored.ObjectKey, ' ', Stored.Sha256);
  finally
    Storage.Free;
  end;
end.
