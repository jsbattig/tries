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
  THashTrieNode = TTrieBranchNode;

  THashTrieNodeArray = array[0..ChildrenPerBucket - 1] of PKeyValuePairNode;
  PHashTrieNodeArray = ^THashTrieNodeArray;

  THashTrieIterator = record
    Base : TTrieIterator;
    ChildNode : PKeyValuePairNode;
  end;

  THashRecord = record
    case THashSize of
      hs16 : (Hash16 : Word);
      hs32 : (Hash32 : Cardinal);
      hs64 : (Hash64 : Int64);
  end;

  TAutoFreeMode = (afmFree, afmFreeMem);

  { THashTrie }

  THashTrie = class(TTrie)
  private
    FHashSize : THashSize;
    FAllowDuplicates : Boolean;
    FAutoFreeValue : Boolean;
    FAutoFreeValueMode : TAutoFreeMode;
    procedure CalcHash(out Hash : THashRecord; key : Pointer);
  protected
    function LeafSize : Cardinal; override;
    procedure InitLeaf(var Leaf); override;
    procedure FreeKey({%H-}key : Pointer); virtual;
    procedure FreeValue({%H-}value : Pointer); virtual;
    function CompareKeys(key1, key2 : Pointer) : Boolean; virtual; abstract;
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte); override;
    function Hash16(key : Pointer) : Word; virtual; abstract;
    function Hash32(key : Pointer) : DWORD; virtual; abstract;
    function Hash64(key : Pointer) : Int64; virtual; abstract;
    procedure Add(kvp : PKeyValuePair);
    function Find(key : Pointer; out HashTrieNode : PHashTrieNode; out AChildIndex : Byte) : PKeyValuePair;
    function Remove(key : Pointer) : Boolean;
    function Next(var AIterator : THashTrieIterator) : PKeyValuePair;
  public
    constructor Create(HashSize : THashSize);
    procedure InitIterator(out AIterator : THashTrieIterator);
    property AllowDuplicates : Boolean read FAllowDuplicates write FAllowDuplicates;
    property AutoFreeValue : Boolean read FAutoFreeValue write FAutoFreeValue;
    property AutoFreeValueMode : TAutoFreeMode read FAutoFreeValueMode write FAutoFreeValueMode;
  end;

implementation

{ THashTrie }

constructor THashTrie.Create(HashSize: THashSize);
const
  HashSizeToTrieDepth : array[hs16..hs64] of Byte = (4, 8, 16);
begin
  inherited Create(HashSizeToTrieDepth[HashSize]);
  inherited AllowDuplicates := True;
  FHashSize := HashSize;
  FAllowDuplicates := True;
end;

procedure THashTrie.CalcHash(out Hash: THashRecord; key: Pointer);
begin
  case FHashSize of
    hs16 : Hash.Hash16 := Hash16(key);
    hs32 : Hash.Hash32 := Hash32(key);
    hs64 : Hash.Hash64 := Hash64(key);
    else RaiseTrieDepthError;
  end;
end;

function THashTrie.LeafSize: Cardinal;
begin
  Result := sizeof(THashTrieNode);
end;

procedure THashTrie.InitLeaf(var Leaf);
begin
  inherited InitLeaf(Leaf);
  THashTrieNode(Leaf).Children := nil;
  THashTrieNode(Leaf).ChildIndex := 0;
end;

procedure THashTrie.FreeKey(key: Pointer);
begin
end;

procedure THashTrie.FreeValue(value: Pointer);
begin
  if FAutoFreeValue then
    if FAutoFreeValueMode = afmFree then
      TObject(value).Free
    else FreeMem(value);
end;

procedure THashTrie.FreeTrieNode(ANode: PTrieBaseNode; Level: Byte);
var
  ListNode, TmpNode : PKeyValuePairNode;
  i : SmallInt;
begin
  inherited FreeTrieNode(ANode, Level);
  if Level = TrieDepth - 1 then
  begin
    for i := 0 to PHashTrieNode(ANode)^.Base.ChildrenCount - 1 do
    begin
      ListNode := PHashTrieNodeArray(PHashTrieNode(ANode)^.Children)^[i];
      while ListNode <> nil do
      begin
        TmpNode := ListNode;
        ListNode := ListNode^.Next;
        FreeKey(TmpNode^.KVP.Key);
        FreeValue(TmpNode^.KVP.Value);
        FreeMem(TmpNode);
      end;
    end;
  end;
end;

procedure THashTrie.Add(kvp: PKeyValuePair);
var
  Node : PHashTrieNode;
  Hash : THashRecord;
  kvpNode : PKeyValuePairNode;
  Added : Boolean;
  ChildIndex : Byte;
begin
  CalcHash(Hash, kvp^.Key);
  Added := inherited Add(Hash, PTrieLeafNode(Node));
  if Added then
  begin
    ChildIndex := Node^.Base.ChildrenCount;
    ReallocMem(Node^.Children, (Node^.Base.ChildrenCount + 1) * sizeof(Pointer));
    PHashTrieNodeArray(Node^.Children)^[ChildIndex] := nil;
    inc(Node^.Base.ChildrenCount);
  end
  else ChildIndex := GetChildIndex(PTrieBranchNode(Node), GetBitFieldIndex(Hash, TrieDepth - 1));
  if not FAllowDuplicates then
  begin
    kvpNode := PHashTrieNodeArray(Node^.Children)^[ChildIndex];
    while kvpNode <> nil do
    begin
      if CompareKeys(kvpNode^.KVP.Key, kvp^.Key) then
        RaiseDuplicateKeysNotAllowed;
      kvpNode := kvpNode^.Next;
    end;
  end;
  GetMem(kvpNode, sizeof(PKeyValuePairNode));
  kvpNode^.KVP.Key := kvp^.Key;
  kvpNode^.KVP.Value := kvp^.Value;
  kvpNode^.Next := PHashTrieNodeArray(Node^.Children)^[ChildIndex];
  PHashTrieNodeArray(Node^.Children)^[ChildIndex] := kvpNode;
end;

function THashTrie.Find(key: Pointer; out HashTrieNode: PHashTrieNode; out
  AChildIndex: Byte): PKeyValuePair;
var
  Hash : THashRecord;
  ListNode : PKeyValuePairNode;
begin
  CalcHash(Hash, key);
  if InternalFind(Hash, PTrieLeafNode(HashTrieNode), AChildIndex) then
  begin
    ListNode := PHashTrieNodeArray(PHashTrieNode(HashTrieNode)^.Children)^[AChildIndex];
    while ListNode <> nil do
    begin
      if CompareKeys(ListNode^.KVP.Key, key) then
      begin
        Result := @ListNode^.KVP;
        exit;
      end;
      ListNode := ListNode^.Next;
    end;
  end;
  Result := nil;
end;

(* We won't call inherited Remove function in purpose. We want to keep our ChildIndex
   field intact and it's ChildIndex reference *)
function THashTrie.Remove(key: Pointer): Boolean;
var
  kvp : PKeyValuePair;
  AChildIndex : Byte;
  PrevNode, ListNode : PKeyValuePairNode;
  HashTrieNode : PHashTrieNode;
begin
  kvp := Find(key, HashTrieNode, AChildIndex);
  if kvp = nil then
    exit;
  PrevNode := nil;
  ListNode := PHashTrieNodeArray(HashTrieNode^.Children)^[AChildIndex];
  while ListNode <> nil do
  begin
    if CompareKeys(ListNode^.KVP.Key, key) then
    begin
      if PrevNode = nil then
        PHashTrieNodeArray(HashTrieNode^.Children)^[AChildIndex] := ListNode^.Next
      else PrevNode^.Next := ListNode^.Next;
      FreeKey(ListNode^.KVP.Key);
      FreeValue(ListNode^.KVP.Value);
      FreeMem(ListNode);
      Result := True;
      exit;
    end;
    ListNode := ListNode^.Next;
  end;
  Result := False;
end;

procedure THashTrie.InitIterator(out AIterator: THashTrieIterator);
begin
  inherited InitIterator(AIterator.Base);
  AIterator.ChildNode := nil;
end;

function THashTrie.Next(var AIterator: THashTrieIterator): PKeyValuePair;
var
  AChildIndex, ABitFieldIndex : Byte;
begin
  if AIterator.ChildNode <> nil then
  begin
    Result := @AIterator.ChildNode^.KVP;
    AIterator.ChildNode := AIterator.ChildNode^.Next;
    exit;
  end;
  repeat
    if inherited Next(AIterator.Base) then
    begin
      case FHashSize of
        hs16 : ABitFieldIndex := GetBitFieldIndex(AIterator.Base.LastResult16, TrieDepth - 1);
        hs32 : ABitFieldIndex := GetBitFieldIndex(AIterator.Base.LastResult32, TrieDepth - 1);
        hs64 : ABitFieldIndex := GetBitFieldIndex(AIterator.Base.LastResult64, TrieDepth - 1);
        else RaiseTrieDepthError;
      end;
      AChildIndex := GetChildIndex(PTrieBranchNode(AIterator.Base.ANodeStack[TrieDepth - 1]), ABitFieldIndex);
      AIterator.ChildNode := PHashTrieNodeArray(PHashTrieNode(AIterator.Base.ANodeStack[TrieDepth - 1])^.Children)^[AChildIndex];
      if AIterator.ChildNode = nil then
        Continue;
      Result := @AIterator.ChildNode^.KVP;
      AIterator.ChildNode := AIterator.ChildNode^.Next;
      exit;
    end
    else
    begin
      Result := nil;
      exit;
    end;
  until False;
end;

end.

