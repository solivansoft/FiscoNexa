unit Application.Authorization;

interface

function ParseBearerToken(const AAuthorization: string): string;

implementation

uses
  System.StrUtils,
  System.SysUtils;

function ParseBearerToken(const AAuthorization: string): string;
const
  BearerPrefix = 'Bearer ';
begin
  Result := Trim(AAuthorization);
  if not StartsText(BearerPrefix, Result) then
    Exit('');

  Result := Trim(Copy(Result, Length(BearerPrefix) + 1, MaxInt));
end;

end.
