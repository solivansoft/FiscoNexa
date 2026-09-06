unit Application.ErpAdministration;

interface

uses System.SysUtils;

type
  EErpAdministrationValidation = class(Exception);
  EErpNotFound = class(Exception);

  TErpKeyIssue = record
    ErpId: string;
    KeyId: string;
    Secret: string;
  end;

  IErpAdministrationStore = interface
    ['{DC4B597C-C330-4C13-A9BC-8182A08409D2}']
    function CreateErp(const ALegalName: string): string;
    function ErpExists(const AErpId: string): Boolean;
    function CreateKey(const AErpId, ALabel, AKeyHash: string): string;
    procedure RevokeKey(const AErpId, AKeyId: string);
  end;

  TErpAdministrationService = class
  private
    FStore: IErpAdministrationStore;
    function NewKeySecret: string;
    function IssueKey(const AErpId, ALabel: string): TErpKeyIssue;
  public
    constructor Create(const AStore: IErpAdministrationStore);
    function CreateErp(const ALegalName, AKeyLabel: string): TErpKeyIssue;
    function RotateKey(const AErpId, AKeyLabel: string): TErpKeyIssue;
    procedure RevokeKey(const AErpId, AKeyId: string);
  end;

implementation

uses
  Application.ErpKeys,
  System.Hash;

constructor TErpAdministrationService.Create(const AStore: IErpAdministrationStore);
begin
  inherited Create;
  if AStore = nil then
    raise EArgumentNilException.Create('Persistencia administrativa de ERP nao informada.');
  FStore := AStore;
end;

function TErpAdministrationService.NewKeySecret: string;
var
  FirstId: TGUID;
  SecondId: TGUID;
begin
  FirstId := TGUID.NewGuid;
  SecondId := TGUID.NewGuid;
  Result := 'fnx_erp_' + THashSHA2.GetHashString(FirstId.ToString + SecondId.ToString).ToLowerInvariant;
end;

function TErpAdministrationService.IssueKey(const AErpId, ALabel: string): TErpKeyIssue;
begin
  if Trim(ALabel) = '' then
    raise EErpAdministrationValidation.Create('Identificacao da chave obrigatoria.');
  Result.ErpId := AErpId;
  Result.Secret := NewKeySecret;
  Result.KeyId := FStore.CreateKey(AErpId, Trim(ALabel), HashErpKey(Result.Secret));
end;

function TErpAdministrationService.CreateErp(const ALegalName,
  AKeyLabel: string): TErpKeyIssue;
var
  ErpId: string;
begin
  if Trim(ALegalName) = '' then
    raise EErpAdministrationValidation.Create('Nome legal do ERP obrigatorio.');
  ErpId := FStore.CreateErp(Trim(ALegalName));
  Result := IssueKey(ErpId, AKeyLabel);
end;

function TErpAdministrationService.RotateKey(const AErpId,
  AKeyLabel: string): TErpKeyIssue;
begin
  if not FStore.ErpExists(AErpId) then
    raise EErpNotFound.Create('ERP nao encontrado.');
  Result := IssueKey(AErpId, AKeyLabel);
end;

procedure TErpAdministrationService.RevokeKey(const AErpId, AKeyId: string);
begin
  if not FStore.ErpExists(AErpId) then
    raise EErpNotFound.Create('ERP nao encontrado.');
  FStore.RevokeKey(AErpId, AKeyId);
end;

end.
