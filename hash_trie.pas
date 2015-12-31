unit Hash_Trie;

{$mode objfpc}{$H+}

interface

uses
  Trie;

type
  THashSize = (hs16, hs32, hs64);
  PKeyValuePair = ^TKeyValuePair;
  TKeyValuePair = record
    Key : Pointer;
    Value : Pointer;
  end;
  PKeyValuePairNode = ^TKeyValuePairNode;
  TKeyValuePairNode = record
    KVP : TKeyValuePair;
    Next : PKeyValuePairNode;
  end;

  PHashTrieNode = ^THashTrieNode;
  THashTrieNode = record
    Base : TTrieLeafNode;
  end;

  { THashTrie }

  THashTrie = class(TTrie)
  private
    FHashSize : THashSize;
  protected
    function LeafSize : Cardinal; override;
    procedure InitLeaf(var Leaf); override;
  public
    constructor Create(HashSize : THashSize);
    procedure Add(kvp : PKeyValuePair);
    function Find(key : Pointer) : PKeyValuePair;
    procedure Remove(key : Pointer);
    function Next(var AIterator : TTrieIterator) : PKeyValuePair;
  end;

implementation

uses
  uSuperFastHash;

{ THashTrie }

function THashTrie.LeafSize: Cardinal;
begin
  Result := sizeof(THashTrieNode);
end;

procedure THashTrie.InitLeaf(var Leaf);
begin
  inherited InitLeaf(Leaf);

end;

constructor THashTrie.Create(HashSize: THashSize);
const
  HashSizeToTrieDepth : array[hs16..hs64] of Byte = (4, 8, 16);
begin
  inherited Create(HashSizeToTrieDepth[HashSize]);
  AllowDuplicates := True;
  FHashSize := HashSize;
end;

procedure THashTrie.Add(kvp: PKeyValuePair);
begin

end;

function THashTrie.Find(key: Pointer): PKeyValuePair;
begin

end;

procedure THashTrie.Remove(key: Pointer);
begin

end;

function THashTrie.Next(var AIterator: TTrieIterator): PKeyValuePair;
begin

end;

end.

