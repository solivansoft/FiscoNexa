unit Application.ErpDocuments;

interface

type
  TErpXmlRequest = record
    Found: Boolean;
    ObjectKey: string;
    CommandId: string;
    CommandStatus: string;
    CommandCStat: Integer;
  end;

  TErpDocumentSummary = record
    Nsu: Int64;
    Id: string;
    AccessKey: string;
    DocumentType: string;
    IssuedAt: string;
    IssuerCnpj: string;
    IssuerName: string;
    OperationType: string;
    FiscalStatus: string;
    TotalAmount: string;
    Status: string;
    XmlAvailable: Boolean;
    AwarenessCStat: Integer;
  end;

  TErpDocumentPage = record
    Items: TArray<TErpDocumentSummary>;
    LastNsu: Int64;
  end;

function ListErpDocuments(const ACompanyId: string; const ASinceNsu: Int64;
  const ALimit: Integer): TErpDocumentPage;
function RequestErpDocumentXml(const ACompanyId, ADocumentId: string): TErpXmlRequest;

implementation

uses
  Database.Connection,
  System.SysUtils,
  Uni;

function ListErpDocuments(const ACompanyId: string; const ASinceNsu: Int64;
  const ALimit: Integer): TErpDocumentPage;
var
  Connection: TUniConnection;
  Query: TUniQuery;
  Item: TErpDocumentSummary;
  Count: Integer;
begin
  if ASinceNsu < 0 then
    raise EArgumentException.Create('NSU nao pode ser negativo.');
  if (ALimit < 1) or (ALimit > 500) then
    raise EArgumentException.Create('Limite deve estar entre 1 e 500.');
  Result.LastNsu := ASinceNsu;
  SetLength(Result.Items, ALimit);
  Count := 0;
  try
    Connection := TDatabaseConnection.OpenFromEnvironment;
    try
      Query := TUniQuery.Create(nil);
      try
        Query.Connection := Connection;
        Query.SQL.Text :=
          'select sync_nsu, id::text as id, access_key, document_type, issued_at, issuer_cnpj, nome_emitente, tipo_operacao, situacao_fiscal, total_amount, status, ' +
          '(xml_object_key is not null) as xml_available, ciencia_cstat ' +
      'from documentos ' +
          'where lower(company_id::text) = lower(:company_id) and sync_nsu > :since_nsu ' +
          'order by sync_nsu asc limit :limit';
        Query.ParamByName('company_id').AsString := ACompanyId;
        Query.ParamByName('since_nsu').AsLargeInt := ASinceNsu;
        Query.ParamByName('limit').AsInteger := ALimit;
        Query.Open;
        while not Query.Eof do
        begin
          Item.Nsu := Query.FieldByName('sync_nsu').AsLargeInt;
          Item.Id := Query.FieldByName('id').AsString;
          Item.AccessKey := Query.FieldByName('access_key').AsString;
          Item.DocumentType := Query.FieldByName('document_type').AsString;
          Item.IssuedAt := Query.FieldByName('issued_at').AsString;
          Item.IssuerCnpj := Query.FieldByName('issuer_cnpj').AsString;
          Item.IssuerName := Query.FieldByName('nome_emitente').AsString;
          Item.OperationType := Query.FieldByName('tipo_operacao').AsString;
          Item.FiscalStatus := Query.FieldByName('situacao_fiscal').AsString;
          Item.TotalAmount := Query.FieldByName('total_amount').AsString;
          Item.Status := Query.FieldByName('status').AsString;
          Item.XmlAvailable := Query.FieldByName('xml_available').AsBoolean;
          Item.AwarenessCStat := Query.FieldByName('ciencia_cstat').AsInteger;
          Result.Items[Count] := Item;
          Result.LastNsu := Item.Nsu;
          Inc(Count);
          Query.Next;
        end;
      finally
        Query.Free;
      end;
    finally
      Connection.Free;
    end;
  except
    raise;
  end;
  SetLength(Result.Items, Count);
end;

function RequestErpDocumentXml(const ACompanyId, ADocumentId: string): TErpXmlRequest;
var C: TUniConnection; Q: TUniQuery; DocumentGuid: TGUID; AccessKey: string;
  AwarenessCStat: Integer;
begin
  Result := Default(TErpXmlRequest);
  try DocumentGuid := StringToGUID('{' + ADocumentId + '}');
  except on E: EConvertError do Exit; end;
  C := TDatabaseConnection.OpenFromEnvironment;
  try
    C.StartTransaction;
    try
      Q := TUniQuery.Create(nil);
      try
        Q.Connection := C;
        Q.SQL.Text := 'select id from empresas where id=cast(:company_id as uuid) for update';
        Q.ParamByName('company_id').AsString := ACompanyId; Q.Open; Q.Close;
        Q.SQL.Text := 'select access_key, xml_object_key, xml_sha256, ciencia_cstat from documentos ' +
          'where company_id=cast(:company_id as uuid) and id=cast(:id as uuid)';
        Q.ParamByName('company_id').AsString := ACompanyId;
        Q.ParamByName('id').AsString := ADocumentId; Q.Open;
        Result.Found := not Q.IsEmpty;
        if Result.Found then
        begin
          AccessKey := Q.FieldByName('access_key').AsString;
          AwarenessCStat := Q.FieldByName('ciencia_cstat').AsInteger;
          if Q.FieldByName('xml_sha256').AsString <> '' then
            Result.ObjectKey := Q.FieldByName('xml_object_key').AsString;
          Q.Close;
          if Result.ObjectKey = '' then
          begin
            if (AwarenessCStat = 596) or (AwarenessCStat = 655) then
            begin
              Result.CommandStatus := 'failed';
              Result.CommandCStat := AwarenessCStat;
              C.Commit;
              Exit;
            end;
            Q.SQL.Text := 'insert into comandos(company_id,command_type,idempotency_key,payload) ' +
              'values(cast(:company_id as uuid),''retrieve_xml'',:key,' +
              'jsonb_build_object(''access_key'',cast(:access_key as text))) ' +
              'on conflict(company_id,command_type,idempotency_key) do update ' +
              'set idempotency_key=excluded.idempotency_key returning id::text, status, last_cstat';
            Q.ParamByName('company_id').AsString := ACompanyId;
            Q.ParamByName('key').AsString := 'automatic-xml:' + AccessKey;
            Q.ParamByName('access_key').AsString := AccessKey;
            Q.Open;
            Result.CommandId := Q.FieldByName('id').AsString;
            Result.CommandStatus := Q.FieldByName('status').AsString;
            Result.CommandCStat := Q.FieldByName('last_cstat').AsInteger;
          end;
        end;
      finally Q.Free; end;
      C.Commit;
    except C.Rollback; raise; end;
  finally C.Free; end;
end;

end.
