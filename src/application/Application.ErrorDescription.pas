unit Application.ErrorDescription;

interface

uses
  System.SysUtils;

function DescricaoErroPersistivel(const AErro: Exception): string;

implementation

function DescricaoErroPersistivel(const AErro: Exception): string;
const
  TamanhoMaximo = 900;
var
  C: Char;
  Mensagem: string;
begin
  if AErro = nil then
    Exit('Exception');
  Result := AErro.ClassName;
  Mensagem := AErro.Message;
  if Mensagem = '' then
    Exit;
  Result := Result + ': ';
  for C in Mensagem do
  begin
    if Length(Result) >= TamanhoMaximo then
      Break;
    if (Ord(C) >= 32) and (Ord(C) <= 126) then
      Result := Result + C
    else if C <> #0 then
      Result := Result + '?';
  end;
end;

end.
