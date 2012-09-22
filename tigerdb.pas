unit tigerdb;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,  sqldb,
  ibconnection {Firebird},
  pqconnection {PostgreSQL},
  sqlite3conn {SQLite};

type
{ TTigerDB }

TTigerDB= class(TObject)
private
  FDB: TSQLConnection; //Database connection
  FDBHost: string; //Database connection details
  FDBPath: string; //Database connection details
  FDBType: string; //Database connection details
  FDBPassword: string; //Database connection details
  FDBUser: string; //Database connection details
  FInsertScan: TSQLQuery; //Inserts new scan data.
  FReadTransaction: TSQLTransaction; //Transaction for read-only access
  FReadWriteTransaction: TSQLTransaction; //Transaction for read/write access
public
  procedure InsertScan(DocumentName, DocumentPath, DocumentHash: string; TheScanDate: TDateTime); //Insterts a new scan record in database. Keep string values empty to insert NULLs; pass a pre 1900 date for TheScanDate to do the same.
  constructor Create;
  destructor Destroy; override;
end;

implementation

uses
  inifiles, dateutils;

const
  SettingsFile = 'tigerserver.ini';


{ TTigerDB }

procedure TTigerDB.InsertScan(DocumentName, DocumentPath, DocumentHash: string;
  TheScanDate: TDateTime);
begin
  try
    if FReadWriteTransaction.Active = false then
      FReadWriteTransaction.StartTransaction;
    if DocumentName='' then
      // NULL
      FInsertScan.ParamByName('DOCUMENTNAME').Clear
    else
      FInsertScan.ParamByName('DOCUMENTNAME').AsString:=DocumentName;
    if DocumentPath='' then
      // NULL
      FInsertScan.ParamByName('PATH').Clear
    else
      FInsertScan.ParamByName('PATH').AsString:=DocumentPath;
    if DocumentHash='' then
      // NULL
      FInsertScan.ParamByName('DOCUMENTHASH').Clear
    else
      FInsertScan.ParamByName('DOCUMENTHASH').AsString:=DocumentHash;
    // Scan dates before 1900 must be fake
    if TheScanDate < EncodeDate(1900,1,1) then
      // NULL
      FInsertScan.ParamByName('SCANDATE').Clear
    else
      FInsertScan.ParamByName('SCANDATE').AsDateTime:=TheScanDate;

    FInsertScan.ExecSQL;
    FReadWriteTransaction.Commit;
  except
    on E: EIBDatabaseError do
    begin
      if FReadWriteTransaction.Active then
      FReadWriteTransaction.Rollback;
        writeln('Database error: ' + E.Message + '(error code: ' + IntToStr(E.GDSErrorCode) + ')');
        writeln('');
        //todo: fix this
        {
        log('Database error: ' + E.Message + '(error code: ' + IntToStr(E.GDSErrorCode) + ')' + LineEnding +
          'Deleted tweet ID: ' + IntToStr(Tweets[i].ID) + LineEnding + '');
        }
    end;
    on F: Exception do
    begin
      if FReadWriteTransaction.Active then
        FReadWriteTransaction.Rollback;
      writeln('Exception: ' + F.ClassName + '/' + F.Message);
      writeln('');
      //todo: add logging; get rid of writelns
      {
      log('Error: ' + F.Message + LineEnding + 'Deleted tweet ID: ' + IntToStr(Tweets[i].ID) + LineEnding + '');
      }
    end;
  end;
end;

constructor TTigerDB.Create;
var
  Settings: TINIFile;
begin
  inherited Create;
  if FileExists(SettingsFile) then
  begin
    Settings := TINIFile.Create(SettingsFile);
    try
      FDBType := Settings.ReadString('Database', 'DatabaseType', 'Firebird'); //Default to Firebird
      FDBHost := Settings.ReadString('Database', 'Host', ''); //default to embedded
      FDBPath := Settings.ReadString('Database', 'Database', 'tiger.fdb');
      FDBUser := Settings.ReadString('Database', 'User', 'SYSDBA');
      FDBPassword := Settings.ReadString('Database', 'Password', 'masterkey');
    finally
      Settings.Free;
    end;
  end
  else
  begin
    // Set up defaults for database
    FDBType := 'Firebird';
    FDBHost := '';
    FDBPath := 'tiger.fdb';
    FDBUser := 'SYSDBA';
    FDBPassword := 'masterkey';
  end;
  case UpperCase(FDBType) of
    'FIREBIRD': FDBType:='Firebird';
    'POSTGRES', 'POSTGRESQL': FDBType:='PostgreSQL';
    'SQLITE','SQLITE3': FDBType:='SQLite';
    else
    begin
      writeln('Warning: unknown database type ' + FDBType + ' specified.');
      writeln('Defaulting to Firebird');
      FDBType:='Firebird';
    end;
  end;

  // Set up db connection
  case FDBType of
    'Firebird': FDB := TIBConnection.Create(nil);
    'PostgreSQL': FDB := TPQConnection.Create(nil);
    'SQLite': FDB := TSQLite3Connection.Create(nil);
  end;
  FReadWriteTransaction := TSQLTransaction.Create(nil);
  FReadTransaction:=TSQLTransaction.Create(nil);
  FInsertScan:=TSQLQuery.Create(nil);

  if FDBType='SQLite' then
    FDB.Hostname:=''
  else
    FDB.HostName := FDBHost;
  FDB.DatabaseName := FDBPath;
  FDB.UserName := FDBUser;
  FDB.Password := FDBPassword;
  FDB.CharSet := 'UTF8';
  if FDBType = 'Firebird' then
    TIBConnection(FDB).Dialect := 3; //just to be sure

  // Check for existing database
  if (FDBHost='') and (FileExists(FDB.DatabaseName)=false) then
    if (FDBType='Firebird') then
      TIBConnection(FDB).CreateDB
    else if (FDBType='sqlite') then
      TSQLite3Connection(FDB).CreateDB;
  FDB.Open;
  FDB.Transaction := FReadWriteTransaction; //Default transaction for database

  // todo: Check for+create required tables

  FInsertScan.Database := FDB;
  FInsertScan.Transaction := FReadWriteTransaction;
  FInsertScan.SQL.Text := 'INSERT INTO DOCUMENTS (DOCUMENTNAME,PATH,SCANDATE,DOCUMENTHASH) '
    +'VALUES (:DOCUMENTNAME,:PATH,:SCANDATE,:DOCUMENTHASH) RETURNING ID';
  FInsertScan.Prepare;
end;

destructor TTigerDB.Destroy;
begin
  if Assigned(FInsertScan) then
    FInsertScan.Close;
  if Assigned(FReadWriteTransaction) then
    FReadWriteTransaction.Rollback;
  if Assigned(FReadTransaction) then
    FReadTransaction.Rollback;
  if Assigned(FDB) then
    FDB.Connected := false;
  FInsertScan.Free;
  FReadWriteTransaction.Free;
  FReadTransaction.Free;
  FDB.Free;
  inherited Destroy;
end;

end.
