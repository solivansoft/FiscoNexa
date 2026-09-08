unit Api.Routes.Documentation;

interface

procedure RegisterDocumentationRoutes;

implementation

uses
  System.SysUtils, System.IOUtils, Horse,
  Application.Authentication, Operations.Authentication;

procedure RegisterDocumentationRoutes;
begin
  THorse.Get('/admin/documentacao',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      Res.AddHeader('Cache-Control', 'no-store');
      Res.AddHeader('Vary', 'Authorization');
      try
        RequireSuperadmin(Req.Headers['Authorization']);
        Res.ContentType('application/json; charset=utf-8').Send(TFile.ReadAllText(
          TPath.Combine(ExtractFilePath(ParamStr(0)), 'docs/openapi-interno.json'),
          TEncoding.UTF8));
      except
        on E: EAuthenticationUnauthorized do Res.Status(401).Send('');
        on E: EAuthenticationForbidden do Res.Status(403).Send('');
        on E: Exception do Res.Status(503).Send('');
      end;
    end);
end;

end.
