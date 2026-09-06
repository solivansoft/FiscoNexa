unit Application.BrazilianStates;

interface

uses System.SysUtils;

function BrazilianStateCode(const AState: string): Integer;

implementation

function BrazilianStateCode(const AState: string): Integer;
var
  State: string;
begin
  State := UpperCase(Trim(AState));
  if State = 'AC' then Exit(12);
  if State = 'AL' then Exit(27);
  if State = 'AP' then Exit(16);
  if State = 'AM' then Exit(13);
  if State = 'BA' then Exit(29);
  if State = 'CE' then Exit(23);
  if State = 'DF' then Exit(53);
  if State = 'ES' then Exit(32);
  if State = 'GO' then Exit(52);
  if State = 'MA' then Exit(21);
  if State = 'MT' then Exit(51);
  if State = 'MS' then Exit(50);
  if State = 'MG' then Exit(31);
  if State = 'PA' then Exit(15);
  if State = 'PB' then Exit(25);
  if State = 'PR' then Exit(41);
  if State = 'PE' then Exit(26);
  if State = 'PI' then Exit(22);
  if State = 'RJ' then Exit(33);
  if State = 'RN' then Exit(24);
  if State = 'RS' then Exit(43);
  if State = 'RO' then Exit(11);
  if State = 'RR' then Exit(14);
  if State = 'SC' then Exit(42);
  if State = 'SP' then Exit(35);
  if State = 'SE' then Exit(28);
  if State = 'TO' then Exit(17);
  raise EArgumentException.Create('UF invalida: ' + AState);
end;

end.
