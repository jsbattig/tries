unit StringHashTrie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  Hash_Trie {$IFDEF FPC}, Strings {$ELSE} ,AnsiStrings {$ENDIF};

type
  { TStringHashTrie }
  TStringHashTrie = class(THashTrie)
  protected
    function CompareKeys(key1, key2 : Pointer) : Boolean; override;
    function Hash32(key : Pointer): Cardinal; override;
    function Hash16(key : Pointer) : Word; override;
    function Hash64(key : Pointer) : Int64; override;
    procedure FreeKey({%H-}key : Pointer); override;
  public
    constructor Create(AHashSize : THashSize = hs32);
    procedure Add(const key: AnsiString; Value: Pointer);
    function Find(const key: AnsiString; out Value: Pointer): Boolean;
    function Remove(const key: AnsiString): Boolean;
    function Next(var AIterator: THashTrieIterator; out key: AnsiString; out Value:
        Pointer): Boolean;
  end;

implementation

uses
  uSuperFastHash;

{ TStringHashTrie }

constructor TStringHashTrie.Create(AHashSize: THashSize);
begin
  inherited Create(AHashSize);
end;

function TStringHashTrie.CompareKeys(key1, key2: Pointer): Boolean;
begin
  Result := StrComp(PAnsiChar(key1), PAnsiChar(key2)) = 0;
end;

function TStringHashTrie.Hash32(key : Pointer): Cardinal;
begin
  Result := SuperFastHash(PAnsiChar(key), strlen(PAnsiChar(key)));
end;

function TStringHashTrie.Hash16(key: Pointer): Word;
var
  AHash32 : Cardinal;
begin
  AHash32 := Hash32(key);
  Result := AHash32;
  AHash32 := AHash32 shr 16;
  inc(Result, Word(AHash32));
end;

function TStringHashTrie.Hash64(key: Pointer): Int64;
var
  AHash32_1, AHash32_2 : Cardinal;
  Len : Integer;
begin
  Len := strlen(PAnsiChar(key));
  AHash32_1 := SuperFastHash(PAnsiChar(key), Len div 2);
  AHash32_2 := SuperFastHash(@PAnsiChar(key)[Len div 2], Len - (Len div 2));
  Result := Int64(AHash32_1) + Int64(AHash32_2) shl 32;
end;

procedure TStringHashTrie.FreeKey(key: Pointer);
begin
  StrDispose(key);
end;

procedure TStringHashTrie.Add(const key: AnsiString; Value: Pointer);
var
  kvp : TKeyValuePair;
begin
  kvp.Key := strnew(PAnsiChar(key));
  kvp.Value := Value;
  inherited Add(@kvp);
end;

function TStringHashTrie.Find(const key: AnsiString; out Value: Pointer):
    Boolean;
var
  kvp : PKeyValuePair;
  AChildIndex : Byte;
  HashTrieNode : PHashTrieNode;
begin
  kvp := inherited Find(PAnsiChar(key), HashTrieNode, AChildIndex);
  Result := kvp <> nil;
  if Result then
    Value := kvp^.Value
  else Value := nil;
end;

function TStringHashTrie.Remove(const key: AnsiString): Boolean;
begin
  Result := inherited Remove(PAnsiChar(key));
end;

function TStringHashTrie.Next(var AIterator: THashTrieIterator; out key:
    AnsiString; out Value: Pointer): Boolean;
var
  kvp : PKeyValuePair;
begin
  kvp := inherited Next(AIterator);
  if kvp <> nil then
  begin
    key := StrPas(PAnsiChar(kvp^.Key));
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

