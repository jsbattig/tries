(*
  The MIT License (MIT)

  Copyright (c) 2015 Jose Sebastian Battig

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
*)

unit StringHashTrie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  SysUtils,
  Trie,
  Hash_Trie,
  trieAllocators,
  Classes
  {$IFDEF UNICODE},AnsiStrings {$ENDIF};

type
  TStrHashTraverseProc = procedure(UserData: Pointer; Key: PAnsiChar;
    Data: TObject; var Done: Boolean);
  TStrHashTraverseMeth = procedure(UserData: Pointer; Key: PAnsiChar;
    Data: TObject; var Done: Boolean) of object;
  {$IFDEF UNICODE}
  TUTF16StrHashTraverseProc = procedure(UserData: Pointer; Key: PChar;
    Data: TObject; var Done: Boolean);
  TUTF16StrHashTraverseMeth = procedure(UserData: Pointer; Key: PChar;
    Data: TObject; var Done: Boolean) of object;
  {$ENDIF}

  EStringHashTrie = class(ETrie);
  { TStringHashTrie }
  TStringHashTrie = class(THashTrie)
  private
    FCaseInsensitive: Boolean;
    FPAnsiCharAllocator : TVariableBlockHeap;
    procedure InitTraversal(out It : THashTrieIterator; out ADone : Boolean); inline;
    {$IFDEF UNICODE}
    procedure CheckCaseInsensitiveWithUTF16; inline;
    {$ENDIF}
  protected
    function CompareKeys(key1: Pointer; {%H-}KeySize1: Cardinal; key2: Pointer;
        {%H-}KeySize2: Cardinal): Boolean; override;
    function Hash32(key: Pointer; KeySize, {%H-}ASeed: Cardinal): Cardinal; override;
    procedure FreeKey(key: Pointer; {%H-}KeySize: Cardinal); override;
    property PAnsiCharAllocator : TVariableBlockHeap read FPAnsiCharAllocator;
  public
    constructor Create(AHashSize: Byte = 16; AUseHashTable: Boolean = False);
    function Add(const key: AnsiString; Value: Pointer = nil): Boolean; overload;
    function Add(const key: AnsiString; Value: IUnknown): Boolean; overload;
    function Find(const key: AnsiString; out Value: Pointer): Boolean; overload;
    function Find(const key: AnsiString; out Value: IUnknown): Boolean; overload;
    function Find(const key: AnsiString): Boolean; overload;
    function Remove(const key: AnsiString): Boolean; {$IFDEF UNICODE} overload; {$ENDIF}
    function Next(var AIterator: THashTrieIterator; out key: AnsiString; out Value:
        Pointer): Boolean; overload;
    function Next(var AIterator: THashTrieIterator; out key: AnsiString; out Value: IUnknown): Boolean; overload;
    destructor Destroy; override;
    procedure Traverse(UserData: Pointer; UserProc: TStrHashTraverseProc); overload;
    procedure Traverse(UserData: Pointer; UserProc: TStrHashTraverseMeth); overload;
    function StringListOfKeyValuePairs: TStrings;
    {$IFDEF UNICODE}
    function Add(const key: String; Value: Pointer = nil): Boolean; overload;
    function Find(const key : String; out Value: Pointer): Boolean; overload;
    function Find(const key: String): Boolean; overload;
    function Remove(const key: String): Boolean; overload;
    function Next(var AIterator: THashTrieIterator; out key: String; out Value: Pointer): Boolean; overload;
    procedure Traverse(UserData: Pointer; UserProc: TUTF16StrHashTraverseProc); overload;
    procedure Traverse(UserData: Pointer; UserProc: TUTF16StrHashTraverseMeth); overload;
    {$ENDIF}
    property CaseInsensitive: Boolean read FCaseInsensitive write FCaseInsensitive;
  end;

implementation

uses
  uSuperFastHash, xxHash;

{ TStringHashTrie }

constructor TStringHashTrie.Create(AHashSize: Byte = 16; AUseHashTable: Boolean = False);
begin
  inherited Create(AHashSize, AUseHashTable);
  FPAnsiCharAllocator := TVariableBlockHeap.Create(_16KB);
end;

destructor TStringHashTrie.Destroy;
begin
  inherited;
  FPAnsiCharAllocator.Free;
end;

function TStringHashTrie.CompareKeys(key1: Pointer; KeySize1: Cardinal; key2:
    Pointer; KeySize2: Cardinal): Boolean;
begin
  if FCaseInsensitive then
    Result := {$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrIComp(PAnsiChar(key1), PAnsiChar(key2)) = 0
  else Result := {$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrComp(PAnsiChar(key1), PAnsiChar(key2)) = 0;
end;

function TStringHashTrie.Hash32(key: Pointer; KeySize, ASeed: Cardinal):
    Cardinal;
begin
  if FCaseInsensitive then
    Result := SuperFastHash(PAnsiChar(key), KeySize, FCaseInsensitive, ASeed)
  else Result := xxHash32Calc(key, KeySize, ASeed);
end;

procedure TStringHashTrie.FreeKey(key: Pointer; KeySize: Cardinal);
begin
  trieAllocators.DeAlloc(key);
end;

function TStringHashTrie.Add(const key: AnsiString; Value: Pointer = nil):
    Boolean;
var
  kvp : TKeyValuePair;
begin
  kvp.KeySize := length(Key);
  kvp.Key := FPAnsiCharAllocator.Alloc(kvp.KeySize + 1);
  move(PAnsiChar(key)^, kvp.Key^, kvp.KeySize + 1);
  kvp.Value := Value;
  Result := inherited Add(kvp);
  if not Result then
    trieAllocators.DeAlloc(kvp.Key);
end;

{$IFDEF UNICODE}
procedure TStringHashTrie.CheckCaseInsensitiveWithUTF16;
const
  SCaseInsensitiveSearchNotSupportedWithUTF16 = 'Case insensitive search not supported with UTF16 functions';
begin
  if FCaseInsensitive then
    raise EStringHashTrie.Create(SCaseInsensitiveSearchNotSupportedWithUTF16);
end;

function TStringHashTrie.Add(const key: String; Value: Pointer = nil): Boolean;
var
  kvp : TKeyValuePair;
  UTF8Str : UTF8String;
begin
  CheckCaseInsensitiveWithUTF16;
  UTF8Str := UTF8String(key);
  kvp.KeySize := length(UTF8Str);
  kvp.Key := FPAnsiCharAllocator.Alloc(kvp.KeySize + 1);
  move(PAnsiChar(UTF8Str)^, kvp.Key^, kvp.KeySize + 1);
  kvp.Value := Value;
  Result := inherited Add(kvp);
  if not Result then
    trieAllocators.Dealloc(kvp.Key);
end;
{$ENDIF}

function TStringHashTrie.Add(const key: AnsiString; Value: IUnknown): Boolean;
begin
  if (Value <> nil) and AutoFreeValue and (AutoFreeValueMode = afmReleaseInterface) then
    Value._AddRef;
  Result := Add(key, Pointer(Value));
end;

function TStringHashTrie.Find(const key: AnsiString; out Value: Pointer):
    Boolean;
var
  kvp : PKeyValuePair;
  AChildIndex : Byte;
  HashTrieNode : PHashTrieNode;
begin
  kvp := inherited InternalFind(PAnsiChar(key), length(key), HashTrieNode, AChildIndex);
  Result := kvp <> nil;
  if Result then
    Value := kvp^.Value
  else Value := nil;
end;

{$IFDEF UNICODE}
function TStringHashTrie.Find(const key: String; out Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
  AChildIndex : Byte;
  HashTrieNode : PHashTrieNode;
  UTF8Str : UTF8String;
begin
  CheckCaseInsensitiveWithUTF16;
  UTF8Str := UTF8String(key);
  kvp := inherited InternalFind(PAnsiChar(UTF8Str), length(UTF8Str), HashTrieNode, AChildIndex);
  Result := kvp <> nil;
  if Result then
    Value := kvp^.Value
  else Value := nil;
end;

function TStringHashTrie.Find(const key: String): Boolean;
var
  Dummy : Pointer;
begin
  Result := Find(key, Dummy);
end;
{$ENDIF}

function TStringHashTrie.Find(const key: AnsiString): Boolean;
var
  Dummy : Pointer;
begin
  Result := Find(key, Dummy);
end;

function TStringHashTrie.Find(const key: AnsiString; out Value: IUnknown): Boolean;
begin
  Result := Find(key, Pointer(Value));
  if Result and (Value <> nil) then
    Value._AddRef;
end;

function TStringHashTrie.Remove(const key: AnsiString): Boolean;
begin
  Result := inherited Remove(PAnsiChar(key), length(key));
end;

function TStringHashTrie.Next(var AIterator: THashTrieIterator; out key:
    AnsiString; out Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
begin
  kvp := inherited Next(AIterator);
  if kvp <> nil then
  begin
    key := {$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrPas(PAnsiChar(kvp^.Key));
    Value := kvp^.Value;
    Result := True;
  end
  else
  begin
    key := '';
    Value := nil;
    Result := False;
  end;
end;

{$IFDEF UNICODE}
function TStringHashTrie.Next(var AIterator: THashTrieIterator; out key:
    String; out Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
begin
  CheckCaseInsensitiveWithUTF16;
  kvp := inherited Next(AIterator);
  if kvp <> nil then
  begin
    key := UTF8String(PAnsiChar(kvp^.Key));
    Value := kvp^.Value;
    Result := True;
  end
  else
  begin
    key := '';
    Value := nil;
    Result := False;
  end;
end;
{$ENDIF}

{$IFDEF UNICODE}
function TStringHashTrie.Remove(const key: String): Boolean;
begin
  CheckCaseInsensitiveWithUTF16;
  Result := inherited Remove(PAnsiChar(UTF8String(key)), length(key));
end;
{$ENDIF}

procedure TStringHashTrie.InitTraversal(out It: THashTrieIterator; out
  ADone: Boolean);
begin
  InitIterator(It);
  ADone := False;
end;

function TStringHashTrie.Next(var AIterator: THashTrieIterator; out key: AnsiString; out Value: IUnknown): Boolean;
begin
  Result := Next(AIterator, key, Pointer(Value));
  if Result and (Value <> nil) then  
    Value._AddRef;
end;

function TStringHashTrie.StringListOfKeyValuePairs: TStrings;
var
  It : THashTrieIterator;
  Key : String;
  Value : Pointer;
begin
  Result := TStringList.Create;
  try
    Result.Capacity := FCount;
    InitIterator(It);
    try
      while Next(It, Key, Value) do
        Result.AddObject(Key, Value);
    finally
      DoneIterator(It);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TStringHashTrie.Traverse(UserData: Pointer; UserProc:
    TStrHashTraverseProc);
var
  It : THashTrieIterator;
  Key : AnsiString;
  Value : Pointer;
  Done : Boolean;
begin
  InitTraversal(It, Done);
  try
    while (not Done) and Next(It, Key, Value) do
      UserProc(UserData, PAnsiChar(Key), TObject(Value), Done);
  finally
    DoneIterator(It);
  end;
end;

procedure TStringHashTrie.Traverse(UserData: Pointer; UserProc:
    TStrHashTraverseMeth);
var
  It : THashTrieIterator;
  Key : AnsiString;
  Value : Pointer;
  Done : Boolean;
begin
  InitTraversal(It, Done);
  try
    while (not Done) and Next(It, Key, Value) do
      UserProc(UserData, PAnsiChar(Key), TObject(Value), Done);
  finally
    DoneIterator(It);
  end;
end;

{$IFDEF UNICODE}
procedure TStringHashTrie.Traverse(UserData: Pointer; UserProc:
    TUTF16StrHashTraverseProc);
var
  It : THashTrieIterator;
  Key : String;
  Value : Pointer;
  Done : Boolean;
begin
  CheckCaseInsensitiveWithUTF16;
  InitTraversal(It, Done);
  try
    while (not Done) and Next(It, Key, Value) do
      UserProc(UserData, PChar(Key), TObject(Value), Done);
  finally
    DoneIterator(It);
  end;
end;

procedure TStringHashTrie.Traverse(UserData: Pointer; UserProc:
    TUTF16StrHashTraverseMeth);
var
  It : THashTrieIterator;
  Key : String;
  Value : Pointer;
  Done : Boolean;
begin
  CheckCaseInsensitiveWithUTF16;
  InitTraversal(It, Done);
  try
    while (not Done) and Next(It, Key, Value) do
      UserProc(UserData, PChar(Key), TObject(Value), Done);
  finally
    DoneIterator(It);
  end;
end;
{$ENDIF}

end.

