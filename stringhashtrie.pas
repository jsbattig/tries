unit StringHashTrie;

{$mode objfpc}{$H+}

interface

uses
  Hash_Trie, Strings;

type
  { TStringHashTrie }
  TStringHashTrie = class(THashTrie)
  protected
    function CompareKeys(key1, key2 : Pointer) : Boolean; override;
    function Hash32(key : Pointer) : DWORD; override;
    function Hash16(key : Pointer) : Word; override;
    function Hash64(key : Pointer) : Int64; override;
    procedure FreeKey({%H-}key : Pointer); override;
  public
    constructor Create(HashSize : THashSize = hs32);
    procedure Add(const key : String; Value : Pointer);
    function Find(const key : String; out Value : Pointer) : Boolean;
    function Remove(const key : String) : Boolean;
    function Next(var AIterator : THashTrieIterator; out key : String; out Value : Pointer) : Boolean;
  end;

implementation

uses
  uSuperFastHash;

{ TStringHashTrie }

constructor TStringHashTrie.Create(HashSize: THashSize);
begin
  inherited Create(HashSize);
end;

function TStringHashTrie.CompareKeys(key1, key2: Pointer): Boolean;
begin
  Result := StrComp(PChar(key1), PChar(key2)) = 0;
end;

function TStringHashTrie.Hash32(key: Pointer): DWORD;
begin
  Result := SuperFastHash(PAnsiChar(key), strlen(PChar(key)));
end;

function TStringHashTrie.Hash16(key: Pointer): Word;
var
  AHash32 : DWORD;
begin
  AHash32 := Hash32(key);
  Result := AHash32;
  AHash32 := AHash32 shr 16;
  inc(Result, Word(AHash32));
end;

function TStringHashTrie.Hash64(key: Pointer): Int64;
var
  AHash32_1, AHash32_2 : DWORD;
  Len : Integer;
begin
  Len := strlen(PChar(key));
  AHash32_1 := SuperFastHash(PAnsiChar(key), Len div 2);
  AHash32_2 := SuperFastHash(@PAnsiChar(key)[Len div 2], Len - (Len div 2));
  Result := Int64(AHash32_1) + Int64(AHash32_2) shl 32;
end;

procedure TStringHashTrie.FreeKey(key: Pointer);
begin
  FreeMem(key);
end;

procedure TStringHashTrie.Add(const key: String; Value: Pointer);
var
  kvp : TKeyValuePair;
begin
  kvp.Key := strnew(PChar(key));
  kvp.Value := Value;
  inherited Add(@kvp);
end;

function TStringHashTrie.Find(const key: String; out Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
  AChildIndex : Byte;
  HashTrieNode : PHashTrieNode;
begin
  kvp := inherited Find(PChar(key), HashTrieNode, AChildIndex);
  Result := kvp <> nil;
  if Result then
    Value := kvp^.Value
  else Value := nil;
end;

function TStringHashTrie.Remove(const key: String): Boolean;
begin
  Result := inherited Remove(PChar(key));
end;

function TStringHashTrie.Next(var AIterator: THashTrieIterator; out
  key: String; out Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
begin
  kvp := inherited Next(AIterator);
  if kvp <> nil then
  begin
    key := StrPas(kvp^.Key);
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

end.

