unit Schema.Definition;

interface

uses
  System.Generics.Collections;

type
  TSchemaFieldType = (sftUuid, sftText, sftInteger, sftBigInteger, sftBoolean, sftDate,
    sftTimestamp, sftDecimal, sftJson, sftBinary);

  TSchemaFieldAttribute = (sfaPrimaryKey, sfaNotNull, sfaUnique,
    sfaDefaultUuid, sfaDefaultNow);
  TSchemaFieldAttributes = set of TSchemaFieldAttribute;
  TSchemaActionType = (satRenameField, satRemoveField, satExecuteData);

  TSchemaIndex = class
  private
    FName: string;
    FFields: string;
    FUnique: Boolean;
  public
    constructor Create(const AName, AFields: string; const AUnique: Boolean);
    property Name: string read FName;
    property Fields: string read FFields;
    property Unique: Boolean read FUnique;
  end;

  TSchemaForeignKey = class
  private
    FName: string;
    FFieldName: string;
    FTargetTable: string;
    FTargetField: string;
    FOnDelete: string;
  public
    constructor Create(const AName, AFieldName, ATargetTable, ATargetField,
      AOnDelete: string);
    property Name: string read FName;
    property FieldName: string read FFieldName;
    property TargetTable: string read FTargetTable;
    property TargetField: string read FTargetField;
    property OnDelete: string read FOnDelete;
  end;

  TSchemaCheck = class
  private
    FName: string;
    FExpression: string;
  public
    constructor Create(const AName, AExpression: string);
    property Name: string read FName;
    property Expression: string read FExpression;
  end;

  TSchemaField = class
  private
    FName: string;
    FFieldType: TSchemaFieldType;
    FLength: Integer;
    FPrecision: Integer;
    FScale: Integer;
    FAttributes: TSchemaFieldAttributes;
    FDefaultValue: string;
  public
    constructor Create(const AName: string; const AFieldType: TSchemaFieldType;
      const ALength, APrecision, AScale: Integer;
      const AAttributes: TSchemaFieldAttributes; const ADefaultValue: string);
    property Name: string read FName;
    property FieldType: TSchemaFieldType read FFieldType;
    property Length: Integer read FLength;
    property Precision: Integer read FPrecision;
    property Scale: Integer read FScale;
    property Attributes: TSchemaFieldAttributes read FAttributes;
    property DefaultValue: string read FDefaultValue;
  end;

  TSchemaAction = class
  private
    FId: string;
    FActionType: TSchemaActionType;
    FSourceName: string;
    FTargetName: string;
    FSql: string;
  public
    constructor Create(const AId: string; const AActionType: TSchemaActionType;
      const ASourceName, ATargetName, ASql: string);
    property Id: string read FId;
    property ActionType: TSchemaActionType read FActionType;
    property SourceName: string read FSourceName;
    property TargetName: string read FTargetName;
    property Sql: string read FSql;
  end;

  TTableSchema = class
  private
    FName: string;
    FFields: TObjectList<TSchemaField>;
    FActions: TObjectList<TSchemaAction>;
    FIndexes: TObjectList<TSchemaIndex>;
    FForeignKeys: TObjectList<TSchemaForeignKey>;
    FChecks: TObjectList<TSchemaCheck>;
    procedure AddDataAction(const AId, ASql: string);
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    function AddField(const AName: string; const AFieldType: TSchemaFieldType;
      const AAttributes: TSchemaFieldAttributes = []; const ADefaultValue: string = ''): TSchemaField; overload;
    function AddField(const AName: string; const AFieldType: TSchemaFieldType;
      const ALength: Integer; const AAttributes: TSchemaFieldAttributes = [];
      const ADefaultValue: string = ''): TSchemaField; overload;
    procedure RenameField(const AOldName, ANewName: string);
    procedure RemoveField(const AName: string);
    procedure AddIndex(const AName, AFields: string; const AUnique: Boolean = False);
    procedure AddForeignKey(const AName, AFieldName, ATargetTable,
      ATargetField: string; const AOnDelete: string = '');
    procedure AddCheck(const AName, AExpression: string);
    procedure ExecuteData(const AId, ASql: string);
    procedure InsertData(const AId, ASql: string);
    procedure DeleteData(const AId, ASql: string);
    property Name: string read FName;
    property Fields: TObjectList<TSchemaField> read FFields;
    property Actions: TObjectList<TSchemaAction> read FActions;
    property Indexes: TObjectList<TSchemaIndex> read FIndexes;
    property ForeignKeys: TObjectList<TSchemaForeignKey> read FForeignKeys;
    property Checks: TObjectList<TSchemaCheck> read FChecks;
  end;

implementation

constructor TSchemaField.Create(const AName: string; const AFieldType: TSchemaFieldType;
  const ALength, APrecision, AScale: Integer; const AAttributes: TSchemaFieldAttributes;
  const ADefaultValue: string);
begin
  inherited Create;
  FName := AName;
  FFieldType := AFieldType;
  FLength := ALength;
  FPrecision := APrecision;
  FScale := AScale;
  FAttributes := AAttributes;
  FDefaultValue := ADefaultValue;
end;

constructor TSchemaAction.Create(const AId: string; const AActionType: TSchemaActionType;
  const ASourceName, ATargetName, ASql: string);
begin
  inherited Create;
  FId := AId;
  FActionType := AActionType;
  FSourceName := ASourceName;
  FTargetName := ATargetName;
  FSql := ASql;
end;

constructor TSchemaIndex.Create(const AName, AFields: string; const AUnique: Boolean);
begin
  inherited Create;
  FName := AName;
  FFields := AFields;
  FUnique := AUnique;
end;

constructor TSchemaForeignKey.Create(const AName, AFieldName, ATargetTable,
  ATargetField, AOnDelete: string);
begin
  inherited Create;
  FName := AName;
  FFieldName := AFieldName;
  FTargetTable := ATargetTable;
  FTargetField := ATargetField;
  FOnDelete := AOnDelete;
end;

constructor TSchemaCheck.Create(const AName, AExpression: string);
begin
  inherited Create;
  FName := AName;
  FExpression := AExpression;
end;

constructor TTableSchema.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FFields := TObjectList<TSchemaField>.Create(True);
  FActions := TObjectList<TSchemaAction>.Create(True);
  FIndexes := TObjectList<TSchemaIndex>.Create(True);
  FForeignKeys := TObjectList<TSchemaForeignKey>.Create(True);
  FChecks := TObjectList<TSchemaCheck>.Create(True);
end;

destructor TTableSchema.Destroy;
begin
  FFields.Free;
  FActions.Free;
  FIndexes.Free;
  FForeignKeys.Free;
  FChecks.Free;
  inherited;
end;

procedure TTableSchema.RenameField(const AOldName, ANewName: string);
begin
  FActions.Add(TSchemaAction.Create('rename:' + AOldName + ':' + ANewName,
    satRenameField, AOldName, ANewName, ''));
end;

procedure TTableSchema.RemoveField(const AName: string);
begin
  FActions.Add(TSchemaAction.Create('remove:' + AName, satRemoveField, AName, '', ''));
end;

procedure TTableSchema.AddIndex(const AName, AFields: string; const AUnique: Boolean);
begin
  FIndexes.Add(TSchemaIndex.Create(AName, AFields, AUnique));
end;

procedure TTableSchema.AddForeignKey(const AName, AFieldName, ATargetTable,
  ATargetField, AOnDelete: string);
begin
  FForeignKeys.Add(TSchemaForeignKey.Create(AName, AFieldName, ATargetTable,
    ATargetField, AOnDelete));
end;

procedure TTableSchema.AddCheck(const AName, AExpression: string);
begin
  FChecks.Add(TSchemaCheck.Create(AName, AExpression));
end;

procedure TTableSchema.AddDataAction(const AId, ASql: string);
begin
  FActions.Add(TSchemaAction.Create(AId, satExecuteData, '', '', ASql));
end;

procedure TTableSchema.ExecuteData(const AId, ASql: string);
begin
  AddDataAction(AId, ASql);
end;

procedure TTableSchema.InsertData(const AId, ASql: string);
begin
  AddDataAction(AId, ASql);
end;

procedure TTableSchema.DeleteData(const AId, ASql: string);
begin
  AddDataAction(AId, ASql);
end;

function TTableSchema.AddField(const AName: string; const AFieldType: TSchemaFieldType;
  const AAttributes: TSchemaFieldAttributes; const ADefaultValue: string): TSchemaField;
begin
  Result := TSchemaField.Create(AName, AFieldType, 0, 0, 0, AAttributes, ADefaultValue);
  FFields.Add(Result);
end;

function TTableSchema.AddField(const AName: string; const AFieldType: TSchemaFieldType;
  const ALength: Integer; const AAttributes: TSchemaFieldAttributes;
  const ADefaultValue: string): TSchemaField;
begin
  Result := TSchemaField.Create(AName, AFieldType, ALength, 0, 0, AAttributes, ADefaultValue);
  FFields.Add(Result);
end;

end.
