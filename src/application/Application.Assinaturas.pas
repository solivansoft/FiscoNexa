unit Application.Assinaturas;
interface
uses System.SysUtils, System.JSON;
type
  EAssinaturaInvalida = class(Exception);
  ECobrancaConflito = class(Exception);
  ECobrancaAusente = class(Exception);
  EAsaasIndisponivel = class(Exception);
  EAsaasRejeitado = class(EAsaasIndisponivel);
  EWebhookNaoAutorizado = class(Exception);
function SituacaoPagamento(const AStatus: string; const AForma: string = 'PIX'): string;
function PossuiEstornoConcluido(const AJson: TJSONObject): Boolean;
function TextoJson(const AJson: TJSONObject; const ANome: string): string;
procedure ValidarIdentificador(const AValor: string);
procedure ValidarChaveCobranca(const AChave: string);
procedure ValidarPagamento(const AJson: TJSONObject; const AId, ACliente,
  AReferencia: string; const AValorCentavos: Int64);
procedure AutenticarWebhook(const AToken, AEsperado: string);
implementation
function PossuiEstornoConcluido(const AJson: TJSONObject): Boolean;
var
  V, Item: TJSONValue;
  Valor: Currency;
begin
  Result := False;
  V := AJson.GetValue('refunds');
  if (V = nil) or (V is TJSONNull) then Exit;
  if not (V is TJSONArray) then raise EAsaasIndisponivel.Create('Lista de estornos invalida.');
  for Item in TJSONArray(V) do
  begin
    if not (Item is TJSONObject) then raise EAsaasIndisponivel.Create('Estorno invalido.');
    if TextoJson(TJSONObject(Item), 'status') <> 'DONE' then Continue;
    if not TryStrToCurr(TextoJson(TJSONObject(Item), 'value'), Valor, TFormatSettings.Create('en-US')) then
      raise EAsaasIndisponivel.Create('Valor de estorno invalido.');
    if Valor > 0 then Result := True;
  end;
end;

function TextoJson(const AJson: TJSONObject; const ANome: string): string;
var V: TJSONValue;
begin
  if AJson=nil then Exit('');
  V := AJson.GetValue(ANome);
  if V=nil then Exit('');
  Result := V.Value;
end;
function SituacaoPagamento(const AStatus: string; const AForma: string): string;
begin
  if AStatus='RECEIVED' then Exit('recebida');
  if (AStatus='CONFIRMED') and ((AForma='CREDIT_CARD') or (AForma='DEBIT_CARD')) then Exit('confirmada');
  if AStatus='OVERDUE' then Exit('vencida');
  if AStatus='REFUNDED' then Exit('estornada');
  if (AStatus='REFUND_REQUESTED') or (AStatus='REFUND_IN_PROGRESS') or
    (AStatus='CHARGEBACK_REQUESTED') or (AStatus='CHARGEBACK_DISPUTE') or
    (AStatus='AWAITING_CHARGEBACK_REVERSAL') then Exit('contestada');
  if (AStatus='PENDING') or (AStatus='CONFIRMED') then Exit('pendente');
  if (AStatus='AUTHORIZED') or (AStatus='AWAITING_RISK_ANALYSIS') then Exit('pendente');
  raise EAsaasIndisponivel.Create('Situacao do pagamento ainda nao suportada.');
end;
procedure ValidarIdentificador(const AValor: string);
var G: TGUID;
begin
  if Length(AValor)<>36 then raise EAssinaturaInvalida.Create('Identificador invalido.');
  try G := StringToGUID('{'+AValor+'}');
  except raise EAssinaturaInvalida.Create('Identificador invalido.'); end;
end;
procedure ValidarChaveCobranca(const AChave: string);
var C: Char;
begin
  if (Length(AChave)<8) or (Length(AChave)>120) then
    raise EAssinaturaInvalida.Create('Idempotency-Key deve ter entre 8 e 120 caracteres.');
  for C in AChave do
    if not CharInSet(C,['a'..'z','A'..'Z','0'..'9','-','_',':','.']) then
      raise EAssinaturaInvalida.Create('Idempotency-Key invalida.');
end;
procedure ValidarPagamento(const AJson: TJSONObject; const AId, ACliente,
  AReferencia: string; const AValorCentavos: Int64);
var Valor: Currency; F: TFormatSettings; Forma: string;
begin
  F := TFormatSettings.Create('en-US');
  Forma := TextoJson(AJson,'billingType');
  if (TextoJson(AJson,'id')<>AId) or (TextoJson(AJson,'customer')<>ACliente) or
    (TextoJson(AJson,'externalReference')<>AReferencia) or
    not ((Forma='PIX') or (Forma='UNDEFINED') or (Forma='BOLETO') or
      (Forma='CREDIT_CARD') or (Forma='DEBIT_CARD')) or
    not TryStrToCurr(TextoJson(AJson,'value'),Valor,F) then
    raise ECobrancaConflito.Create('Pagamento divergente da cobranca.');
  if Valor*100 <> AValorCentavos then
    raise ECobrancaConflito.Create('Valor divergente da cobranca.');
end;
procedure AutenticarWebhook(const AToken, AEsperado: string);
var I, Diferenca: Integer;
begin
  if (Length(AEsperado)<32) or (Length(AToken)<>Length(AEsperado)) then
    raise EWebhookNaoAutorizado.Create('Webhook nao autorizado.');
  Diferenca := 0;
  for I:=1 to Length(AEsperado) do
    Diferenca := Diferenca or (Ord(AEsperado[I]) xor Ord(AToken[I]));
  if Diferenca<>0 then raise EWebhookNaoAutorizado.Create('Webhook nao autorizado.');
end;
end.
