unit Api.Routes.Health;

interface

procedure RegisterHealthRoute;

implementation

uses
  Horse;

procedure RegisterHealthRoute;
begin
  THorse.Get('/health',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    begin
      AResponse.ContentType('application/json').Send('{"situacao":"disponivel"}');
    end);
end;

end.
