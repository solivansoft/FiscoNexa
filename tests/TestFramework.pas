unit TestFramework;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Variants,
  System.Rtti, System.TypInfo, Winapi.Windows, System.StrUtils;

type
  TConsoleColor = (ccBlack, ccBlue, ccGreen, ccCyan, ccRed, ccMagenta, ccBrown, ccLightGray, ccDarkGray, ccLightBlue, ccLightGreen, ccLightCyan, ccLightRed, ccLightMagenta,
    ccYellow, ccWhite);

type
  TConsoleParams = record
    verbose: Boolean;
    quiet: Boolean;
    noColor: Boolean;
    wait: Boolean;
    // Filtro CSV de substrings (case-insensitive) aplicado ao ClassName dos
    // TTestCase registrados. Vazio = roda tudo. Ex.: 'Image,Tunables' executa
    // qualquer classe cujo nome contenha "Image" ou "Tunables".
    filter: string;
  end;

  // funcoes console
procedure Print(AText: string = ' '); overload;
procedure Print(AText: string; const Params: array of Variant); overload;

// Funções para controle de cores no console
procedure SetConsoleColor(Color: TConsoleColor);

procedure ResetConsoleColor;

type
  TTestResult = (trPassed, trPartial, trFailed, trError, trSkipped);
  TTestResultSet = set of TTestResult;

  TTestMethodInfo = record
    MethodName: string;
    Result: TTestResult;
    ErrorMessage: string;
    ExecutionTime: Cardinal;
  end;

  TTestMethods = TList<TTestMethodInfo>;

  TTestInfo = record
    TestName: string;
    TestClass: string;
    ErrorMessage: string;
    ExecutionTime: Cardinal;
    Methods: TTestMethods;
    function GetTestResult: TTestResult;
  end;

  TMethodInfo = record
    Proc: TMethod; // Muda de Pointer para TMethod
    MethodName: string;
    MethodTest: TTestMethodInfo;
  end;

  TMethods = TList<TMethodInfo>;

  TTestCase = class
  private
    FMethods: TMethods;
    FTestInfo: TTestInfo;
    FName: string;
    FMethodInfo: TMethodInfo;
    function GetMethods: TMethods;
  protected
    procedure Setup; virtual;
    procedure TearDown; virtual;
    procedure AssertTrue(Condition: Boolean; const Message: string = ''); virtual;
    procedure AssertFalse(Condition: Boolean; const Message: string = ''); virtual;
    procedure AssertEquals(Value1, Value2: Variant; const Message: string = ''); virtual;
    procedure Fail(const Message: string); virtual;
    procedure Skip(const Message: string); virtual;
    function GetTestInfo: TTestInfo;
    constructor Create(const ATestName: string = '');
    procedure Run; virtual;

    property Name: string read FName write FName;
    property TestInfo: TTestInfo read FTestInfo write FTestInfo;
    property Methods: TMethods read GetMethods write FMethods;
    property MethodInfo: TMethodInfo read FMethodInfo;
  public
    destructor Destroy; override;
  end;

  TTestRunner = class
  class var
    Params: TConsoleParams;
  private
    FTests: TList<TTestCase>;
    FResults: TList<TTestInfo>;
    procedure ExecuteTest(TestCase: TTestCase);
    // Métodos auxiliares para PrintResults
    procedure PrintMethodDetails(const TestInfo: TTestInfo);
    procedure PrintSummary(PassedCount, FailedCount, ErrorCount, SkippedCount: Integer; TotalTime: Cardinal);
    procedure PrintColoredText(const Text: string; Color: TConsoleColor);
    function GetResultString(TestResult: TTestResult): string;
    function GetResultColor(TestResult: TTestResult): TConsoleColor;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterTest(TestCase: TTestCase);
    procedure RunAllTests;
    procedure PrintResults;
    class procedure RunTests;
    property Results: TList<TTestInfo> read FResults;
  end;

  // Classe helper para registrar testes facilmente
  TTestHelper = class
  public
    class procedure RegisterTest(TestCase: TTestCase);
  end;

  // ETestFailure separa "asserção falhou (esperado, sem bug no código de teste)"
  // de exceção inesperada (bug real). Run captura ETestFailure como trFailed
  // e Exception como trError. Sem isso, `AssertTrue(False)` apenas anotava
  // o erro e continuava executando — qualquer assert seguinte que acessasse
  // memória nil disparava AV em cascata e mascarava o assert real.
  ETestFailure = class(Exception);

var
  GlobalTestRunner: TTestRunner;

implementation

procedure ShowUsage;
begin
  Print('=== SISTEMA DE TESTES UNITARIOS - BR SISTEMAS ===');
  Print;
  Print('Uso: TestRunner.exe [opcoes]');
  Print;
  Print('Opcoes:');
  Print('  -h, --help     Mostra esta ajuda');
  Print('  -v, --verbose  Modo verboso (mostra detalhes de cada teste)');
  Print('  -q, --quiet    Modo silencioso (apenas resumo final)');
  Print('  -w, --wait     Aguardar Enter para sair do console');
  Print('  --no-color     Desativa a saida com cores');
  Print('  --only X[,Y]   Roda apenas TestCases cujo ClassName contenha X ou Y (CSV, case-insensitive)');
  Print('  --core         Executa apenas testes dos modulos Core');
  Print('  --app          Executa apenas testes dos modulos App');
  Print('  --services     Executa apenas testes dos Servicos');
  Print('  --utils        Executa apenas testes dos utilitarios');
  Print;
  Print('Exemplos:');
  Print('  TestRunner.exe              (executa todos os testes)');
  Print('  TestRunner.exe --funcoes -v    (executa testes Funcoes em modo verboso)');
  // Print('  TestRunner.exe --app -q     (executa testes App em modo silencioso)');
  Print;
end;

function HasParam(const Param: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
  begin
    if (ParamStr(I) = Param) or (ParamStr(I) = '--' + Param) or (ParamStr(I) = '-' + Param) then
    begin
      Result := True;
      Break;
    end;
  end;
end;

// Retorna o valor associado a uma flag. Aceita 3 formas equivalentes:
//   --only=X   |   --only X   |   -only X
function GetParamValue(const Param: string; out Value: string): Boolean;
var
  I: Integer;
  Arg: string;
  Prefixes: TArray<string>;
  Pfx: string;
begin
  Result := False;
  Value := '';
  Prefixes := TArray<string>.Create('--', '-');
  for I := 1 to ParamCount do
  begin
    Arg := ParamStr(I);
    for Pfx in Prefixes do
    begin
      if StartsText(Pfx + Param + '=', Arg) then
      begin
        Value := Copy(Arg, Length(Pfx + Param + '=') + 1, MaxInt);
        Exit(True);
      end;
      if SameText(Arg, Pfx + Param) and (I < ParamCount) then
      begin
        Value := ParamStr(I + 1);
        Exit(True);
      end;
    end;
  end;
end;

procedure ConfigureTestRunner;
var
  FilterValue: string;
begin
  TTestRunner.Params.verbose := HasParam('v') or HasParam('verbose');
  TTestRunner.Params.quiet := HasParam('q') or HasParam('quiet');
  TTestRunner.Params.wait := HasParam('w') or HasParam('wait');
  TTestRunner.Params.noColor := HasParam('no-color');
  if GetParamValue('only', FilterValue) then
    TTestRunner.Params.filter := FilterValue;
end;

procedure Print(AText: string); overload;
begin
  Print(AText, []);
end;

procedure Print(AText: string; const Params: array of Variant);
var
  OutputStr: string;
begin

  // Monta a string de saída
  OutputStr := AText;
  for var I := 0 to High(Params) do
    OutputStr := OutputStr + ' ' + VarToStr(Params[I]);

  // Imprime no console
  Writeln(OutputStr);

  // Flush por linha quando verbose — em stdout redirecionado (pipe pra
  // arquivo ou `2>&1 | tail`), Writeln bufferiza ate' o handle fechar.
  // Em deadlock de teste, ultima linha printada nao saia sem o flush.
  // Custo: ~1 syscall por linha; aceitavel em modo diagnostico.
  if TTestRunner.Params.verbose then
    System.Flush(Output);
end;

procedure SetConsoleColor(Color: TConsoleColor);
var
  ConsoleHandle: THandle;
  ColorValue: Word;
begin
  if TTestRunner.Params.noColor then
    Exit;

  ConsoleHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  case Color of
    ccBlack:
      ColorValue := 0;
    ccBlue:
      ColorValue := 1;
    ccGreen:
      ColorValue := 2;
    ccCyan:
      ColorValue := 3;
    ccRed:
      ColorValue := 4;
    ccMagenta:
      ColorValue := 5;
    ccBrown:
      ColorValue := 6;
    ccLightGray:
      ColorValue := 7;
    ccDarkGray:
      ColorValue := 8;
    ccLightBlue:
      ColorValue := 9;
    ccLightGreen:
      ColorValue := 10;
    ccLightCyan:
      ColorValue := 11;
    ccLightRed:
      ColorValue := 12;
    ccLightMagenta:
      ColorValue := 13;
    ccYellow:
      ColorValue := 14;
    ccWhite:
      ColorValue := 15;
  else
    ColorValue := 7; // Default: Light Gray
  end;
  SetConsoleTextAttribute(ConsoleHandle, ColorValue);
end;

procedure ResetConsoleColor;
begin
  if TTestRunner.Params.noColor then
    Exit;
  SetConsoleColor(ccLightGray);
end;

{ TTestCase }

constructor TTestCase.Create(const ATestName: string);
begin
  inherited Create;
  FName := ifthen(ATestName <> EmptyStr, ATestName, Self.ClassName);
  FMethods := TMethods.Create;
  FTestInfo.Methods := TTestMethods.Create;
end;

destructor TTestCase.Destroy;
begin
  FMethods.Free;
  FTestInfo.Methods.Free;
  inherited;
end;

procedure TTestCase.Setup;
begin
  // Implementacao padrao vazia
end;

procedure TTestCase.TearDown;
begin
  // Implementacao padrao vazia
end;

procedure TTestCase.AssertTrue(Condition: Boolean; const Message: string);
begin
  if not Condition then
  begin
    if Message <> '' then
      Fail(Message)
    else
      Fail('Condicao esperada como True, mas foi False');
  end;
end;

procedure TTestCase.AssertFalse(Condition: Boolean; const Message: string);
begin
  if Condition then
  begin
    if Message <> '' then
      Fail(Message)
    else
      Fail('Condicao esperada como False, mas foi True');
  end;
end;

procedure TTestCase.AssertEquals(Value1, Value2: Variant; const Message: string);
begin

  if Value1 <> Value2 then
  begin
    if Message <> '' then
      Fail(Format('%s: esperado "%s", obtido "%s"', [Message, VarToStr(Value1), VarToStr(Value2)]))
    else
      Fail(Format('Valores diferentes: esperado "%s", obtido "%s"', [VarToStr(Value1), VarToStr(Value2)]));
  end;

end;

procedure TTestCase.Fail(const Message: string);
begin
  // Marca antes do raise pra cobrir o caso de quem captura ETestFailure no
  // proprio teste (raro, mas valido em testes meta do framework). Mensagem
  // e Result tambem sao reescritos no handler do Run, redundante mas seguro.
  FMethodInfo.MethodTest.ErrorMessage := Message;
  FMethodInfo.MethodTest.Result := trFailed;

  // Raise interrompe o metodo de teste — assertions seguintes nao executam.
  // Sem isso, assert que dependia do estado validado pelo Fail anterior
  // explodia em AV (acesso a nil) e mascarava a causa raiz.
  raise ETestFailure.Create(Message);
end;

procedure TTestCase.Skip(const Message: string);
begin
  FMethodInfo.MethodTest.ErrorMessage := Message;
  FMethodInfo.MethodTest.Result := trSkipped;
end;

function TTestCase.GetMethods: TMethods;
var
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  RttiMethod: TRttiMethod;
  MethodInfo: TMethodInfo;
  MethodAddr: Pointer;
  MethodName: string;
begin
  if Assigned(FMethods) and (FMethods.Count > 0) then
  begin
    Result := FMethods;
    Exit;
  end;

  if not Assigned(FMethods) then
    FMethods := TMethods.Create;

  // Limpa a lista antes de popular
  FMethods.Clear;

  RttiContext := TRttiContext.Create;
  try
    RttiType := RttiContext.GetType(Self.ClassType);

    // Itera por todos os metodos da classe
    for RttiMethod in RttiType.GetMethods do
    begin
      // Verifica se e um metodo publico que comeca com "Test"
      if (RttiMethod.Visibility = mvPublic) and (RttiMethod.MethodKind = mkProcedure) and (Length(RttiMethod.GetParameters) = 0) and // Sem parametros
        (Copy(RttiMethod.Name, 1, 4) = 'Test') then
      begin
        MethodName := RttiMethod.Name;
        MethodAddr := RttiMethod.CodeAddress;

        if Assigned(MethodAddr) then
        begin
          // Preenche as informacoes do metodo de teste
          MethodInfo.Proc.Data := Self; // Ponteiro para o objeto
          MethodInfo.Proc.Code := MethodAddr; // Ponteiro para o metodo
          MethodInfo.MethodName := MethodName;

          // Adiciona a lista
          FMethods.Add(MethodInfo);
        end;
      end;
    end;
  finally
    RttiContext.Free;
  end;

  Result := FMethods;

end;

function TTestCase.GetTestInfo: TTestInfo;
begin
  Result := FTestInfo;
end;

procedure TTestCase.Run;
var
  MethodExec: procedure of object;
begin

  FMethods := Methods;

  for var I := 0 to FMethods.Count - 1 do
  begin
    MethodExec := nil;
    FMethodInfo := FMethods[I];

    // Heartbeat por metodo — emite ANTES de executar pra que, se o metodo
    // travar (deadlock COM, socket sem timeout, busy-loop, modal dialog),
    // saibamos exatamente qual metodo dentro da classe foi o ultimo a
    // iniciar. O heartbeat por classe em TTestRunner.ExecuteTest cobre
    // travas no Setup; este aqui cobre travas no proprio metodo de teste.
    // Gateado por -v pra nao poluir output padrao. Flush imediato pq
    // Writeln em stdout redirect bufferiza ate' fechar handle — em
    // deadlock, ultima linha nao sairia sem o flush explicito.
    if TTestRunner.Params.verbose then
    begin
      Writeln(Format('[hb]   %s.%s', [Self.ClassName, MethodInfo.MethodName]));
      System.Flush(Output);
    end;

    try

      TMethod(MethodExec).Code := MethodInfo.Proc.Code;
      TMethod(MethodExec).Data := MethodInfo.Proc.Data;

      FMethodInfo.MethodTest.MethodName := MethodInfo.MethodName;
      FMethodInfo.MethodTest.Result := trPassed;
      FMethodInfo.MethodTest.ErrorMessage := '';
      FMethodInfo.MethodTest.ExecutionTime := GetTickCount;

      MethodExec();

    except
      // Ordem importa: ETestFailure (descendente de Exception) precisa vir
      // ANTES do handler genérico, senão cai em trError em vez de trFailed
      // e perde a distinção entre "assert falhou" e "bug no codigo de teste".
      on e: ETestFailure do
      begin
        FMethodInfo.MethodTest.Result := trFailed;
        FMethodInfo.MethodTest.ErrorMessage := e.Message;
      end;
      on e: exception do
      begin
        FMethodInfo.MethodTest.Result := trError;
        FMethodInfo.MethodTest.ErrorMessage := e.Message;
      end;
    end;

    FMethodInfo.MethodTest.ExecutionTime := GetTickCount - MethodInfo.MethodTest.ExecutionTime;
    TestInfo.Methods.Add(MethodInfo.MethodTest);
  end;

end;

constructor TTestRunner.Create;
begin
  inherited Create;
  FTests := TList<TTestCase>.Create;
  FResults := TList<TTestInfo>.Create;
end;

destructor TTestRunner.Destroy;
var
  I: Integer;
begin
  for I := 0 to FTests.Count - 1 do
    FTests[I].Free;
  FTests.Free;
  FResults.Free;
  inherited Destroy;
end;

procedure AbrirConsole;
begin
  if IsConsole then
  begin
    SetTextCodePage(Output, CP_UTF8);
    Exit;
  end;
  AllocConsole;
  SetConsoleOutputCP(1252); // Define saída como UTF-8
  SetConsoleCP(CP_UTF7); // Define entrada como UTF-8

  // Redireciona a saída padrão para o console
  AssignFile(Output, 'CONOUT$');
  Rewrite(Output);
  AssignFile(Input, 'CONIN$');
  Reset(Input);
end;

procedure FecharConsole;
begin
  if IsConsole then Exit;
  CloseFile(Output);
  CloseFile(Input);
  FreeConsole;
end;

class procedure TTestRunner.RunTests;
var
  StartTime: Cardinal;
begin
  AbrirConsole;
  try
    try
      // Verificar se é pedido de ajuda
      if HasParam('h') or HasParam('help') then
      begin
        ShowUsage;
        Exit;
      end;

      ConfigureTestRunner;

      Print('=== SISTEMA DE TESTES UNITARIOS - Delphos Automação ===');
      Print('Iniciando execucao dos testes...');
      Print;

      // Executar os testes
      StartTime := GetTickCount;

      GlobalTestRunner.RunAllTests;

      Print;
      Print(Format('Tempo total de execucao: %dms', [GetTickCount - StartTime]));
      Print;

      // Mostrar resultados se não estiver em modo silencioso
      if not HasParam('q') and not HasParam('quiet') then
        GlobalTestRunner.PrintResults;

      // Definir código de saída baseado nos resultados
      var
      FailedCount := 0;
      var
      ErrorCount := 0;
      for var I := 0 to GlobalTestRunner.Results.Count - 1 do
        for var M in GlobalTestRunner.Results[I].Methods do
        begin
          case M.Result of
            trFailed:
              Inc(FailedCount);
            trError:
              Inc(ErrorCount);
          end;
        end;

      if (FailedCount > 0) or (ErrorCount > 0) then
        ExitCode := 1
      else
        ExitCode := 0;

    except
      on e: exception do
      begin
        Print('ERRO FATAL: ' + e.Message);
        ExitCode := 2;
      end;
    end;

  finally
    // Aguardar entrada para que o console não feche imediatamente
    Print;
    if Params.verbose then
    Print('Pressione ENTER para sair...');
    if Params.wait then
    Readln;
    FecharConsole;
  end;
end;

procedure TTestRunner.RegisterTest(TestCase: TTestCase);
begin
  FTests.Add(TestCase);
end;

procedure TTestRunner.ExecuteTest(TestCase: TTestCase);
var
  StartTime: Cardinal;
begin
  // Heartbeat por teste — emite linha ANTES de Setup+Run pra que, se o
  // proximo TestCase travar (deadlock COM, socket sem timeout, modal
  // dialog), saibamos qual eh. Gateado por -v pra nao poluir output
  // padrao. Flush imediato pq Writeln em pipe (stdout redirect) bufferiza
  // ate' fechar — em deadlock, ultima linha nao sairia.
  if Params.verbose then
  begin
    Writeln(Format('[hb] %s.%s', [TestCase.ClassName, TestCase.Name]));
    System.Flush(Output);
  end;

  StartTime := GetTickCount;

  TestCase.FTestInfo.TestName := TestCase.Name;
  TestCase.FTestInfo.TestClass := TestCase.ClassName;
  TestCase.FTestInfo.ErrorMessage := '';
  TestCase.FTestInfo.ExecutionTime := StartTime;

  TestCase.Setup;

  TestCase.Run;

  TestCase.FTestInfo.ExecutionTime := GetTickCount - StartTime;

  Results.Add(TestCase.FTestInfo);

end;

function ClassMatchesFilter(const AClassName, AFilter: string): Boolean;
var
  Tokens: TArray<string>;
  Token, LowerName: string;
begin
  if Trim(AFilter) = '' then
    Exit(True);
  LowerName := LowerCase(AClassName);
  Tokens := AFilter.Split([',']);
  for Token in Tokens do
  begin
    var T := LowerCase(Trim(Token));
    if (T <> '') and (Pos(T, LowerName) > 0) then
      Exit(True);
  end;
  Result := False;
end;

procedure TTestRunner.RunAllTests;
var
  Selected, Skipped: Integer;
begin
  FResults.Clear;
  Selected := 0;
  Skipped := 0;

  // Filtro --only: pula registros cujo ClassName nao bate em nenhuma das
  // substrings (case-insensitive, CSV). Aplicado aqui — fora de ExecuteTest
  // — pra que classes filtradas nem apareçam nos Results, mantendo
  // contagem final coerente com o que foi de fato executado.
  for var I := 0 to FTests.Count - 1 do
  begin
    if not ClassMatchesFilter(FTests[I].ClassName, Params.filter) then
    begin
      Inc(Skipped);
      Continue;
    end;
    Inc(Selected);
    ExecuteTest(FTests[I]);
  end;

  if Trim(Params.filter) <> '' then
  begin
    Writeln(Format('[filter] --only "%s" -> %d selecionados, %d pulados',
      [Params.filter, Selected, Skipped]));
    System.Flush(Output);
  end;
end;

// Métodos auxiliares para PrintResults

procedure TTestRunner.PrintColoredText(const Text: string; Color: TConsoleColor);
begin
  if Params.noColor then
  begin
    Write(Text);
    Exit;
  end;
  SetConsoleColor(Color);
  Write(Text);
  ResetConsoleColor;
end;

function TTestRunner.GetResultString(TestResult: TTestResult): string;
begin
  case TestResult of
    trPassed:
      Result := 'PASSED';
    trPartial:
      Result := 'PARTIAL';
    trFailed:
      Result := 'FAILED';
    trError:
      Result := 'ERRO';
    trSkipped:
      Result := 'SKIP';
  else
    Result := 'DESCONHECIDO';
  end;
end;

function TTestRunner.GetResultColor(TestResult: TTestResult): TConsoleColor;
begin
  case TestResult of
    trPassed:
      Result := ccGreen;
    trPartial:
      Result := ccYellow;
    trFailed, trError:
      Result := ccRed;
    trSkipped:
      Result := ccYellow;
  else
    Result := ccWhite;
  end;
end;


procedure TTestRunner.PrintMethodDetails(const TestInfo: TTestInfo);
var
  Method: TTestMethodInfo;
  MethodResultStr: string;
  MethodColor: TConsoleColor;
begin
  if not Params.verbose then
    Exit;

  for Method in TestInfo.Methods do
  begin
    MethodResultStr := GetResultString(Method.Result);
    MethodColor := GetResultColor(Method.Result);

    Write(' ');
    // PrintColoredText(Format('[%s]', [MethodResultStr]), MethodColor);
    SetConsoleColor(MethodColor);
    // Print(Format('%s %s (%dms)', [MethodResultStr, Method.MethodName, Method.ExecutionTime]));

    if Method.ErrorMessage = '' then
      Print(Format('%s %s (%dms)', [MethodResultStr, Copy(Method.MethodName, 1, 20), Method.ExecutionTime]))
    else
      Print(Format('%s %s (%dms) > %s', [MethodResultStr, Copy(Method.MethodName, 1, 20), Method.ExecutionTime, Method.ErrorMessage]))
  end;
end;

procedure TTestRunner.PrintSummary(PassedCount, FailedCount, ErrorCount, SkippedCount: Integer; TotalTime: Cardinal);
begin
  Print;
  Print('=== RESUMO ===');
  Print(Format('Total de metodos: %d', [PassedCount + FailedCount + ErrorCount + SkippedCount]));

  PrintColoredText(Format('Passou: %d', [PassedCount]), ccGreen);
  Print;

  if FailedCount > 0 then
    PrintColoredText(Format('Falhou: %d', [FailedCount]), ccRed)
  else
    Write(Format('Falhou: %d', [FailedCount]));
  Print;

  if ErrorCount > 0 then
    PrintColoredText(Format('Erro: %d', [ErrorCount]), ccRed)
  else
    Write(Format('Erro: %d', [ErrorCount]));
  Print;

  if SkippedCount > 0 then
    PrintColoredText(Format('Ignorou: %d', [SkippedCount]), ccYellow)
  else
    Write(Format('Ignorou: %d', [SkippedCount]));
  Print;

  Print(Format('Tempo total: %dms', [TotalTime]));

  if (FailedCount > 0) or (ErrorCount > 0) then
    PrintColoredText('ALGUNS TESTES FALHARAM!', ccRed)
  else
    PrintColoredText('TODOS OS TESTES PASSARAM!', ccGreen);
  Print;
end;

procedure TTestRunner.PrintResults;
var
  I: Integer;
  PassedCount, FailedCount, ErrorCount, SkippedCount: Integer;
  TotalTime: Cardinal;
  Method: TTestMethodInfo;
begin
  // Inicializar contadores (por método)
  PassedCount := 0;
  FailedCount := 0;
  ErrorCount := 0;
  SkippedCount := 0;
  TotalTime := 0;

  // Cabeçalho
  Print('=== RESULTADOS DOS TESTES ===');
  Print;

  // Processar cada resultado de teste
  for I := 0 to FResults.Count - 1 do
  begin
    // Contabilizar por método
    for Method in FResults[I].Methods do
    begin
      case Method.Result of
        trPassed:
          Inc(PassedCount);
        trFailed:
          Inc(FailedCount);
        trError:
          Inc(ErrorCount);
        trSkipped:
          Inc(SkippedCount);
      end;
    end;

    // Imprimir resultado do teste
    // PrintTestResult(FResults[i]);

    // Imprimir detalhes dos métodos se verbose
    PrintMethodDetails(FResults[I]);

    // Acumular tempo total
    TotalTime := TotalTime + FResults[I].ExecutionTime;
  end;

  // Imprimir resumo
  PrintSummary(PassedCount, FailedCount, ErrorCount, SkippedCount, TotalTime);
end;

{ TTestInfo }

function TTestInfo.GetTestResult: TTestResult;
var
  Passed, Failed, Error, Skipped: Integer;
begin
  Passed := 0;
  Failed := 0;
  Error := 0;
  Skipped := 0;

  for var Method in Methods do
  begin
    case Method.Result of
      trPassed:
        Inc(Passed);
      trFailed:
        Inc(Failed);
      trError:
        Inc(Error);
      trSkipped:
        Inc(Skipped);
    end;
  end;

  if (Failed = 0) and (Error = 0) then
  begin
    if (Skipped > 0) and (Passed = 0) then
      Result := trSkipped
    else
      Result := trPassed
  end
  else if (Error > 0) then
    Result := trError
  else if (Failed > 0) and (Passed > 0) then
    Result := trPartial
  else
    Result := trFailed;
end;

{ TTestHelper }

class procedure TTestHelper.RegisterTest(TestCase: TTestCase);
begin
  GlobalTestRunner.RegisterTest(TestCase);
end;

initialization

GlobalTestRunner := TTestRunner.Create;

finalization

GlobalTestRunner.Free;

end.
