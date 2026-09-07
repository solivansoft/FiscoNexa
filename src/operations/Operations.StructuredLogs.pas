unit Operations.StructuredLogs;

interface

procedure RegistrarLog(const ANivel, AServico, AEvento: string;
  const ADadosJson: string = '{}');

implementation

uses
  System.DateUtils,
  System.JSON,
  System.Classes,
  System.IOUtils,
  System.SysUtils;

var LogLock: TObject;

function NomeSeguro(const AValor: string): string;
var C: Char;
begin
  Result := '';
  for C in Copy(AValor, 1, 80) do
    if CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) then
      Result := Result + C;
  if Result = '' then Result := 'local';
end;

procedure GravarArquivo(const AServico, AInstancia, ALinha: string);
const MaxBytes = 10 * 1024 * 1024; Retidos = 5;
var Pasta, Nome, Origem, Destino: string; I: Integer;
  Arquivo: TFileStream; Bytes: TBytes;
begin
  Pasta := GetEnvironmentVariable('FISCONEXA_LOG_DIR');
  if Pasta = '' then Pasta := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
  ForceDirectories(Pasta);
  Nome := TPath.Combine(Pasta, NomeSeguro(AServico) + '-' + NomeSeguro(AInstancia));
  Bytes := TEncoding.UTF8.GetBytes(ALinha + #10);
  if TFile.Exists(Nome + '.log') then
  begin
    Arquivo := TFileStream.Create(Nome + '.log', fmOpenRead or fmShareDenyNone);
    try I := Ord(Arquivo.Size + Length(Bytes) > MaxBytes); finally Arquivo.Free; end;
    if I <> 0 then
    begin
      Destino := Nome + '.' + IntToStr(Retidos) + '.log';
      if TFile.Exists(Destino) then TFile.Delete(Destino);
      for I := Retidos - 1 downto 0 do
      begin
        if I = 0 then Origem := Nome + '.log'
        else Origem := Nome + '.' + IntToStr(I) + '.log';
        Destino := Nome + '.' + IntToStr(I + 1) + '.log';
        if TFile.Exists(Origem) then TFile.Move(Origem, Destino);
      end;
    end;
  end;
  if TFile.Exists(Nome + '.log') then
    Arquivo := TFileStream.Create(Nome + '.log', fmOpenReadWrite or fmShareDenyWrite)
  else Arquivo := TFileStream.Create(Nome + '.log', fmCreate or fmShareDenyWrite);
  try
    Arquivo.Seek(0, soEnd);
    if Length(Bytes) > 0 then Arquivo.WriteBuffer(Bytes[0], Length(Bytes));
  finally Arquivo.Free; end;
end;

procedure RegistrarLog(const ANivel, AServico, AEvento, ADadosJson: string);
var Root: TJSONObject; Data: TJSONValue; InstanceId, Version, Linha: string;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('timestamp', DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True));
    Root.AddPair('projeto', 'fisconexa');
    Root.AddPair('ambiente', Copy(GetEnvironmentVariable('FISCONEXA_ENVIRONMENT'), 1, 80));
    Root.AddPair('nivel', Copy(ANivel, 1, 20)); Root.AddPair('servico', Copy(AServico, 1, 80));
    Root.AddPair('evento', Copy(AEvento, 1, 160));
    InstanceId := GetEnvironmentVariable('FISCONEXA_INSTANCE_ID');
    InstanceId := NomeSeguro(InstanceId);
    Root.AddPair('instancia', InstanceId);
    Version := GetEnvironmentVariable('FISCONEXA_VERSION');
    if Version <> '' then Root.AddPair('versao', Copy(Version, 1, 80));
    if Length(ADadosJson) <= 16384 then Data := TJSONObject.ParseJSONValue(ADadosJson)
    else Data := TJSONObject.ParseJSONValue('{"dados_omitidos":"limite_de_tamanho"}');
    if Data = nil then Data := TJSONObject.Create;
    Root.AddPair('dados', Data);
    Linha := Root.ToJSON;
    TMonitor.Enter(LogLock);
    try
      try
        GravarArquivo(AServico, InstanceId, Linha);
      except
        on E: Exception do
          try Writeln(ErrOutput, '{"nivel":"erro","evento":"falha_gravacao_log"}'); except end;
      end;
      if not SameText(GetEnvironmentVariable('FISCONEXA_LOG_CONSOLE'), 'false') then
        try Writeln(Linha); Flush(Output); except end;
    finally TMonitor.Exit(LogLock); end;
  finally Root.Free; end;
end;

initialization
  LogLock := TObject.Create;
finalization
  LogLock.Free;
end.
