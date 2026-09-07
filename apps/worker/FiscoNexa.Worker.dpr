program FiscoNexa.Worker;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Application.MonitorCommands,
  Persistence.MonitorCommands,
  FireDAC.Stan.Param, FireDAC.Comp.Client,
  Application.CertificateEnvelope in '..\..\src\application\Application.CertificateEnvelope.pas',
  Application.CertificateMaterial in '..\..\src\application\Application.CertificateMaterial.pas',
  Application.MonitorCycle in '..\..\src\application\Application.MonitorCycle.pas',
  Application.MonitorGaps in '..\..\src\application\Application.MonitorGaps.pas',
  Application.MonitorLeases in '..\..\src\application\Application.MonitorLeases.pas',
  Database.Connection in '..\..\src\db\Database.Connection.pas',
  Integrations.AcbrSefaz in '..\..\src\integrations\Integrations.AcbrSefaz.pas',
  Integrations.AwsKms in '..\..\src\integrations\Integrations.AwsKms.pas',
  Integrations.AwsKmsTransport in '..\..\src\integrations\Integrations.AwsKmsTransport.pas',
  Integrations.AwsS3Xml in '..\..\src\integrations\Integrations.AwsS3Xml.pas',
  Integrations.MockSefaz in '..\..\src\integrations\Integrations.MockSefaz.pas',
  Integrations.OpenSslCipher in '..\..\src\integrations\Integrations.OpenSslCipher.pas',
  Persistence.CertificateMaterial in '..\..\src\persistence\Persistence.CertificateMaterial.pas',
  Persistence.MonitorCycles in '..\..\src\persistence\Persistence.MonitorCycles.pas',
  Persistence.MonitorGaps in '..\..\src\persistence\Persistence.MonitorGaps.pas',
  Persistence.MonitorLeases in '..\..\src\persistence\Persistence.MonitorLeases.pas',
  Operations.StructuredLogs,
  Worker.Monitoring in '..\..\src\worker\Worker.Monitoring.pas';

function RequiredEnvironmentValue(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise EInvalidOpException.Create('Variavel obrigatoria ausente: ' + AName);
end;

function PositiveEnvironmentInteger(const AName: string;
  const ADefault: Integer): Integer;
var
  Value: string;
begin
  Value := GetEnvironmentVariable(AName);
  if Value = '' then
    Exit(ADefault);
  Result := StrToIntDef(Value, 0);
  if Result <= 0 then
    raise EInvalidOpException.Create('Variavel deve ser inteira positiva: ' + AName);
end;

function EnvironmentBoolean(const AName: string; const ADefault: Boolean): Boolean;
var Value: string;
begin
  Value := LowerCase(Trim(GetEnvironmentVariable(AName)));
  if Value = '' then Exit(ADefault);
  if Value = 'true' then Exit(True);
  if Value = 'false' then Exit(False);
  raise EInvalidOpException.Create('Variavel deve ser true ou false: ' + AName);
end;

function MockResponseFromEnvironment: TDistributionResponse;
begin
  Result := Default(TDistributionResponse);
  Result.CStat := PositiveEnvironmentInteger('FISCONEXA_MOCK_SEFAZ_CSTAT', 0);
  Result.ReturnedNsu := GetEnvironmentVariable('FISCONEXA_MOCK_SEFAZ_RETURNED_NSU');
  Result.MaxNsu := GetEnvironmentVariable('FISCONEXA_MOCK_SEFAZ_MAX_NSU');
  Result.MessageText := GetEnvironmentVariable('FISCONEXA_MOCK_SEFAZ_MESSAGE');
end;

type
  TEmptyXmlStorage = class(TInterfacedObject, IXmlStorage)
  public
    function Put(const ACompanyCnpj, AAccessKey, AXml: string): TStoredXml;
  end;

function TEmptyXmlStorage.Put(const ACompanyCnpj, AAccessKey,
  AXml: string): TStoredXml;
begin
  raise EInvalidOpException.Create('Modo mock nao aceita persistencia de XML.');
end;

procedure ExecutarWorker;
var
  Connection: TFDConnection;
  LeaseRepository: IMonitorLeaseRepository;
  CycleWriter: IMonitorCycleWriter;
  GapRepository: IMonitorGapRepository;
  Gateway: IDistributionGateway;
  StoredCertificateReader: IStoredCertificateReader;
  CertificateProvider: IActiveCertificateProvider;
  XmlStorage: IXmlStorage;
  KmsTransport: IAwsKmsTransport;
  KeyService: IEnvelopeKeyService;
  Decipher: IEnvelopeDecipher;
  CommandRepository: IMonitorCommandRepository;
  CommandProcessor: TMonitorCommandProcessor;
  Cycle: TMonitorCycle;
  GapRecovery: TMonitorGapRecovery;
  Worker: TMonitoringWorker;
  WorkerId: string;
  SefazMode: string;
  ProcessedCount: Integer;
begin
  SefazMode := LowerCase(GetEnvironmentVariable('FISCONEXA_SEFAZ_MODE'));
  if (SefazMode <> 'mock') and (SefazMode <> 'acbr') then
    raise EInvalidOpException.Create(
      'FISCONEXA_SEFAZ_MODE deve ser mock ou acbr.');
  Connection := TDatabaseConnection.OpenFromEnvironment;
  try
    WorkerId := RequiredEnvironmentValue('FISCONEXA_WORKER_ID');
    LeaseRepository := TPostgresMonitorLeaseRepository.Create(Connection);
    CycleWriter := TPostgresMonitorCycleWriter.Create(Connection);
    GapRepository := TPostgresMonitorGapRepository.Create(Connection);
    if SefazMode = 'mock' then
    begin
      Gateway := TMockDistributionGateway.Create(MockResponseFromEnvironment);
      XmlStorage := TEmptyXmlStorage.Create;
    end
    else
    begin
      KmsTransport := TAwsKmsSignedTransport.CreateFromEnvironment;
      KeyService := TAwsKmsDataKeyService.Create(KmsTransport,
        RequiredEnvironmentValue('AWS_REGION'),
        RequiredEnvironmentValue('FISCONEXA_KMS_KEY_ID'));
      Decipher := TOpenSslGcmCipher.Create;
      StoredCertificateReader := TPostgresStoredCertificateReader.Create(Connection);
      CertificateProvider := TActiveCertificateService.Create(StoredCertificateReader,
        KeyService, Decipher);
      Gateway := TAcbrSefazDistributionGateway.Create(CertificateProvider,
        EnvironmentBoolean('FISCONEXA_AUTO_AWARENESS', True));
      XmlStorage := TAwsS3XmlStorage.CreateFromEnvironment;
    end;
    Cycle := TMonitorCycle.Create(Gateway, CycleWriter, XmlStorage);
    try
      GapRecovery := TMonitorGapRecovery.Create(Gateway, GapRepository, XmlStorage);
      try
        CommandRepository := TPostgresMonitorCommandRepository.Create(Connection);
        CommandProcessor := TMonitorCommandProcessor.Create(Gateway as IXmlRetrievalGateway,
          CommandRepository, XmlStorage);
        try
          Worker := TMonitoringWorker.Create(LeaseRepository, Cycle, GapRepository, GapRecovery,
            CommandRepository, CommandProcessor);
          try
            ProcessedCount := Worker.RunOnce(WorkerId,
              PositiveEnvironmentInteger('FISCONEXA_WORKER_BATCH_SIZE', 50),
              PositiveEnvironmentInteger('FISCONEXA_WORKER_LEASE_SECONDS', 300));
            RegistrarLog('info', 'worker', 'ciclo_worker_concluido',
              Format('{"tarefas_processadas":%d}', [ProcessedCount]));
          finally
            Worker.Free;
          end;
        finally
          CommandProcessor.Free;
        end;
      finally
        GapRecovery.Free;
      end;
    finally
      Cycle.Free;
    end;
  finally
    Connection.Free;
  end;
end;

begin
  try
    ExecutarWorker;
  except
    on E: Exception do
    begin
      RegistrarLog('erro', 'worker', 'worker_interrompido',
        '{"classe":"' + E.ClassName + '"}');
      ExitCode := 1;
    end;
  end;
end.
