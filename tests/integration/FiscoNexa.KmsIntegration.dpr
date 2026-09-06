program FiscoNexa.KmsIntegration;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Application.CertificateEnvelope in '..\..\src\application\Application.CertificateEnvelope.pas',
  Integrations.AwsKms in '..\..\src\integrations\Integrations.AwsKms.pas',
  Integrations.AwsKmsTransport in '..\..\src\integrations\Integrations.AwsKmsTransport.pas',
  Integrations.AwsSignature in '..\..\src\integrations\Integrations.AwsSignature.pas';

procedure ClearBytes(var AValue: TBytes);
begin
  if Length(AValue) > 0 then
    FillChar(AValue[0], Length(AValue), 0);
  AValue := nil;
end;

var
  Transport: IAwsKmsTransport;
  Service: TAwsKmsDataKeyService;
  DataKey: TEnvelopeDataKey;
  RecoveredKey: TBytes;
  KeyReference: string;
  Index: Integer;
begin
  KeyReference := GetEnvironmentVariable('AWS_KMS_CERTIFICATES_KEY_ID');
  if KeyReference = '' then
    KeyReference := 'alias/fisconexa-certificates';
  Transport := TAwsKmsSignedTransport.CreateFromEnvironment;
  Service := TAwsKmsDataKeyService.Create(Transport,
    GetEnvironmentVariable('AWS_REGION'), KeyReference);
  try
    DataKey := Service.GenerateDataKey;
    try
      if Length(DataKey.PlaintextKey) <> 32 then
        raise EInvalidOpException.Create('KMS nao retornou uma data key AES-256.');
      if Length(DataKey.EncryptedKey) = 0 then
        raise EInvalidOpException.Create('KMS nao retornou a data key cifrada.');
      RecoveredKey := Service.DecryptDataKey(DataKey.EncryptedKey);
      try
        if Length(RecoveredKey) <> Length(DataKey.PlaintextKey) then
          raise EInvalidOpException.Create('KMS retornou uma data key com tamanho inesperado.');
        for Index := 0 to High(RecoveredKey) do
          if RecoveredKey[Index] <> DataKey.PlaintextKey[Index] then
            raise EInvalidOpException.Create('KMS nao recuperou a mesma data key.');
      finally
        ClearBytes(RecoveredKey);
      end;
      Writeln('Smoke KMS aprovado: GenerateDataKey retornou envelope AES-256.');
    finally
      ClearBytes(DataKey.PlaintextKey);
      ClearBytes(DataKey.EncryptedKey);
    end;
  finally
    Service.Free;
  end;
end.
