unit Application.ErpKeys;

interface

uses
  System.SysUtils;

type
  EErpKeyUnauthorized = class(Exception);

  TErpKeyPrincipal = record
    KeyId: string;
    OrganizationId: string;
    ScopesJson: string;
  end;

  IErpKeyReader = interface
    ['{6C310D95-B558-40F8-8E34-18E5B0C30310}']
    function FindActiveByHash(const AKeyHash: string;
      out APrincipal: TErpKeyPrincipal): Boolean;
  end;

function HashErpKey(const AToken: string): string;
function AuthenticateErpKey(const AAuthorization: string;
  const AReader: IErpKeyReader): TErpKeyPrincipal;
function HasErpScope(const AScopesJson, ARequiredScope: string): Boolean;
procedure RequireErpScope(const APrincipal: TErpKeyPrincipal;
  const ARequiredScope: string);

implementation

uses
  System.Hash,
  System.JSON,
  Application.Authorization;

function HashErpKey(const AToken: string): string;
begin
  Result := THashSHA2.GetHashString(AToken).ToLowerInvariant;
end;

function HasErpScope(const AScopesJson, ARequiredScope: string): Boolean;
var
  Value: TJSONValue;
  Scopes: TJSONArray;
  Item: TJSONValue;
begin
  Result := False;
  Value := TJSONObject.ParseJSONValue(AScopesJson);
  try
    if not (Value is TJSONArray) then
      Exit;

    Scopes := TJSONArray(Value);
    for Item in Scopes do
      if SameText(Item.Value, ARequiredScope) then
        Exit(True);
  finally
    Value.Free;
  end;
end;

function AuthenticateErpKey(const AAuthorization: string;
  const AReader: IErpKeyReader): TErpKeyPrincipal;
var
  Token: string;
begin
  Token := ParseBearerToken(AAuthorization);
  if Token = '' then
    raise EErpKeyUnauthorized.Create('Chave do ERP ausente ou invalida.');

  if not AReader.FindActiveByHash(HashErpKey(Token), Result) then
    raise EErpKeyUnauthorized.Create('Chave do ERP ausente ou invalida.');
end;

procedure RequireErpScope(const APrincipal: TErpKeyPrincipal;
  const ARequiredScope: string);
begin
  if not HasErpScope(APrincipal.ScopesJson, ARequiredScope) then
    raise EErpKeyUnauthorized.Create('Chave do ERP sem permissao para esta operacao.');
end;

end.
