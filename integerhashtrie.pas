unit IntegerHashTrie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  Trie, Hash_Trie;

type
  TIntHashTraverseProc = procedure(UserData: Pointer; Value: integer;
    Data: TObject; var Done: Boolean);
  TIntHashTraverseMeth = procedure(UserData: Pointer; Value: integer;
    Data: TObject; var Done: Boolean) of object;
  TWordHashTraverseProc = procedure(UserData: Pointer; Value: Word;
    Data: TObject; var Done: Boolean);
  TWordHashTraverseMeth = procedure(UserData: Pointer; Value: Word;
    Data: TObject; var Done: Boolean) of object;
  TInt64HashTraverseProc = procedure(UserData: Pointer; Value: Int64;
    Data: TObject; var Done: Boolean);
  TInt64HashTraverseMeth = procedure(UserData: Pointer; Value: Int64;
    Data: TObject; var Done: Boolean) of object;
  EIntegerHashTrie = class(ETrie);
  { TIntegerHashTrie }
  TIntegerHashTrie = class(THashTrie)
  private
    procedure CheckHashSize(ASize: THashSize); inline;
    procedure CheckKey(AKey: Cardinal); overload; inline;
    procedure CheckKey(AKey: Word); overload; inline;
    procedure CheckKey(AKey: Int64); overload; inline;
    function InternalAdd(key: Pointer; KeySize: Cardinal; Value: Pointer): Boolean;
    function InternalFind(key: Pointer; KeySize: Cardinal; out Value: Pointer):
        Boolean;
  protected
    function CompareKeys(key1: Pointer; KeySize1: Cardinal; key2: Pointer;
        KeySize2: Cardinal): Boolean; override;
    function Hash32(key: Pointer; {%H-}KeySize: Cardinal): Cardinal; override;
    function Hash16(key: Pointer; {%H-}KeySize: Cardinal): Word; override;
    function Hash64(key: Pointer; {%H-}KeySize: Cardinal): Int64; override;
    procedure FreeKey(key : Pointer); override;
  public
    constructor Create(AHashSize : THashSize = hs32);
    function Add(key : Cardinal; Value : Pointer): Boolean; overload;
    function Add(key : Word; Value : Pointer): Boolean; overload;
    function Add(key : Int64; Value : Pointer): Boolean; overload;
    function Find(key : Cardinal; out Value : Pointer) : Boolean; overload;
    function Find(key : Word; out Value : Pointer) : Boolean; overload;
    function Find(key : Int64; out Value : Pointer) : Boolean; overload;
    function Remove(key : Cardinal) : Boolean; overload;
    function Remove(key : Word) : Boolean; overload;
    function Remove(key : Int64) : Boolean; overload;
    function Next(var AIterator : THashTrieIterator; out key : Cardinal; out Value : Pointer) : Boolean; overload;
    function Next(var AIterator : THashTrieIterator; out key : Word; out Value : Pointer) : Boolean; overload;
    function Next(var AIterator : THashTrieIterator; out key : Int64; out Value : Pointer) : Boolean; overload;
    procedure Traverse(UserData: Pointer; UserProc: TIntHashTraverseProc); overload;
    procedure Traverse(UserData: Pointer; UserProc: TIntHashTraverseMeth); overload;
    procedure Traverse(UserData: Pointer; UserProc: TWordHashTraverseProc); overload;
    procedure Traverse(UserData: Pointer; UserProc: TWordHashTraverseMeth); overload;
    procedure Traverse(UserData: Pointer; UserProc: TInt64HashTraverseProc); overload;
    procedure Traverse(UserData: Pointer; UserProc: TInt64HashTraverseMeth); overload;
  end;

implementation

{ TIntegerHashTrie }

constructor TIntegerHashTrie.Create(AHashSize: THashSize);
begin
  inherited Create(AHashSize);
end;

function TIntegerHashTrie.CompareKeys(key1: Pointer; KeySize1: Cardinal; key2:
    Pointer; KeySize2: Cardinal): Boolean;
begin
  {$IFNDEF FPC}
  Result := False;
  {$ENDIF}
  if KeySize1 <> KeySize2 then
  begin
    Result := False;
    exit;
  end;
  case KeySize1 of
    sizeof(Word) : Result := {%H-}Word(key1) = {%H-}Word(key2);
    sizeof(Cardinal) : Result := {%H-}Cardinal(key1) = {%H-}Cardinal(key2);
    sizeof(Int64) : if sizeof(Pointer) <> sizeof(Int64) then
      Result := PInt64(key1)^ = PInt64(key2)^
    else {%H-}Result := key1 = key2;
    else RaiseTrieDepthError;
  end;
end;

function TIntegerHashTrie.Hash32(key: Pointer; KeySize: Cardinal): Cardinal;
begin
  Result := {%H-}Cardinal(key);
end;

function TIntegerHashTrie.Hash16(key: Pointer; KeySize: Cardinal): Word;
begin
  Result := {%H-}Word(key);
end;

function TIntegerHashTrie.Hash64(key: Pointer; KeySize: Cardinal): Int64;
begin
  if (HashSize = hs64) and (sizeof(Pointer) <> sizeof(Int64)) then
    Result := PInt64(key)^
  else Result := {%H-}Int64(key);
end;

procedure TIntegerHashTrie.FreeKey(key: Pointer);
begin
  if (HashSize = hs64) and (sizeof(Pointer) <> sizeof(Int64)) then
    Dispose(PInt64(key));
end;

function TIntegerHashTrie.Add(key : Cardinal; Value : Pointer): Boolean;
begin
  CheckHashSize(hs32);
  CheckKey(key);
  Result := InternalAdd({%H-}Pointer(key), sizeof(key), Value);
end;

function TIntegerHashTrie.Add(key : Word; Value : Pointer): Boolean;
begin
  CheckHashSize(hs16);
  CheckKey(key);
  Result := InternalAdd({%H-}Pointer(key), sizeof(key), Value);
end;

function TIntegerHashTrie.Add(key : Int64; Value : Pointer): Boolean;
var
  keyInt64 : PInt64;
begin
  CheckHashSize(hs64);
  CheckKey(key);
  if (HashSize = hs64) and (sizeof(Pointer) <> sizeof(Int64)) then
  begin
    New(keyInt64);
    keyInt64^ := key;
    Result := InternalAdd(keyInt64, sizeof(key), Value);
  end
  else Result := InternalAdd({%H-}Pointer(key), sizeof(key), Value);
end;

procedure TIntegerHashTrie.CheckHashSize(ASize: THashSize);
const
  SHashSizeMismatch = 'HashSize mismatch';
begin
  if ASize <> HashSize then
    raise EIntegerHashTrie.Create(SHashSizeMismatch);
end;

procedure TIntegerHashTrie.CheckKey(AKey: Cardinal);
const
  SKeyCantBeZero = 'Key can''t be zero';
begin
  if AKey = 0 then
    raise EIntegerHashTrie.Create(SKeyCantBeZero);
end;

procedure TIntegerHashTrie.CheckKey(AKey: Word);
const
  SKeyCantBeZero = 'Key can''t be zero';
begin
  if AKey = 0 then
    raise EIntegerHashTrie.Create(SKeyCantBeZero);
end;

procedure TIntegerHashTrie.CheckKey(AKey: Int64);
const
  SKeyCantBeZero = 'Key can''t be zero';
begin
  if AKey = 0 then
    raise EIntegerHashTrie.Create(SKeyCantBeZero);
end;

function TIntegerHashTrie.Find(key: Cardinal; out Value: Pointer): Boolean;
begin
  CheckHashSize(hs32);
  CheckKey(key);
  Result := InternalFind({%H-}Pointer(key), sizeof(key), Value);
end;

function TIntegerHashTrie.Find(key: Word; out Value: Pointer): Boolean;
begin
  CheckHashSize(hs16);
  CheckKey(key);
  Result := InternalFind({%H-}Pointer(key), sizeof(key), Value);
end;

function TIntegerHashTrie.Find(key: Int64; out Value: Pointer): Boolean;
begin
  CheckHashSize(hs64);
  CheckKey(key);
  if (HashSize = hs64) and (sizeof(Pointer) <> sizeof(Int64)) then
    Result := InternalFind(@key, sizeof(key), Value)
  else Result := InternalFind({%H-}Pointer(key), sizeof(key), Value);
end;

function TIntegerHashTrie.InternalAdd(key: Pointer; KeySize: Cardinal; Value:
    Pointer): Boolean;
var
  kvp : TKeyValuePair;
begin
  kvp.Key := key;
  kvp.Value := Value;
  kvp.KeySize := KeySize;
  Result := inherited Add(kvp);
end;

function TIntegerHashTrie.InternalFind(key: Pointer; KeySize: Cardinal; out
    Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
  AChildIndex : Byte;
  HashTrieNode : PHashTrieNode;
begin
  kvp := inherited InternalFind(key, KeySize, HashTrieNode, AChildIndex);
  Result := kvp <> nil;
  if Result then
    Value := kvp^.Value
  else Value := nil;
end;

function TIntegerHashTrie.Remove(key: Cardinal): Boolean;
begin
  CheckHashSize(hs32);
  CheckKey(key);
  Result := inherited Remove({%H-}Pointer(key), sizeof(key));
end;

function TIntegerHashTrie.Remove(key: Word): Boolean;
begin
  CheckHashSize(hs16);
  CheckKey(key);
  Result := inherited Remove({%H-}Pointer(key), sizeof(key));
end;

function TIntegerHashTrie.Remove(key: Int64): Boolean;
begin
  CheckHashSize(hs64);
  CheckKey(key);
  if (HashSize = hs64) and (sizeof(Pointer) <> sizeof(Int64)) then
    Result := inherited Remove(@key, sizeof(key))
  else Result := inherited Remove({%H-}Pointer(key), sizeof(key));
end;

function TIntegerHashTrie.Next(var AIterator: THashTrieIterator; out
  key: Cardinal; out Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
begin
  CheckHashSize(hs32);
  kvp := inherited Next(AIterator);
  if kvp <> nil then
  begin
    key := {%H-}Cardinal(kvp^.Key);
    Value := kvp^.Value;
    Result := True;
  end
  else
  begin
    key := 0;
    Value := nil;
    Result := False;
  end;
end;

function TIntegerHashTrie.Next(var AIterator: THashTrieIterator; out key: Word;
  out Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
begin
  CheckHashSize(hs16);
  kvp := inherited Next(AIterator);
  if kvp <> nil then
  begin
    key := {%H-}Word(kvp^.Key);
    Value := kvp^.Value;
    Result := True;
  end
  else
  begin
    key := 0;
    Value := nil;
    Result := False;
  end;
end;

function TIntegerHashTrie.Next(var AIterator: THashTrieIterator; out
  key: Int64; out Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
begin
  CheckHashSize(hs64);
  kvp := inherited Next(AIterator);
  if kvp <> nil then
  begin
    if (HashSize = hs64) and (sizeof(Pointer) <> sizeof(Int64)) then
      key := PInt64(kvp^.Key)^
    else key := {%H-}Int64(kvp^.Key);
    Value := kvp^.Value;
    Result := True;
  end
  else
  begin
    key := 0;
    Value := nil;
    Result := False;
  end;
end;

procedure TIntegerHashTrie.Traverse(UserData: Pointer; UserProc:
    TIntHashTraverseMeth);
var
  It : THashTrieIterator;
  Key : Cardinal;
  Value : Pointer;
  Done : Boolean;
begin
  InitIterator(It);
  Done := False;
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, Key, TObject(Value), Done);
end;

procedure TIntegerHashTrie.Traverse(UserData: Pointer;
  UserProc: TWordHashTraverseProc);
var
  It : THashTrieIterator;
  Key : Word;
  Value : Pointer;
  Done : Boolean;
begin
  InitIterator(It);
  Done := False;
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, Key, TObject(Value), Done);
end;

procedure TIntegerHashTrie.Traverse(UserData: Pointer;
  UserProc: TWordHashTraverseMeth);
var
  It : THashTrieIterator;
  Key : Word;
  Value : Pointer;
  Done : Boolean;
begin
  InitIterator(It);
  Done := False;
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, Key, TObject(Value), Done);
end;

procedure TIntegerHashTrie.Traverse(UserData: Pointer;
  UserProc: TInt64HashTraverseProc);
var
  It : THashTrieIterator;
  Key : Int64;
  Value : Pointer;
  Done : Boolean;
begin
  InitIterator(It);
  Done := False;
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, Key, TObject(Value), Done);
end;

procedure TIntegerHashTrie.Traverse(UserData: Pointer;
  UserProc: TInt64HashTraverseMeth);
var
  It : THashTrieIterator;
  Key : Int64;
  Value : Pointer;
  Done : Boolean;
begin
  InitIterator(It);
  Done := False;
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, Key, TObject(Value), Done);
end;

procedure TIntegerHashTrie.Traverse(UserData: Pointer; UserProc:
    TIntHashTraverseProc);
var
  It : THashTrieIterator;
  Key : Cardinal;
  Value : Pointer;
  Done : Boolean;
begin
  InitIterator(It);
  Done := False;
  while (not Done) and Next(It, Key, Value) do
    UserProc(UserData, Key, TObject(Value), Done);
end;

end.

