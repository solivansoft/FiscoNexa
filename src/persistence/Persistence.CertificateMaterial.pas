unit Persistence.CertificateMaterial;

interface

uses
  Application.CertificateMaterial,
  System.SysUtils,
  FireDAC.Stan.Param, FireDAC.Comp.Client;

type
  TPostgresStoredCertificateReader = class(TInterfacedObject, IStoredCertificateReader)
  private
    FConnection: TFDConnection;
    function ReadBytes(const AQuery: TFDQuery; const AFieldName: string): TBytes;
  public
    constructor Create(const AConnection: TFDConnection);
    function ReadActive(const ACompanyId: string): TStoredCertificateMaterial;
  end;

implementation

uses
  Data.DB,
  System.Classes;

constructor TPostgresStoredCertificateReader.Create(const AConnection: TFDConnection);
begin
  inherited Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Conexao PostgreSQL nao informada.');
  FConnection := AConnection;
end;

function TPostgresStoredCertificateReader.ReadBytes(const AQuery: TFDQuery;
  const AFieldName: string): TBytes;
var
  Stream: TStream;
begin
  Stream := AQuery.CreateBlobStream(AQuery.FieldByName(AFieldName), bmRead);
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[0], Stream.Size);
  finally
    Stream.Free;
  end;
end;

function TPostgresStoredCertificateReader.ReadActive(
  const ACompanyId: string): TStoredCertificateMaterial;
var
  Query: TFDQuery;
begin
  Result := Default(TStoredCertificateMaterial);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select company.cnpj, company.state, certificate.encryption_key_ref, certificate.encrypted_data_key, ' +
      'certificate.encrypted_certificate, certificate.certificate_nonce, certificate.certificate_tag, ' +
      'certificate.encrypted_password, certificate.password_nonce, certificate.password_tag ' +
      'from certificados certificate join empresas company on company.id = certificate.company_id ' +
      'where certificate.company_id = cast(:company_id as uuid) ' +
      'and certificate.revoked_at is null and certificate.valid_until >= current_date ' +
      'order by certificate.created_at desc limit 1';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.Open;
    if Query.IsEmpty then
      raise EInvalidOpException.Create('Certificado A1 ativo nao encontrado para o CNPJ.');
    Result.Cnpj := Query.FieldByName('cnpj').AsString;
    Result.State := Query.FieldByName('state').AsString;
    Result.Envelope.EncryptionKeyReference := Query.FieldByName('encryption_key_ref').AsString;
    Result.Envelope.EncryptedDataKey := ReadBytes(Query, 'encrypted_data_key');
    Result.Envelope.EncryptedCertificate.Ciphertext := ReadBytes(Query, 'encrypted_certificate');
    Result.Envelope.EncryptedCertificate.Nonce := ReadBytes(Query, 'certificate_nonce');
    Result.Envelope.EncryptedCertificate.Tag := ReadBytes(Query, 'certificate_tag');
    Result.Envelope.EncryptedPassword.Ciphertext := ReadBytes(Query, 'encrypted_password');
    Result.Envelope.EncryptedPassword.Nonce := ReadBytes(Query, 'password_nonce');
    Result.Envelope.EncryptedPassword.Tag := ReadBytes(Query, 'password_tag');
  finally
    Query.Free;
  end;
end;

end.
