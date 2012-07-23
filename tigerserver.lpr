program tigerserver;
{ Paper Tiger paper scanning/OCR/archiving solution

  Copyright (c) 2012 Reinier Olislagers

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

{$i tigerserver.inc}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, SysUtils, CustApp, scan, ocr;

type

  { TTigerServer }

  TTigerServer = class(TCustomApplication)
  protected
    procedure DoRun; override;
    procedure ProcessImage(ImageFile: string);
    procedure ScanAndProcess;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
  end;

{ TTigerServer }

procedure TTigerServer.DoRun;
var
  ErrorMsg: String;
begin
  // quick check parameters
  ErrorMsg:=CheckOptions('hi:s','help image: scan');
  if ErrorMsg<>'' then
  begin
    ShowException(Exception.Create(ErrorMsg));
    Terminate;
    Exit;
  end;

  // parse parameters
  if HasOption('h','help') then
  begin
    WriteHelp;
    Terminate;
    Exit;
  end;

  if HasOption('i','image') then
  begin
    ProcessImage(GetOptionValue('i','image'));
  end;

  if HasOption('s','scan') then
  begin
    ScanAndProcess;
  end;

  // stop program loop
  Terminate;
end;

procedure TTigerServer.ProcessImage(ImageFile: string);
var
  OCR: TOCR;
begin
  //todo: add preprocess unit??! despeckle, deskew etc? ScanTailor?
  OCR:=TOCR.Create;
  try
    if ImageFile<>'' then
    begin
      OCR.ImageFile:=ImageFile;
      OCR.RecognizeText;
      writeln('Got this text:');
      writeln(OCR.Text);
    end;
  finally
    OCR.Free;
  end;
  // Need Tesseract 3 for hocr output?
  // Create searchable PDF using exactimage
  //hocr2pdf -i scan.tiff -s -o test.pdf < cuneiform-out.hocr
end;

procedure TTigerServer.ScanAndProcess;
// Performs the document scan, and process result
var
  ImageFile: string;
  Scanner: TScanner;
begin
  Scanner:=TScanner.Create;
  try
    Scanner.Scan;
    //todo: figure out if grayscale/lineart works better for OCR; convert if necessary
    //todo: lineart or grayscale default for docs? 600DPI lineart perhaps?
    ImageFile:=Scanner.FileName;
    writeln('Image file: '+ImageFile);
    //todo: add teventlog logging support
  finally
    Scanner.Free;
  end;
  ProcessImage(ImageFile);
end;

constructor TTigerServer.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException:=True;
end;

destructor TTigerServer.Destroy;
begin
  inherited Destroy;
end;

procedure TTigerServer.WriteHelp;
begin
  writeln('Usage: ',ExeName,' -h');
  writeln('-i --image <image>');
  writeln(' Process image.');
  writeln('-s --scan: scan');
  writeln(' Scan document, process.');
end;

var
  Application: TTigerServer;
begin
  Application:=TTigerServer.Create(nil);
  Application.Run;
  Application.Free;
end.

