{ Process utility unit

  Copyright (c) 2012 Ludo Brands

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to
  deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
}
unit processutils;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, process, strutils;

const
  // Error code/result code:
  PROC_INTERNALERROR=-1;
type
  TProcessEx=class; //forward
  TDumpFunc = procedure (Sender:TProcessEx; output:string);
  TDumpMethod = procedure (Sender:TProcessEx; output:string) of object;
  TErrorFunc = procedure (Sender:TProcessEx;IsException:boolean);
  TErrorMethod = procedure (Sender:TProcessEx;IsException:boolean) of object;
  { TProcessEnvironment }

  TProcessEnvironment = class(TObject)
    private
      FEnvironmentList:TStringList;
      FCaseSensitive:boolean;
      function GetVarIndex(VarName:string):integer;
    public
      function GetVar(VarName:string):string;
      procedure SetVar(VarName,VarValue:string);
      property EnvironmentList:TStringList read FEnvironmentList;
      constructor Create;
      destructor Destroy; override;
    end;

  { TProcessEx }

  TProcessEx = class(TProcess)
    private
      FExceptionInfoStrings: TstringList;
      FExecutable: string;
      FExitStatus: integer;
      FOnError: TErrorFunc;
      FOnErrorM: TErrorMethod;
      FOnOutput: TDumpFunc;
      FOnOutputM: TDumpMethod;
      FOutputStrings: TstringList;
      FOutStream: TMemoryStream;
      FProcessEnvironment:TProcessEnvironment;
      function GetResultingCommand: string;
      function GetExceptionInfo: string;
      function GetOutputString: string;
      function GetOutputStrings: TstringList;
      function GetParametersString: String;
      function GetProcessEnvironment: TProcessEnvironment;
      procedure SetOnError(AValue: TErrorFunc);
      procedure SetOnErrorM(AValue: TErrorMethod);
      procedure SetOnOutput(AValue: TDumpFunc);
      procedure SetOnOutputM(AValue: TDumpMethod);
    public
      procedure Execute;
      // Executable+parameters. Use Executable and Parameters/ParametersString to assign
      property ResultingCommand: string read GetResultingCommand;
      property Environment:TProcessEnvironment read GetProcessEnvironment;
      property ExceptionInfo:string read GetExceptionInfo;
      property ExceptionInfoStrings:TstringList read FExceptionInfoStrings;
      property ExitStatus:integer read FExitStatus;
      property OnError:TErrorFunc read FOnError write SetOnError;
      property OnErrorM:TErrorMethod read FOnErrorM write SetOnErrorM;
      property OnOutput:TDumpFunc read FOnOutput write SetOnOutput;
      property OnOutputM:TDumpMethod read FOnOutputM write SetOnOutputM;
      property OutputString:string read GetOutputString;
      property OutputStrings:TstringList read GetOutputStrings;
      constructor Create(AOwner : TComponent); override;
      destructor Destroy; override;
    end;

// Convenience functions

function ExecuteCommand(Commandline: string; Verbose:boolean): integer; overload;
function ExecuteCommand(Commandline: string; var Output:string; Verbose:boolean): integer; overload;
function ExecuteCommandInDir(Commandline, Directory: string; Verbose:boolean): integer; overload;
function ExecuteCommandInDir(Commandline, Directory: string; var Output:string; Verbose:boolean): integer; overload;
procedure DumpConsole(Sender:TProcessEx; output:string);



implementation

{ TProcessEx }

function TProcessEx.GetOutputString: string;
begin
  result:=OutputStrings.Text;
end;

function TProcessEx.GetOutputStrings: TstringList;
begin
  if (FOutputStrings.Count=0) and (FOutStream.Size>0) then
    begin
    FOutStream.Position := 0;
    FOutputStrings.LoadFromStream(FOutStream);
    end;
  result:=FOutputStrings;
end;

function TProcessEx.GetParametersString: String;
begin
  result:=AnsiReplaceStr(Parameters.text, LineEnding, ' ');
end;

function TProcessEx.GetExceptionInfo: string;
begin
  result:=FExceptionInfoStrings.Text;
end;

function TProcessEx.GetResultingCommand: string;
var i:integer;
begin
  //this is not the command as executed. The quotes are surrounding individual params.
  //the actual quoting is platform dependant
  //perhaps better to use another quoting character to make this clear to the user.
  result:=Executable;
  for i:=0 to Parameters.Count-1 do
    result:=result+' "'+Parameters[i]+'"';
end;

function TProcessEx.GetProcessEnvironment: TProcessEnvironment;
begin
  If not assigned(FProcessEnvironment) then
    FProcessEnvironment:=TProcessEnvironment.Create;
  result:=FProcessEnvironment;
end;

procedure TProcessEx.SetOnError(AValue: TErrorFunc);
begin
  if FOnError=AValue then Exit;
  FOnError:=AValue;
end;

procedure TProcessEx.SetOnErrorM(AValue: TErrorMethod);
begin
  if FOnErrorM=AValue then Exit;
  FOnErrorM:=AValue;
end;

procedure TProcessEx.SetOnOutput(AValue: TDumpFunc);
begin
  if FOnOutput=AValue then Exit;
  FOnOutput:=AValue;
end;

procedure TProcessEx.SetOnOutputM(AValue: TDumpMethod);
begin
  if FOnOutputM=AValue then Exit;
  FOnOutputM:=AValue;
end;

procedure TProcessEx.Execute;

  function ReadOutput: boolean;

  const
    BufSize = 4096;
  var
    Buffer: array[0..BufSize - 1] of byte;
    ReadBytes: integer;
  begin
    Result := False;
    while Output.NumBytesAvailable > 0 do
    begin
      ReadBytes := Output.Read(Buffer, BufSize);
      FOutStream.Write(Buffer, ReadBytes);
      if Assigned(FOnOutput) then
        FOnOutput(Self,copy(pchar(@buffer[0]),1,ReadBytes));
      if Assigned(FOnOutputM) then
        FOnOutputM(Self,copy(pchar(@buffer[0]),1,ReadBytes));
      Result := True;
    end;
  end;

begin
  try
    // "Normal" linux and DOS exit codes are in the range 0 to 255.
    // Windows System Error Codes are 0 to 15999
    // Use negatives for internal errors.
    FExitStatus:=PROC_INTERNALERROR;
    FExceptionInfoStrings.Clear;
    FOutputStrings.Clear;
    FOutStream.Clear;
    if Assigned(FProcessEnvironment) then
      inherited Environment:=FProcessEnvironment.EnvironmentList;
    Options := Options +[poUsePipes, poStderrToOutPut];
    if Assigned(FOnOutput) then
      FOnOutput(Self,'Executing : '+ResultingCommand+' (working dir: '+ CurrentDirectory +')'+ LineEnding);
    if Assigned(FOnOutputM) then
      FOnOutputM(Self,'Executing : '+ResultingCommand+' (working dir: '+ CurrentDirectory +')'+ LineEnding);

    try
      inherited Execute;
    except
      // Leave exitstatus as proc_internalerror
      // This should handle calling non-existing application etc.
    end;

    while Running do
    begin
      if not ReadOutput then
        Sleep(50);
    end;
    ReadOutput;
    FExitStatus:=inherited ExitStatus;
    if (FExitStatus<>0) and (Assigned(OnError) or Assigned(OnErrorM))  then
      if Assigned(OnError) then
        OnError(Self,false)
      else
        OnErrorM(Self,false);
  except
    on E: Exception do
    begin
    FExceptionInfoStrings.Add('Exception calling '+Executable+' '+Parameters.Text);
    FExceptionInfoStrings.Add('Details: '+E.ClassName+'/'+E.Message);
    FExitStatus:=-2;
    if Assigned(OnError) then
      OnError(Self,true);
    end;
  end;
end;

constructor TProcessEx.Create(AOwner : TComponent);
begin
  inherited;
  FExceptionInfoStrings:= TstringList.Create;
  FOutputStrings:= TstringList.Create;
  FOutStream := TMemoryStream.Create;
end;

destructor TProcessEx.Destroy;
begin
  FExceptionInfoStrings.Free;
  FOutputStrings.Free;
  FOutStream.Free;
  If assigned(FProcessEnvironment) then
    FProcessEnvironment.Free;
  inherited Destroy;
end;

{ TProcessEnvironment }

function TProcessEnvironment.GetVarIndex(VarName: string): integer;
var
  idx:integer;

  function ExtractVar(VarVal:string):string;
  begin
    result:='';
    if length(Varval)>0 then
      begin
      if VarVal[1] = '=' then //windows
        delete(VarVal,1,1);
      result:=trim(copy(VarVal,1,pos('=',VarVal)-1));
      if not FCaseSensitive then
        result:=UpperCase(result);
      end
  end;

begin
  if not FCaseSensitive then
    VarName:=UpperCase(VarName);
  idx:=0;
  while idx<FEnvironmentList.Count  do
    begin
    if VarName = ExtractVar(FEnvironmentList[idx]) then
      break;
    idx:=idx+1;
    end;
  if idx<FEnvironmentList.Count then
    result:=idx
  else
    result:=-1;
end;

function TProcessEnvironment.GetVar(VarName: string): string;
var
  idx:integer;

  function ExtractVal(VarVal:string):string;
  begin
    result:='';
    if length(Varval)>0 then
      begin
      if VarVal[1] = '=' then //windows
        delete(VarVal,1,1);
      result:=trim(copy(VarVal,pos('=',VarVal)+1,length(VarVal)));
      end
  end;

begin
  idx:=GetVarIndex(VarName);
  if idx>0 then
    result:=ExtractVal(FEnvironmentList[idx])
  else
    result:='';
end;

procedure TProcessEnvironment.SetVar(VarName, VarValue: string);
var
  idx:integer;
  s:string;
begin
  idx:=GetVarIndex(VarName);
  s:=trim(Varname)+'='+trim(VarValue);
  if idx>0 then
    FEnvironmentList[idx]:=s
  else
    FEnvironmentList.Add(s);
end;

constructor TProcessEnvironment.Create;
var
  i: integer;
begin
  FEnvironmentList:=TStringList.Create;
  {$ifdef WINDOWS}
  FCaseSensitive:=false;
  {$else}
  FCaseSensitive:=true;
  {$endif WINDOWS}
  // GetEnvironmentVariableCount is 1 based
  for i:=1 to GetEnvironmentVariableCount do
    EnvironmentList.Add(trim(GetEnvironmentString(i)));
end;

destructor TProcessEnvironment.Destroy;
begin
  FEnvironmentList.Free;
  inherited Destroy;
end;


procedure DumpConsole(Sender:TProcessEx; output:string);
begin
  write(output);
end;

function ExecuteCommand(Commandline: string; Verbose: boolean): integer;
var
  s:string;
begin
  Result:=ExecuteCommandInDir(Commandline,'',s,Verbose);
end;

function ExecuteCommand(Commandline: string; var Output: string;
  Verbose: boolean): integer;
begin
  Result:=ExecuteCommandInDir(Commandline,'',Output,Verbose);
end;

function ExecuteCommandInDir(Commandline, Directory: string; Verbose: boolean
  ): integer;
var
  s:string;
begin
  Result:=ExecuteCommandInDir(Commandline,Directory,s,Verbose);
end;

function ExecuteCommandInDir(Commandline, Directory: string;
  var Output: string; Verbose: boolean): integer;
var
  PE:TProcessEx;
  s:string;

  function GetFirstWord:string;
  var
    i:integer;
    LastQuote:char;
    InQuote:boolean;
  const
    QUOTES = ['"',''''];
  begin
  Commandline:=trim(Commandline);
  i:=1;
  InQuote:=false;
  while (i<length(Commandline)) and (InQuote or (Commandline[i]>' ')) do
    begin
    if Commandline[i] in QUOTES then
      if InQuote then
        begin
        if Commandline[i]=LastQuote then
          begin
          InQuote:=false;
          delete(Commandline,i,1);
          i:=i-1
          end;
        end
      else
        begin
        InQuote:=True;
        LastQuote:=Commandline[i];
        delete(Commandline,i,1);
        i:=i-1
        end;
    i:=i+1;
    end;
  result:=trim(copy(Commandline,1,i));
  delete(Commandline,1,i);
  end;

begin
  PE:=TProcessEx.Create(nil);
  try
    if Directory<>'' then
      PE.CurrentDirectory:=Directory;
    PE.Executable:=GetFirstWord;
    s:=GetFirstWord;
    while s<>'' do
      begin
      PE.Parameters.Add(s);
      s:=GetFirstWord;
      end;
    PE.ShowWindow := swoHIDE;
    if Verbose then
      PE.OnOutput:=@DumpConsole;
    PE.Execute;
    Output:=PE.OutputString;
    Result:=PE.ExitStatus;
  finally
    PE.Free;
  end;
end;

end.

