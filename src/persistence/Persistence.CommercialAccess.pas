unit Persistence.CommercialAccess;

interface

uses
  Application.CommercialAccess,
  FireDAC.Comp.Client;

function SalvarLicenca(const AConnection: TFDConnection;
  const AUpdate: TCommercialAccessUpdate): TCommercialAccessResult;
function EntregaComercialPermitida(const AConnection: TFDConnection;
  const ACompanyId: string; out AProtectedUntil: string): Boolean;

implementation

uses
  FireDAC.Stan.Param,
  System.DateUtils,
  System.SysUtils;

function SalvarLicenca(const AConnection: TFDConnection;
  const AUpdate: TCommercialAccessUpdate): TCommercialAccessResult;
var Q: TFDQuery; ExistingVersion: Int64; ExistingStatus, ExistingAccess,
  ExistingProtection, ExistingReference: string;
begin
  ValidateCommercialAccessUpdate(AUpdate);
  AConnection.StartTransaction;
  try
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := AConnection;
      Q.SQL.Text := 'select id from empresas where id=cast(:id as uuid) for update';
      Q.ParamByName('id').AsString := AUpdate.CompanyId;
      Q.Open;
      if Q.IsEmpty then raise ELicenseCompanyNotFound.Create('Empresa nao encontrada.');
      Q.Close;
      Q.SQL.Text := 'select situacao,coalesce(acesso_liberado_ate::text,''''),'+
        'coalesce(proteger_monitoramento_ate::text,''''),referencia,versao_origem '+
        'from licencas where company_id=cast(:id as uuid) for update';
      Q.ParamByName('id').AsString := AUpdate.CompanyId; Q.Open;
      if not Q.IsEmpty then
      begin
        ExistingStatus := Q.Fields[0].AsString; ExistingAccess := Q.Fields[1].AsString;
        ExistingProtection := Q.Fields[2].AsString; ExistingReference := Q.Fields[3].AsString;
        ExistingVersion := Q.Fields[4].AsLargeInt;
        if AUpdate.SourceVersion < ExistingVersion then
          raise ELicenseValidation.Create('Versao da origem desatualizada.');
        if AUpdate.SourceVersion = ExistingVersion then
        begin
          if (ExistingStatus <> AUpdate.Status) or
             (ExistingReference <> AUpdate.Reference) or
             ((ExistingAccess = '') <> (AUpdate.AccessGrantedUntil = '')) or
             ((ExistingProtection = '') <> (AUpdate.MonitoringProtectedUntil = '')) then
            raise ELicenseValidation.Create('Versao repetida com conteudo divergente.');
          Q.Close;
          Q.SQL.Text := 'select (acesso_liberado_ate is not distinct from '+
            'cast(nullif(:acesso,'''') as timestamptz)) and '+
            '(proteger_monitoramento_ate is not distinct from '+
            'cast(nullif(:protecao,'''') as timestamptz)) from licencas '+
            'where company_id=cast(:id as uuid)';
          Q.ParamByName('id').AsString := AUpdate.CompanyId;
          Q.ParamByName('acesso').AsString := AUpdate.AccessGrantedUntil;
          Q.ParamByName('protecao').AsString := AUpdate.MonitoringProtectedUntil;
          Q.Open;
          if not Q.Fields[0].AsBoolean then
            raise ELicenseValidation.Create('Versao repetida com prazos divergentes.');
          Result.Replayed := True;
          Result.Status := ExistingStatus;
          Result.AccessGrantedUntil := AUpdate.AccessGrantedUntil;
          Result.MonitoringProtectedUntil := AUpdate.MonitoringProtectedUntil;
          Result.SourceVersion := ExistingVersion;
          AConnection.Commit;
          Exit;
        end;
      end;
      Q.Close;
      Q.SQL.Text := 'insert into licencas(company_id,situacao,'+
        'acesso_liberado_ate,proteger_monitoramento_ate,referencia,versao_origem) '+
        'values(cast(:id as uuid),:situacao,cast(nullif(:acesso,'''') as timestamptz),'+
        'cast(nullif(:protecao,'''') as timestamptz),:referencia,:versao) '+
        'on conflict(company_id) do update set situacao=excluded.situacao,'+
        'acesso_liberado_ate=excluded.acesso_liberado_ate,'+
        'proteger_monitoramento_ate=excluded.proteger_monitoramento_ate,'+
        'referencia=excluded.referencia,versao_origem=excluded.versao_origem,updated_at=now()';
      Q.ParamByName('id').AsString := AUpdate.CompanyId;
      Q.ParamByName('situacao').AsString := AUpdate.Status;
      Q.ParamByName('acesso').AsString := AUpdate.AccessGrantedUntil;
      Q.ParamByName('protecao').AsString := AUpdate.MonitoringProtectedUntil;
      Q.ParamByName('referencia').AsString := AUpdate.Reference;
      Q.ParamByName('versao').AsLargeInt := AUpdate.SourceVersion; Q.Execute;
      Q.SQL.Text := 'insert into auditorias(company_id,event_type,payload) values('+
        'cast(:id as uuid),''licenca.atualizada'',jsonb_build_object('+
        '''situacao'',cast(:situacao as text),''referencia'',cast(:referencia as text),'+
        '''versao_origem'',cast(:versao as bigint)))'; Q.Execute;
      Result.Replayed := False; Result.Status := AUpdate.Status;
      Result.AccessGrantedUntil := AUpdate.AccessGrantedUntil;
      Result.MonitoringProtectedUntil := AUpdate.MonitoringProtectedUntil;
      Result.SourceVersion := AUpdate.SourceVersion;
    finally Q.Free; end;
    AConnection.Commit;
  except
    AConnection.Rollback;
    raise;
  end;
end;

function EntregaComercialPermitida(const AConnection: TFDConnection;
  const ACompanyId: string; out AProtectedUntil: string): Boolean;
var Q: TFDQuery;
begin
  AProtectedUntil := '';
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := AConnection;
    Q.SQL.Text := 'select entrega_permitida,monitoramento_protegido_ate::text from acessos_assinatura '+
      'where company_id=cast(:id as uuid)';
    Q.ParamByName('id').AsString := ACompanyId; Q.Open;
    if Q.IsEmpty then Exit(False);
    AProtectedUntil := Q.Fields[1].AsString;
    Result := Q.Fields[0].AsBoolean;
  finally Q.Free; end;
end;

end.
