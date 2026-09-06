unit TestBase;

interface

uses
  TestFramework, System.SysUtils, System.Classes;

type
  // Classe base estendida para testes espec�ficos
  TTestCaseBase = class(TTestCase)
  private
    FTestMethod: TProc;
  protected
    procedure ExecuteTest; virtual;
  public
    constructor Create(const ATestName: string; ATestMethod: TProc);
    procedure Run; override;
  end;

  // Classe helper para registrar testes facilmente
  TTestHelper = class
  public
    class procedure RegisterTest(TestCase: TTestCase);
  end;

implementation

{ TTestCaseBase }

constructor TTestCaseBase.Create(const ATestName: string; ATestMethod: TProc);
begin
  inherited Create(ATestName);
  FTestMethod := ATestMethod;
end;

procedure TTestCaseBase.ExecuteTest;
begin
  if Assigned(FTestMethod) then
    FTestMethod();
end;

procedure TTestCaseBase.Run;
begin
  ExecuteTest;
end;

{ TTestHelper }

class procedure TTestHelper.RegisterTest(TestCase: TTestCase);
begin
  GlobalTestRunner.RegisterTest(TestCase);
end;

end.