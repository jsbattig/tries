unit Hash_Trie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

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
    function Hash32(key : Pointer): Cardinal; virtual; abstract;
    function Hash64(key : Pointer) : Int64; virtual; abstract;
    procedure Add(kvp : PKeyValuePair);
    function Find(key : Pointer; out HashTrieNode : PHashTrieNode; out AChildIndex : Byte) : PKeyValuePair;
    function Remove(key : Pointer) : Boolean;
    function Next(var AIterator : THashTrieIterator) : PKeyValuePair;
    property HashSize : THashSize read FHashSize;
  public
    constructor Create(AHashSize : THashSize);
    procedure InitIterator(out AIterator : THashTrieIterator);
    procedure Pack; override;
    property AllowDuplicates : Boolean read FAllowDuplicates write FAllowDuplicates;
    property AutoFreeValue : Boolean read FAutoFreeValue write FAutoFreeValue;
    property AutoFreeValueMode : TAutoFreeMode read FAutoFreeValueMode write FAutoFreeValueMode;
  end;

implementation

{ THashTrie }

constructor THashTrie.Create(AHashSize: THashSize);
const
  HashSizeToTrieDepth : array[hs16..hs64] of Byte = (4, 8, 16);
begin
  inherited Create(HashSizeToTrieDepth[AHashSize]);
  inherited AllowDuplicates := True;
  FHashSize := AHashSize;
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
        dec(FStats.TotalMemAllocated, sizeof(TKeyValuePairNode));
      end;
    end;
    if PHashTrieNode(ANode)^.Base.ChildrenCount > 0 then
    begin
      FreeMem(PHashTrieNode(ANode)^.Children);
      dec(FStats.TotalMemAllocated, Int64(PHashTrieNode(ANode)^.Base.ChildrenCount) * Int64(sizeof(Pointer)));
    end;
  end;
  inherited FreeTrieNode(ANode, Level);
end;

procedure THashTrie.Add(kvp: PKeyValuePair);
var
  Node : PHashTrieNode;
  Hash : THashRecord;
  kvpNode : PKeyValuePairNode;
  WasNodeBusy : Boolean;
  ChildIndex : Byte;
begin
  CalcHash(Hash, kvp^.Key);
  inherited Add(Hash, PTrieLeafNode(Node), WasNodeBusy);
  if not WasNodeBusy then
  begin
    ChildIndex := Node^.Base.ChildrenCount;
    inc(Node^.Base.ChildrenCount);
    SetChildIndex(PTrieBranchNode(Node), GetBitFieldIndex(Hash, TrieDepth - 1), ChildIndex);
    ReallocMem(Node^.Children, Node^.Base.ChildrenCount * sizeof(Pointer));
    inc(FStats.TotalMemAllocated, sizeof(Pointer));
    PHashTrieNodeArray(Node^.Children)^[ChildIndex] := nil;
  end
  else
  begin
    ChildIndex := GetChildIndex(PTrieBranchNode(Node), GetBitFieldIndex(Hash, TrieDepth - 1));
    inc(FCount);
  end;
  if not FAllowDuplicates then
  begin
    kvpNode := PHashTrieNodeArray(Node^.Children)^[ChildIndex];
    while kvpNode <> nil do
    begin
      if CompareKeys(kvpNode^.KVP.Key, kvp^.Key) then
      begin
        if WasNodeBusy then
          dec(FCount); // Rollback prior addition of FCount
        RaiseDuplicateKeysNotAllowed;
      end;
      kvpNode := kvpNode^.Next;
    end;
  end;
  GetMem(kvpNode, sizeof(TKeyValuePairNode));
  kvpNode^.KVP.Key := kvp^.Key;
  kvpNode^.KVP.Value := kvp^.Value;
  kvpNode^.Next := PHashTrieNodeArray(Node^.Children)^[ChildIndex];
  PHashTrieNodeArray(Node^.Children)^[ChildIndex] := kvpNode;
  inc(FStats.TotalMemAllocated, sizeof(TKeyValuePairNode));
end;

function THashTrie.Find(key: Pointer; out HashTrieNode: PHashTrieNode; out
  AChildIndex: Byte): PKeyValuePair;
var
  Hash : THashRecord;
  ListNode : PKeyValuePairNode;
begin
  CalcHash(Hash, key);
  if InternalFind(Hash, PTrieLeafNode(HashTrieNode), AChildIndex, True) then
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
  Result := False;
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
      dec(FStats.TotalMemAllocated, sizeof(TKeyValuePairNode));
      Result := True;
      exit;
    end;
    ListNode := ListNode^.Next;
  end;
end;

procedure THashTrie.InitIterator(out AIterator: THashTrieIterator);
begin
  inherited InitIterator(AIterator.Base);
  AIterator.ChildNode := nil;
end;

procedure THashTrie.Pack;
label
  ContinueIteration;
var
  It : TTrieIterator;
  i, AChildIndex : byte;
  ATrieDepth : Byte;
  ANode : PHashTrieNode;
begin
  ATrieDepth := TrieDepth;
  inherited InitIterator(It);
  while inherited Next(It) do
  begin
    ANode := PHashTrieNode(It.NodeStack[ATrieDepth - 1]);
    for i := 0 to ChildrenPerBucket - 1 do
    begin
      if GetBusyIndicator(@ANode^.Base, i) then
      begin
         AChildIndex := GetChildIndex(PTrieBranchNode(ANode), i);
         if PHashTrieNodeArray(ANode^.Children)^[AChildIndex] <> nil then
           goto ContinueIteration;
      end;
    end;
    ANode^.Base.Busy := 0; // We mark the record as not busy anymore, will be collected by inherited Pack()
ContinueIteration:
  end;
  inherited Pack;
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
      ABitFieldIndex := GetBitFieldIndex(AIterator.Base.LastResult64, TrieDepth - 1);
      AChildIndex := GetChildIndex(PTrieBranchNode(AIterator.Base.NodeStack[TrieDepth - 1]), ABitFieldIndex);
      AIterator.ChildNode := PHashTrieNodeArray(PHashTrieNode(AIterator.Base.NodeStack[TrieDepth - 1])^.Children)^[AChildIndex];
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
