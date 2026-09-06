unit Application.SefazMonitoringPolicy;

interface

uses
  System.SysUtils;

const
  SefazWaitSeconds = 3630;
  SefazPointIntervalSeconds = 300;
  SefazPointLimitPerHour = 15;

type
  TSefazDistributionDecision = record
    NextNsu: string;
    GapStartNsu: string;
    GapEndNsu: string;
    ContinueNow: Boolean;
    MustWait: Boolean;
    ExternalAdvance: Boolean;
  end;

function NormalizeNsu(const AValue: string): string;
function IncrementNsu(const ANsu: string): string;
function DecideDistribution(const ACurrentNsu, AReturnedNsu, AMaxNsu: string;
  const ACStat: Integer): TSefazDistributionDecision;
function IsPointQueryAllowed(const ANow: TDateTime; const ACountLastHour: Integer;
  const AFirstQueryAt, ALastQueryAt: TDateTime; out ANextQueryAt: TDateTime): Boolean;
function TechnicalFailureDelaySeconds(const AFailureCount: Integer): Integer;

implementation

uses
  System.DateUtils;

function NormalizeNsu(const AValue: string): string;
var
  Character: Char;
  Digits: string;
begin
  Digits := '';
  for Character in Trim(AValue) do
  begin
    if not CharInSet(Character, ['0'..'9']) then
      Exit('');
    Digits := Digits + Character;
  end;

  if (Digits = '') or (Length(Digits) > 15) then
    Exit('');
  Result := StringOfChar('0', 15 - Length(Digits)) + Digits;
end;

function IncrementNsu(const ANsu: string): string;
var
  Value: Int64;
begin
  if not TryStrToInt64(ANsu, Value) or (Value = High(Int64)) then
    Exit('');
  Result := Format('%.15d', [Value + 1]);
end;

function DecideDistribution(const ACurrentNsu, AReturnedNsu, AMaxNsu: string;
  const ACStat: Integer): TSefazDistributionDecision;
var
  CurrentNsu: string;
  ReturnedNsu: string;
  MaxNsu: string;
begin
  Result := Default(TSefazDistributionDecision);
  CurrentNsu := NormalizeNsu(ACurrentNsu);
  if Trim(ACurrentNsu) = '' then
    CurrentNsu := '000000000000000';
  ReturnedNsu := NormalizeNsu(AReturnedNsu);
  MaxNsu := NormalizeNsu(AMaxNsu);
  Result.NextNsu := CurrentNsu;

  case ACStat of
    138:
      begin
        if ReturnedNsu <> '' then
          Result.NextNsu := ReturnedNsu;
        Result.ContinueNow := (ReturnedNsu <> '') and (MaxNsu <> '') and
          (ReturnedNsu < MaxNsu);
        Result.MustWait := not Result.ContinueNow;
      end;
    137:
      begin
        if ReturnedNsu <> '' then
          Result.NextNsu := ReturnedNsu;
        Result.MustWait := True;
      end;
    656:
      begin
        Result.MustWait := True;
        if (CurrentNsu <> '') and (ReturnedNsu <> '') and
          (ReturnedNsu <> CurrentNsu) then
        begin
          Result.NextNsu := ReturnedNsu;
          Result.ExternalAdvance := ReturnedNsu > CurrentNsu;
          if Result.ExternalAdvance then
          begin
            Result.GapStartNsu := IncrementNsu(CurrentNsu);
            Result.GapEndNsu := ReturnedNsu;
          end;
        end;
      end;
  else
    Result.MustWait := True;
  end;
end;

function IsPointQueryAllowed(const ANow: TDateTime; const ACountLastHour: Integer;
  const AFirstQueryAt, ALastQueryAt: TDateTime;
  out ANextQueryAt: TDateTime): Boolean;
var
  LimitResetAt: TDateTime;
  SpacingResetAt: TDateTime;
begin
  LimitResetAt := 0;
  SpacingResetAt := 0;
  ANextQueryAt := 0;

  if (ACountLastHour >= SefazPointLimitPerHour) and (AFirstQueryAt > 0) then
    LimitResetAt := IncSecond(AFirstQueryAt, SefazWaitSeconds);
  if ALastQueryAt > 0 then
    SpacingResetAt := IncSecond(ALastQueryAt, SefazPointIntervalSeconds);

  if LimitResetAt > ANextQueryAt then
    ANextQueryAt := LimitResetAt;
  if SpacingResetAt > ANextQueryAt then
    ANextQueryAt := SpacingResetAt;

  Result := (ANextQueryAt = 0) or (ANow >= ANextQueryAt);
  if Result then
    ANextQueryAt := IncSecond(ANow, SefazPointIntervalSeconds);
end;

function TechnicalFailureDelaySeconds(const AFailureCount: Integer): Integer;
var
  Attempt: Integer;
begin
  Result := 60;
  for Attempt := 1 to AFailureCount do
  begin
    if Result >= SefazWaitSeconds div 2 then
      Exit(SefazWaitSeconds);
    Result := Result * 2;
  end;
end;

end.
