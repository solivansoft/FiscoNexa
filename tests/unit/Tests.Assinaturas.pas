unit Tests.Assinaturas;
interface
uses TestFramework;
type TAssinaturasTests = class(TTestCase)
public
  procedure TestSomenteRecebidoConcedePeriodo;
  procedure TestEstornoEContestacao;
  procedure TestPagamentoDivergenteRecusado;
  procedure TestValorFracionadoRecusado;
  procedure TestWebhookExigeSegredo;
  procedure TestIdempotenciaValida;
  procedure TestEstornoExigeConclusao;
  procedure TestCartaoConfirmadoEPixEmAnalise;
  procedure TestFormasDaFaturaERecebimentoManual;
end;
implementation
uses System.JSON, Application.Assinaturas;
procedure TAssinaturasTests.TestCartaoConfirmadoEPixEmAnalise;
begin
  AssertEquals('confirmada',SituacaoPagamento('CONFIRMED','CREDIT_CARD'));
  AssertEquals('confirmada',SituacaoPagamento('CONFIRMED','DEBIT_CARD'));
  AssertEquals('pendente',SituacaoPagamento('CONFIRMED','PIX'));
  AssertEquals('pendente',SituacaoPagamento('AUTHORIZED','CREDIT_CARD'));
  AssertEquals('pendente',SituacaoPagamento('AWAITING_RISK_ANALYSIS','CREDIT_CARD'));
end;

procedure TAssinaturasTests.TestFormasDaFaturaERecebimentoManual;
var J: TJSONObject; Forma: string;
begin
  for Forma in ['UNDEFINED','PIX','BOLETO','CREDIT_CARD','DEBIT_CARD'] do
  begin
    J := TJSONObject.Create.AddPair('id','pay').AddPair('customer','cus')
      .AddPair('externalReference','ref').AddPair('value',TJSONNumber.Create(49.90)).AddPair('billingType',Forma);
    try ValidarPagamento(J,'pay','cus','ref',4990); finally J.Free; end;
  end;
  J := TJSONObject.Create.AddPair('id','pay').AddPair('customer','cus')
    .AddPair('externalReference','ref').AddPair('value',TJSONNumber.Create(49.90)).AddPair('billingType','RECEIVED_IN_CASH');
  try
    try ValidarPagamento(J,'pay','cus','ref',4990); Fail('Recebimento manual aceito.');
    except on E: ECobrancaConflito do AssertTrue(True); end;
  finally J.Free; end;
end;

procedure TAssinaturasTests.TestEstornoExigeConclusao;
var J: TJSONObject;
begin
  J := TJSONObject.ParseJSONValue('{"refunds":[{"status":"AWAITING_CRITICAL_ACTION_AUTHORIZATION","value":499},{"status":"CANCELLED","value":1}]}') as TJSONObject;
  try AssertTrue(not PossuiEstornoConcluido(J)); finally J.Free; end;
  J := TJSONObject.ParseJSONValue('{"status":"RECEIVED","refunds":[{"status":"DONE","value":0.01}]}') as TJSONObject;
  try AssertTrue(PossuiEstornoConcluido(J)); finally J.Free; end;
  J := TJSONObject.ParseJSONValue('{"refunds":null}') as TJSONObject;
  try AssertTrue(not PossuiEstornoConcluido(J)); finally J.Free; end;
end;

function Pagamento: TJSONObject;
begin
  Result:=TJSONObject.Create.AddPair('id','pay_teste').AddPair('customer','cus_teste')
    .AddPair('externalReference','referencia').AddPair('billingType','PIX').AddPair('value',TJSONNumber.Create(49.9));
end;
procedure TAssinaturasTests.TestSomenteRecebidoConcedePeriodo;
begin
  AssertEquals('recebida',SituacaoPagamento('RECEIVED'));
  AssertEquals('pendente',SituacaoPagamento('CONFIRMED'));
  AssertEquals('pendente',SituacaoPagamento('PENDING'));
  try SituacaoPagamento('OUTRO'); Fail('Estado desconhecido aceito.');
  except on E: EAsaasIndisponivel do AssertTrue(True); end;
end;
procedure TAssinaturasTests.TestEstornoEContestacao;
begin
  AssertEquals('estornada',SituacaoPagamento('REFUNDED'));
  AssertEquals('contestada',SituacaoPagamento('CHARGEBACK_REQUESTED'));
end;
procedure TAssinaturasTests.TestPagamentoDivergenteRecusado;
var J: TJSONObject;
begin
  J:=Pagamento;
  try
    ValidarPagamento(J,'pay_teste','cus_teste','referencia',4990);
    try ValidarPagamento(J,'pay_teste','outro_tenant','referencia',4990); Fail('Outro tenant aceito.');
    except on E: ECobrancaConflito do AssertTrue(True); end;
    try ValidarPagamento(J,'pay_teste','cus_teste','referencia',49900); Fail('Valor incorreto aceito.');
    except on E: ECobrancaConflito do AssertTrue(True); end;
  finally J.Free; end;
end;
procedure TAssinaturasTests.TestValorFracionadoRecusado;
var J: TJSONObject;
begin
  J:=Pagamento;
  try
    J.RemovePair('value').Free; J.AddPair('value',TJSONNumber.Create(49.901));
    try ValidarPagamento(J,'pay_teste','cus_teste','referencia',4990); Fail('Fracao indevida aceita.');
    except on E: ECobrancaConflito do AssertTrue(True); end;
  finally J.Free; end;
end;
procedure TAssinaturasTests.TestWebhookExigeSegredo;
begin
  AutenticarWebhook('01234567890123456789012345678901','01234567890123456789012345678901');
  try AutenticarWebhook('',''); Fail('Segredo vazio aceito.');
  except on E: EWebhookNaoAutorizado do AssertTrue(True); end;
  try AutenticarWebhook('01234567890123456789012345678902','01234567890123456789012345678901'); Fail('Segredo divergente aceito.');
  except on E: EWebhookNaoAutorizado do AssertTrue(True); end;
end;
procedure TAssinaturasTests.TestIdempotenciaValida;
begin
  ValidarChaveCobranca('erp-2026:pedido-001');
  try ValidarChaveCobranca('curta'); Fail('Chave curta aceita.');
  except on E: EAssinaturaInvalida do AssertTrue(True); end;
end;
initialization
  TTestHelper.RegisterTest(TAssinaturasTests.Create);
end.
