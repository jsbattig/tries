unit StringHashTrie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  SysUtils,
  Trie,
  Hash_Trie
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
    procedure InitTraversal(out It : THashTrieIterator; out ADone : Boolean); inline;
    {$IFDEF UNICODE}
    procedure CheckCaseInsensitiveWithUTF16; inline;
    {$ENDIF}
  protected
    function CompareKeys(key1: Pointer; KeySize1: Cardinal; key2: Pointer;
        KeySize2: Cardinal): Boolean; override;
    function Hash32(key: Pointer; KeySize: Cardinal): Cardinal; override;
    function Hash16(key: Pointer; KeySize: Cardinal): Word; override;
    function Hash64(key: Pointer; KeySize: Cardinal): Int64; override;
    procedure FreeKey({%H-}key : Pointer); override;
  public
    constructor Create(AHashSize : THashSize = hs16);
    function Add(const key: AnsiString; Value: Pointer): Boolean; {$IFDEF UNICODE} overload; {$ENDIF}
    function Find(const key: AnsiString; out Value: Pointer): Boolean; {$IFDEF UNICODE} overload; {$ENDIF}
    function Remove(const key: AnsiString): Boolean; {$IFDEF UNICODE} overload; {$ENDIF}
    function Next(var AIterator: THashTrieIterator; out key: AnsiString; out Value:
        Pointer): Boolean; {$IFDEF UNICODE} overload; {$ENDIF}
    procedure Traverse(UserData: Pointer; UserProc: TStrHashTraverseProc); overload;
    procedure Traverse(UserData: Pointer; UserProc: TStrHashTraverseMeth); overload;
    {$IFDEF UNICODE}
    function Add(const key : String; Value : Pointer): Boolean; overload;
    function Find(const key : String; out Value: Pointer): Boolean; overload;
    function Remove(const key: String): Boolean; overload;
    function Next(var AIterator: THashTrieIterator; out key: String; out Value: Pointer): Boolean; overload;
    procedure Traverse(UserData: Pointer; UserProc: TUTF16StrHashTraverseProc); overload;
    procedure Traverse(UserData: Pointer; UserProc: TUTF16StrHashTraverseMeth); overload;
    {$ENDIF}
    property CaseInsensitive: Boolean read FCaseInsensitive write FCaseInsensitive;
  end;

implementation

uses
  uSuperFastHash;

{ TStringHashTrie }

constructor TStringHashTrie.Create(AHashSize: THashSize);
begin
  inherited Create(AHashSize);
end;

function TStringHashTrie.CompareKeys(key1: Pointer; KeySize1: Cardinal; key2:
    Pointer; KeySize2: Cardinal): Boolean;
begin
  if FCaseInsensitive then
    Result := {$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrIComp(PAnsiChar(key1), PAnsiChar(key2)) = 0
  else Result := {$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrComp(PAnsiChar(key1), PAnsiChar(key2)) = 0;
end;

function TStringHashTrie.Hash32(key: Pointer; KeySize: Cardinal): Cardinal;
begin
  Result := SuperFastHash(PAnsiChar(key), KeySize, FCaseInsensitive);
end;

function TStringHashTrie.Hash16(key: Pointer; KeySize: Cardinal): Word;
var
  AHash32 : Cardinal;
begin
  AHash32 := Hash32(key, KeySize);
  Result := AHash32;
  AHash32 := AHash32 shr 16;
  inc(Result, Word(AHash32));
end;

function TStringHashTrie.Hash64(key: Pointer; KeySize: Cardinal): Int64;
var
  AHash32_1, AHash32_2 : Cardinal;
begin
  AHash32_1 := SuperFastHash(PAnsiChar(key), KeySize div 2, FCaseInsensitive);
  AHash32_2 := SuperFastHash(@PAnsiChar(key)[KeySize div 2], KeySize - (KeySize div 2), FCaseInsensitive);
  Result := Int64(AHash32_1) + Int64(AHash32_2) shl 32;
end;

procedure TStringHashTrie.FreeKey(key: Pointer);
begin
  dec(FStats.TotalMemAllocated, Int64({$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrLen(PAnsiChar(key))) + 1);
  {$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrDispose(key);
end;

function TStringHashTrie.Add(const key: AnsiString; Value: Pointer): Boolean;
var
  kvp : TKeyValuePair;
begin
  kvp.Key := {$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrNew(PAnsiChar(key));
  kvp.Value := Value;
  kvp.KeySize := length(Key);
  Result := inherited Add(kvp);
  inc(FStats.TotalMemAllocated, Int64(length(key)) + 1);
end;

{$IFDEF UNICODE}
procedure TStringHashTrie.CheckCaseInsensitiveWithUTF16;
const
  SCaseInsensitiveSearchNotSupportedWithUTF16 = 'Case insensitive search not supported with UTF16 functions';
begin
  if FCaseInsensitive then
    raise EStringHashTrie.Create(SCaseInsensitiveSearchNotSupportedWithUTF16);
end;

function TStringHashTrie.Add(const key : String; Value : Pointer): Boolean;
var
  kvp : TKeyValuePair;
  UTF8Str : UTF8String;
begin
  CheckCaseInsensitiveWithUTF16;
  UTF8Str := UTF8String(key);
  kvp.Key := AnsiStrings.StrNew(PAnsiChar(UTF8Str));
  kvp.Value := Value;
  kvp.KeySize := length(UTF8Str);
  Result := inherited Add(kvp);
  inc(FStats.TotalMemAllocated, Int64(length(key)) + 1);
end;
{$ENDIF}

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
{$ENDIF}

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

procedure TStringHashTrie.Traverse(UserData: Pointer; UserProc:
    TStrHashTraverseProc);
var
  It : THashTrieIterator;
  Key : AnsiString;
  Value : Pointer;
  Done : Boolean;
begin
  InitTraversal(It, Done);
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, PAnsiChar(Key), TObject(Value), Done);
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
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, PAnsiChar(Key), TObject(Value), Done);
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
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, PChar(Key), TObject(Value), Done);
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
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, PChar(Key), TObject(Value), Done);
end;
{$ENDIF}

end.

