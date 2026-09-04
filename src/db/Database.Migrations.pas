unit Database.Migrations;

interface

uses
  FireDAC.Comp.Client;

type
  TDatabaseMigrator = class
  public
    class procedure ApplyPending(const AConnection: TFDConnection); static;
  end;

implementation

uses
  FireDAC.Stan.Param;

type
  TDatabaseMigration = class abstract
  public
    function Id: string; virtual; abstract;
    procedure Apply(const AConnection: TFDConnection); virtual; abstract;
  end;

  TInitialSchemaMigration = class(TDatabaseMigration)
  public
    function Id: string; override;
    procedure Apply(const AConnection: TFDConnection); override;
  end;

procedure ExecuteSql(const AConnection: TFDConnection; const ASql: string);
begin
  AConnection.ExecSQL(ASql);
end;

function MigrationApplied(const AConnection: TFDConnection; const AMigrationId: string): Boolean;
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'select exists(select 1 from schema_migrations where migration_id = :migration_id) as applied';
    Query.ParamByName('migration_id').AsString := AMigrationId;
    Query.Open;
    Result := Query.FieldByName('applied').AsBoolean;
  finally
    Query.Free;
  end;
end;

procedure RegisterMigration(const AConnection: TFDConnection; const AMigrationId: string);
begin
  AConnection.ExecSQL(
    'insert into schema_migrations (migration_id) values (:migration_id)',
    [AMigrationId]);
end;

function TInitialSchemaMigration.Id: string;
begin
  Result := '0001_core';
end;

procedure TInitialSchemaMigration.Apply(const AConnection: TFDConnection);
const
  Statements: array[0..12] of string = (
    'create extension if not exists pgcrypto',
    'create table app_users (' +
      'id uuid primary key default gen_random_uuid(), email text not null unique, ' +
      'display_name text not null, password_hash text not null, ' +
      'platform_role text not null default ''user'' check (platform_role in (''user'', ''superadmin'')), ' +
      'created_at timestamptz not null default now(), disabled_at timestamptz)',
    'create table organizations (' +
      'id uuid primary key default gen_random_uuid(), legal_name text not null, ' +
      'organization_type text not null check (organization_type in (''accountant'', ''erp_vendor'', ''reseller'')), ' +
      'created_by_user_id uuid not null references app_users(id), created_at timestamptz not null default now())',
    'create table organization_members (' +
      'organization_id uuid not null references organizations(id) on delete cascade, ' +
      'user_id uuid not null references app_users(id) on delete cascade, ' +
      'role text not null check (role in (''owner'', ''admin'', ''member'')), ' +
      'created_at timestamptz not null default now(), primary key (organization_id, user_id))',
    'create table companies (' +
      'id uuid primary key default gen_random_uuid(), cnpj text not null unique, legal_name text not null, ' +
      'onboarded_by_user_id uuid not null references app_users(id), created_at timestamptz not null default now(), ' +
      'disabled_at timestamptz, check (cnpj ~ ''^[0-9A-Z]{14}$''))',
    'create table company_user_access (' +
      'company_id uuid not null references companies(id) on delete cascade, ' +
      'user_id uuid not null references app_users(id) on delete cascade, ' +
      'role text not null check (role in (''owner'', ''admin'', ''viewer'')), ' +
      'granted_by_user_id uuid not null references app_users(id), created_at timestamptz not null default now(), ' +
      'revoked_at timestamptz, primary key (company_id, user_id))',
    'create table company_organization_access (' +
      'company_id uuid not null references companies(id) on delete cascade, ' +
      'organization_id uuid not null references organizations(id) on delete cascade, ' +
      'role text not null check (role in (''accountant'', ''erp_vendor'', ''reseller'')), ' +
      'granted_by_user_id uuid not null references app_users(id), created_at timestamptz not null default now(), ' +
      'revoked_at timestamptz, primary key (company_id, organization_id))',
    'create table company_certificates (' +
      'id uuid primary key default gen_random_uuid(), company_id uuid not null references companies(id) on delete cascade, ' +
      'uploaded_by_user_id uuid not null references app_users(id), encryption_key_ref text not null, ' +
      'encrypted_certificate bytea not null, encrypted_password bytea not null, sha256 text not null unique, ' +
      'valid_until date, created_at timestamptz not null default now(), revoked_at timestamptz)',
    'create table fiscal_monitor_settings (' +
      'company_id uuid primary key references companies(id) on delete cascade, ' +
      'auto_register_awareness boolean not null default false, ' +
      'auto_download_after_manifestation boolean not null default false, ' +
      'updated_by_user_id uuid not null references app_users(id), updated_at timestamptz not null default now())',
    'create table fiscal_documents (' +
      'id uuid primary key default gen_random_uuid(), company_id uuid not null references companies(id) on delete cascade, ' +
      'access_key text not null, document_type text not null, issued_at timestamptz, issuer_cnpj text, ' +
      'total_amount numeric(18, 2), status text not null check (status in ' +
      '(''located'', ''awareness_registered'', ''manifested'', ''xml_available'', ''cancelled'')), ' +
      'xml_object_key text, xml_sha256 text, created_at timestamptz not null default now(), ' +
      'updated_at timestamptz not null default now(), unique (company_id, access_key))',
    'create table erp_integrations (' +
      'id uuid primary key default gen_random_uuid(), company_id uuid not null references companies(id) on delete cascade, ' +
      'erp_organization_id uuid references organizations(id), display_name text not null, ' +
      'api_token_hash text not null unique, scopes jsonb not null default ''["documents:read"]''::jsonb, ' +
      'created_at timestamptz not null default now(), revoked_at timestamptz)',
    'create table audit_events (' +
      'id uuid primary key default gen_random_uuid(), company_id uuid references companies(id) on delete set null, ' +
      'actor_user_id uuid references app_users(id) on delete set null, event_type text not null, ' +
      'payload jsonb not null default ''{}''::jsonb, created_at timestamptz not null default now())',
    'create index fiscal_documents_company_status_idx on fiscal_documents (company_id, status, issued_at desc)'
  );
var
  Statement: string;
begin
  for Statement in Statements do
    ExecuteSql(AConnection, Statement);
  ExecuteSql(AConnection,
    'create index audit_events_company_created_idx on audit_events (company_id, created_at desc)');
end;

class procedure TDatabaseMigrator.ApplyPending(const AConnection: TFDConnection);
var
  Migration: TDatabaseMigration;
begin
  ExecuteSql(AConnection,
    'create table if not exists schema_migrations (' +
    'migration_id text primary key, applied_at timestamptz not null default now())');

  Migration := TInitialSchemaMigration.Create;
  try
    if MigrationApplied(AConnection, Migration.Id) then
      Exit;

    AConnection.StartTransaction;
    try
      Migration.Apply(AConnection);
      RegisterMigration(AConnection, Migration.Id);
      AConnection.Commit;
    except
      AConnection.Rollback;
      raise;
    end;
  finally
    Migration.Free;
  end;
end;

end.
