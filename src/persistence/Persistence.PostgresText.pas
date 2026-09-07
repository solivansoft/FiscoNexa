unit Persistence.PostgresText;

interface

function TextoSeguroPostgres(const AValor: string;
  const ATamanhoMaximo: Integer = 1000): string;

implementation

uses
  System.SysUtils;

function TextoSeguroPostgres(const AValor: string;
  const ATamanhoMaximo: Integer): string;
var
  C: Char;
  Tamanho: Integer;
begin
  if ATamanhoMaximo <= 0 then
    raise EArgumentOutOfRangeException.Create(
      'Tamanho maximo do texto deve ser positivo.');
  // PostgreSQL rejeita U+0000 em valores text. Bibliotecas nativas podem
  // incluir esse caractere em mensagens de erro recebidas de fora do sistema.
  Result := '';
  SetLength(Result, ATamanhoMaximo);
  Tamanho := 0;
  for C in AValor do
    if C <> #0 then
    begin
      Inc(Tamanho);
      Result[Tamanho] := C;
      if Tamanho = ATamanhoMaximo then
        Break;
    end;
  SetLength(Result, Tamanho);
end;

end.
