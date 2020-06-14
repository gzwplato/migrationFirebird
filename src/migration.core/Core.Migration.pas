unit Core.Migration;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, System.IoUtils,

  FireDAC.Comp.Client, FireDAC.Comp.DataSet,

  uCommands,

  Core.ScriptExecutor,

  Conn.Connection.DB.Firebird, Conn.connection.Singleton.Firebird;


type

  TMigration = class
  strict private
    const HistoryTableName = 'HISTORY_MIGRATION';
  private
    FConexao : TConnConnectionFirebird;
    ScriptExecutor : TScriptExecutor;
    FArgs:TArgs;

    function GetListNoExecutedFiles(): TArray<String>;
    procedure InsertFilesOnDataBase;
    procedure CreateTheHistoryTable;
    procedure UpdateHistotyTable(Const ArrayOfFiles : TArray<String>);
    function HistoryTableExists: Boolean;
    procedure ExecuteScript(aFileName: String);
    procedure UpdateScriptExecuted(aFileName:String; aDuration:TDateTime);
  public
    Constructor Create();
    Destructor Destroy(); override;

    function Execute():TMigration;
    class function New(aArgs:TArgs):TMigration;
  end;

implementation

{ TMigration }

uses common.Types;

constructor TMigration.Create;
begin
  inherited Create();
  Self.FConexao                  := TConexaoSingleton.GetInstance();
  Self.ScriptExecutor            := TScriptExecutor.New();
end;

destructor TMigration.Destroy;
begin
  FreeAndNil(ScriptExecutor);
  inherited;
end;

procedure TMigration.UpdateScriptExecuted(aFileName:String; aDuration:TDateTime);
Const
  _Sql :String = ' UPDATE HISTORY_MIGRATION SET '+
                 ' EXECUTED = TRUE, '+
                 ' EXECUTION_TIME = :EXECUTION_TIME, '+
                 ' EXECUTION_DATE = :EXECUTION_DATE, '+
                 ' EXECUTION_DURATION = :EXECUTION_DURATION '+
                 ' WHERE FILE_NAME = :FILE_NAME';
begin
  var Q := Self.FConexao.GetQuery(_Sql);
  try
    Q.ParamByName('EXECUTION_TIME').AsTime     := Now;
    Q.ParamByName('EXECUTION_DATE').AsDate     := Now;
    Q.ParamByName('EXECUTION_DURATION').AsTime := aDuration;
    Q.ParamByName('FILE_NAME').AsString        := ExtractFileName(aFileName);

    Q.ExecSQL;

    writeLn('Migration executed ',Q.ParamByName('FILE_NAME').AsString);
  finally
    FreeAndNil(Q);
  end;
end;

procedure TMigration.ExecuteScript(aFileName:String);
begin
  Self.FConexao.StartTransaction();
  try
    ScriptExecutor.Script.SQLScripts.Clear();
    ScriptExecutor.Script.SQLScriptFileName := aFileName;
    var Duration := now;
    if ScriptExecutor.Script.ExecuteAll() then begin
      UpdateScriptExecuted(aFileName, Now - Duration);
      Self.FConexao.CommitTransaction();
    end
    else self.FConexao.RollbackTransaction();
  except
    on E:Exception do begin
      Self.FConexao.RollbackTransaction();
      raise;
    end;

  end;

end;

function TMigration.Execute(): TMigration;
begin
  Result := Self;

  Var ArrayOfFiles :TArray<String> := GetListNoExecutedFiles();

  if Length(ArrayOfFiles) = 0 then writeLn('up to date!');

  for var sFileName : String in ArrayOfFiles do begin
    Var Dir := TPath.Combine(GetCurrentDir, sFileName);
    Self.ExecuteScript(Dir);
  end;


end;

class function TMigration.New(aArgs:TArgs): TMigration;
begin
  Result := TMigration.Create();
  Result.FArgs := aArgs;

end;

function TMigration.GetListNoExecutedFiles():TArray<String>;
const
  _Sql:String = 'SELECT A.FILE_NAME FROM HISTORY_MIGRATION A WHERE NOT A.EXECUTED';
begin
  InsertFilesOnDataBase();
  var Query :TFDQuery := Self.FConexao.GetQuery(_Sql);
  try
    Query.First();
    SetLength(Result, Query.RecordCount);
    while not Query.eof do begin
      Result[pred(Query.RecNo)] := Query.FieldByName('FILE_NAME').AsString;

      Query.Next();
    end;

  finally
    FreeAndNil(Query);
  end;
end;

procedure TMigration.InsertFilesOnDataBase();
begin
  CreateTheHistoryTable();
  Var ArrayOfFiles : TArray<String> := TDirectory.GetFiles(GetCurrentDir, TFindFileExpression.Migration);
  UpdateHistotyTable(ArrayOfFiles);
end;

function TMigration.HistoryTableExists():Boolean;
const
  _Sql : String = 'Select RDB$RELATION_NAME from RDB$relations WHERE RDB$RELATION_NAME = %s;';
begin
  var Q :TFDQuery := Self.FConexao.GetQuery(_sql,[Self.HistoryTableName.QuotedString]);
  try
    Result := Q.RecordCount > 0;
  finally
    FreeAndNil(Q)
  end;

end;

procedure TMigration.CreateTheHistoryTable();
const
  _Sql:String = 'create table HISTORY_MIGRATION( ' +
                  'ID_HISTORY INTEGER GENERATED BY DEFAULT AS IDENTITY NOT NULL PRIMARY KEY, ' +
                  'FILE_NAME VARCHAR(200) NOT NULL, ' +
                  'EXECUTION_TIME TIME, ' +
                  'EXECUTION_DATE DATE, ' +
                  'EXECUTION_DURATION TIME, ' +
                  'EXECUTED BOOLEAN DEFAULT FALSE' +
                '); ';

begin
  if HistoryTableExists() then exit();

  Self.FConexao.StartTransaction();
  try

    Self.FConexao.ExecuteCommand(_Sql);

    Self.FConexao.CommitTransaction();
  except
    on E:Exception do begin
      Self.FConexao.RollbackTransaction();
      raise;
    end;
  end;
end;

procedure TMigration.UpdateHistotyTable(Const ArrayOfFiles : TArray<String>);
Const
  _Sql : String = 'UPDATE OR INSERT INTO HISTORY_MIGRATION(FILE_NAME) VALUES(:FILE_NAME) MATCHING(FILE_NAME)';
begin
  var QueryFiles : TFDQuery := Self.FConexao.GetQuery(_Sql);
  try
    QueryFiles.Params.ArraySize := Length(ArrayOfFiles);

    for Var i:Integer := 0 to pred(length(ArrayOfFiles)) do
      QueryFiles.Params.ParamByName('FILE_NAME').AsStrings[i] := ExtractFileName(ArrayOfFiles[i]);

    Self.FConexao.StartTransaction();
    try
      QueryFiles.Execute(QueryFiles.Params.ArraySize);

      Self.FConexao.CommitTransaction();
    except
      on E: Exception do begin
        self.FConexao.RollbackTransaction();
        raise;
      end;
    end;
  finally
    FreeAndNil(QueryFiles);
  end;

end;

end.
