unit Hash_Trie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  Trie, hash_table, trieAllocators, HashedContainer;

type
  PKeyValuePair = ^TKeyValuePair;
  TKeyValuePair = record
    Key : Pointer;
    KeySize : Cardinal;
    Value : Pointer;
    Hash : Word;
  end;

  PKeyValuePairNode = ^TKeyValuePairNode;
  PPKeyValuePairNode = ^PKeyValuePairNode;
  TKeyValuePairNode = record
    KVP : TKeyValuePair;
    Left : PKeyValuePairNode;
    Next : PKeyValuePairNode;
    Right : PKeyValuePairNode;
  end;

  TIteratorMovement = (imLeft, imNext, imRight, imUp);
  PKeyValuePairBacktrackNode = ^TKeyValuePairBacktrackNode;
  TKeyValuePairBacktrackNode = record
    Node : PKeyValuePairNode;
    NextMove : TIteratorMovement;
    Next : PKeyValuePairBacktrackNode;
  end;

  PHashTrieNode = ^THashTrieNode;
  THashTrieNode = TTrieBranchNode;

  THashTrieNodeArray = array[0..ChildrenPerBucket - 1] of PKeyValuePairNode;
  PHashTrieNodeArray = ^THashTrieNodeArray;

  THashTrieIterator = record
    BackTrack : PKeyValuePairBacktrackNode;
    case Integer of
      0 : (Base : THashedContainerIterator);
      1 : (BaseTrieIterator : TTrieIterator);
      2 : (BaseHashTableIterator : THashTableIterator);
  end;

  THashRecord = record
    case Integer of
      0 : (Hash16 : Word);
      1 : (Hash32 : Cardinal);
      2 : (Hash64 : Int64);
      3 : (Hash32_1, Hash32_2 : Cardinal);
      4 : (Hash16_1, Hash16_2, Hash16_3, Hash16_4 : Word);
  end;

  TAutoFreeMode = (afmFree, afmFreeMem);
  TDuplicatesMode = (dmNotAllow, dmAllowed, dmReplaceExisting);

  { THashTrie }

  EHashTrie = class(EHashedContainer);
  THashTrie = class(TBaseHashedContainer)
  private
    FContainer : THashedContainer;
    FAutoFreeValue : Boolean;
    FAutoFreeValueMode : TAutoFreeMode;
    FKeyValuePairNodeAllocator : TFixedBlockHeap;
    FKeyValuePairBacktrackNodeAllocator : TFixedBlockHeap;
    FTrieDepth: Byte;
    function AddOrReplaceNode(var Root: PKeyValuePairNode; const kvp:
        TKeyValuePair): Boolean;
    function HashSizeToTrieDepth(AHashSize: Byte): Byte; inline;
    procedure NewBacktrackNode(var AIterator: THashTrieIterator; Node:
        PKeyValuePairNode; NextMove: TIteratorMovement);
    function NewKVPNode(const kvp: TKeyValuePair): PKeyValuePairNode;
    procedure NextLeafTreeNode(var AIterator: THashTrieIterator; AFreeNodes:
        Boolean = False);
  protected
    procedure InitLeaf(var Leaf); inline;
    procedure FreeKey(key: Pointer; KeySize: Cardinal); virtual;
    procedure FreeValue({%H-}value : Pointer); virtual;
    function CompareKeys(key1: Pointer; KeySize1: Cardinal; key2: Pointer;
        KeySize2: Cardinal): Boolean; virtual; abstract;
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
    procedure CalcHash(out Hash: THashRecord; key: Pointer; KeySize,
        AOriginalKeySize: Cardinal; ASeed: _Int64; AHashSize: Byte); virtual;
    function Hash16(key: Pointer; KeySize, ASeed: Cardinal): Word; virtual;
    function Hash32(key: Pointer; KeySize, ASeed: Cardinal): Cardinal; virtual;
    function Hash64(key: Pointer; KeySize: Cardinal; ASeed: _Int64): Int64; virtual;
    function Add(var kvp: TKeyValuePair): Boolean;
    function InternalFind(key: Pointer; KeySize: Cardinal; out HashTrieNode:
                          PHashTrieNode; out AChildIndex: Byte): PKeyValuePair;
    function Remove(key: Pointer; KeySize: Cardinal): Boolean;
    function Next(var AIterator : THashTrieIterator) : PKeyValuePair;
    property TrieDepth: Byte read FTrieDepth;
  public
    constructor Create(AHashSize: Byte);
    destructor Destroy; override;
    procedure Clear;
    procedure InitIterator(out AIterator : THashTrieIterator);
    procedure DoneIterator(var AIterator : THashTrieIterator);
    procedure Pack;
    property AutoFreeValue : Boolean read FAutoFreeValue write FAutoFreeValue;
    property AutoFreeValueMode : TAutoFreeMode read FAutoFreeValueMode write FAutoFreeValueMode;
  end;

implementation

uses
  SysUtils, uSuperFastHash;

const
  TRIE_HASH_SEED = $FEA0945B;
  TREE_HASH_SEED = $AFC456EB;

{ THashTrie }

constructor THashTrie.Create(AHashSize: Byte);
begin
  FTrieDepth := HashSizeToTrieDepth(AHashSize);
  inherited Create(AHashSize, sizeof(THashTrieNode));
  if AHashSize <= 20 then
    FContainer := THashTable.Create(AHashSize, sizeof(THashTrieNode))
  else FContainer := TTrie.Create(FTrieDepth, sizeof(THashTrieNode));
  FContainer.OnFreeTrieNode := {$IFDEF FPC}@{$ENDIF}FreeTrieNode;
  FContainer.OnInitLeaf := {$IFDEF FPC}@{$ENDIF}InitLeaf;
  FKeyValuePairNodeAllocator := TFixedBlockHeap.Create(sizeof(TKeyValuePairNode), _64KB div sizeof(TKeyValuePairNode));
  FKeyValuePairBacktrackNodeAllocator := TFixedBlockHeap.Create(sizeof(TKeyValuePairBacktrackNode), _64KB div sizeof(TKeyValuePairBacktrackNode));
end;

destructor THashTrie.Destroy;
begin
  inherited;
  FContainer.Free;
  FKeyValuePairBacktrackNodeAllocator.Free;
  FKeyValuePairNodeAllocator.Free;
end;

function THashTrie.Hash16(key: Pointer; KeySize, ASeed: Cardinal): Word;
var
  AHash32 : Cardinal;
begin
  AHash32 := Hash32(key, KeySize, ASeed);
  Result := AHash32;
  AHash32 := AHash32 shr 16;
  inc(Result, Word(AHash32));
end;

function THashTrie.Hash32(key: Pointer; KeySize, ASeed: Cardinal): Cardinal;
begin
  Result := SuperFastHash(key, KeySize, False);
end;

function THashTrie.Hash64(key: Pointer; KeySize: Cardinal; ASeed: _Int64):
    Int64;
var
  AHash32_1, AHash32_2 : Cardinal;
begin
  AHash32_1 := Hash32(PAnsiChar(key), KeySize div 2, ASeed);
  AHash32_2 := Hash32(@PAnsiChar(key)[KeySize div 2], KeySize - (KeySize div 2), ASeed);
  Result := Int64(AHash32_1) + Int64(AHash32_2) shl 32;
end;

procedure THashTrie.CalcHash(out Hash: THashRecord; key: Pointer; KeySize,
    AOriginalKeySize: Cardinal; ASeed: _Int64; AHashSize: Byte);
begin
  case AHashSize of
    1..16  : Hash.Hash16 := Hash16(key, KeySize, ASeed);
    17..32 : Hash.Hash32 := Hash32(key, KeySize, ASeed);
    33..64 : Hash.Hash64 := Hash64(key, KeySize, ASeed);
    else RaiseHashSizeError;
  end;
end;

procedure THashTrie.InitLeaf(var Leaf);
begin
  THashTrieNode(Leaf).Children := nil;
  THashTrieNode(Leaf).ChildIndex := 0;
end;

procedure THashTrie.FreeKey(key: Pointer; KeySize: Cardinal);
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
  ListNode : PKeyValuePairNode;
  i : SmallInt;
  AIterator : THashTrieIterator;
begin
  if Level = TrieDepth - 1 then
  begin
    for i := 0 to PHashTrieNode(ANode)^.Base.ChildrenCount - 1 do
    begin
      ListNode := PHashTrieNodeArray(PHashTrieNode(ANode)^.Children)^[i];
      if ListNode  = nil then
        continue;
      InitIterator(AIterator);
      NewBacktrackNode(AIterator, ListNode, imLeft);
      repeat
        NextLeafTreeNode(AIterator, True);
      until AIterator.BackTrack = nil;
    end;
    if PHashTrieNode(ANode)^.Base.ChildrenCount > 0 then
      FreeMem(PHashTrieNode(ANode)^.Children);
  end;
end;

function THashTrie.Add(var kvp: TKeyValuePair): Boolean;
var
  Node : PHashTrieNode;
  Hash, TreeHash : THashRecord;
  WasNodeBusy : Boolean;
  ChildIndex : Byte;
begin
  if HashSize * 2 > 64 then
  begin
    CalcHash(Hash, kvp.Key, kvp.KeySize, kvp.KeySize, TRIE_HASH_SEED, HashSize);
    CalcHash(TreeHash, kvp.Key, kvp.KeySize div 2, kvp.KeySize, TREE_HASH_SEED, HashSize);
    kvp.Hash := TreeHash.Hash16;
  end
  else
  begin
    CalcHash(Hash, kvp.Key, kvp.KeySize, kvp.KeySize, TRIE_HASH_SEED, 64);
    kvp.Hash := Hash.Hash16_3;
  end;
  FContainer.Add(Hash, PTrieLeafNode(Node), WasNodeBusy);
  if not WasNodeBusy then
  begin
    ChildIndex := Node^.Base.ChildrenCount;
    inc(Node^.Base.ChildrenCount);
    SetChildIndex(PTrieBranchNode(Node), GetBitFieldIndex(Hash, TrieDepth - 1), ChildIndex);
    ReallocMem(Node^.Children, Node^.Base.ChildrenCount * sizeof(Pointer));
    PHashTrieNodeArray(Node^.Children)^[ChildIndex] := nil;
  end
  else ChildIndex := GetChildIndex(PTrieBranchNode(Node), GetBitFieldIndex(Hash, TrieDepth - 1));
  Result := AddOrReplaceNode(PHashTrieNodeArray(Node^.Children)^[ChildIndex], kvp);
  if Result then
    inc(FCount);
end;

function THashTrie.AddOrReplaceNode(var Root: PKeyValuePairNode; const kvp:
    TKeyValuePair): Boolean;
var
  Node, PrevNode : PKeyValuePairNode;
  WentRight : Boolean;
begin
  Node := Root;
  PrevNode := nil;
  WentRight := False;
  while Node <> nil do
  begin
    PrevNode := Node;
    if kvp.Hash > Node^.KVP.Hash then
    begin
      Node := Node^.Right;
      WentRight := True;
    end
    else if kvp.Hash < Node^.KVP.Hash then
    begin
      Node := Node^.Left;
      WentRight := False;
    end
    else
    begin
      while Node <> nil do
      begin
        PrevNode := Node;
        if CompareKeys(Node^.KVP.Key, Node^.KVP.KeySize, kvp.Key, kvp.KeySize) then
        begin
          Node^.KVP.Value := kvp.Value;
          Result := False;
          exit;
        end
        else Node := Node^.Next;
      end;
      PrevNode^.Next := NewKVPNode(kvp);
      Result := True;
      exit;
    end;
  end;
  if PrevNode <> nil then
    if WentRight then
      PrevNode^.Right := NewKVPNode(kvp)
    else PrevNode^.Left := NewKVPNode(kvp)
  else Root := NewKVPNode(kvp);
  Result := True;
end;

procedure THashTrie.Clear;
begin
  FContainer.Clear;
end;

procedure THashTrie.DoneIterator(var AIterator : THashTrieIterator);
var
  Node, TmpNode : PKeyValuePairBacktrackNode;
begin
  Node := AIterator.BackTrack;
  while Node <> nil do
  begin
    TmpNode := Node;
    Node := Node^.Next;
    trieAllocators.DeAlloc(TmpNode);
  end;
  AIterator.BackTrack := nil;
end;

function THashTrie.HashSizeToTrieDepth(AHashSize: Byte): Byte;
begin
  Result := AHashSize div BitsForChildIndexPerBucket;
end;

function THashTrie.InternalFind(key: Pointer; KeySize: Cardinal; out
    HashTrieNode: PHashTrieNode; out AChildIndex: Byte): PKeyValuePair;
var
  Hash, TreeHash : THashRecord;
  Node : PKeyValuePairNode;
begin
  if HashSize * 2 > 64 then
  begin
    CalcHash(Hash, key, KeySize, KeySize, TRIE_HASH_SEED, HashSize);
    CalcHash(TreeHash, key, KeySize div 2, KeySize, TREE_HASH_SEED, HashSize);
  end
  else
  begin
    CalcHash(Hash, key, KeySize, KeySize, TRIE_HASH_SEED, 64);
    TreeHash.Hash16 := Hash.Hash16_3;
  end;
  if FContainer.Find(Hash, PTrieLeafNode(HashTrieNode), AChildIndex, True) then
  begin
    Node := PHashTrieNodeArray(PHashTrieNode(HashTrieNode)^.Children)^[AChildIndex];
    while Node <> nil do
    begin
      if (TreeHash.Hash16 = Node^.KVP.Hash) and
          CompareKeys(Node^.KVP.Key, Node^.KVP.KeySize, key, KeySize) then
      begin
        Result := @Node^.KVP;
        exit;
      end;
      if TreeHash.Hash16 < Node^.KVP.Hash then
        Node := Node^.Left
      else if TreeHash.Hash16 > Node^.KVP.Hash then
        Node := Node^.Right
      else Node := Node^.Next;
    end;
  end;
  Result := nil;
end;

(* We won't call inherited Remove function in purpose. We want to keep our ChildIndex
   field intact and it's ChildIndex reference *)
function THashTrie.Remove(key: Pointer; KeySize: Cardinal): Boolean;
var
  kvp : PKeyValuePair;
  AChildIndex : Byte;
  ParentNodePtr : PPKeyValuePairNode;
  Node, SmallestNode, SmallestNodeParent : PKeyValuePairNode;
  HashTrieNode : PHashTrieNode;
  TreeHash : THashRecord;
  Hash : Word;
  procedure FindSmallestNode;
  var
    ANode : PKeyValuePairNode;
  begin
    ANode := Node^.Right;
    SmallestNode := ANode;
    SmallestNodeParent := nil;
    while ANode <> nil do
    begin
      if ANode^.Left <> nil then
      begin
        SmallestNodeParent := ANode;
        ANode := ANode^.Left;
        SmallestNode := ANode;
      end
      else exit;
    end;
  end;
begin
  Result := False;
  kvp := InternalFind(key, KeySize, HashTrieNode, AChildIndex);
  if kvp = nil then
    exit;
  ParentNodePtr := @PHashTrieNodeArray(HashTrieNode^.Children)^[AChildIndex];
  Node := PHashTrieNodeArray(HashTrieNode^.Children)^[AChildIndex];
  if HashSize * 2 > 64 then
  begin
    CalcHash(TreeHash, key, KeySize div 2, KeySize, TREE_HASH_SEED, HashSize);
    Hash := TreeHash.Hash16;
  end
  else
  begin
    CalcHash(TreeHash, key, KeySize, KeySize, TRIE_HASH_SEED, 64);
    Hash := TreeHash.Hash16_3;
  end;
  while Node <> nil do
  begin
    if (Hash = Node^.KVP.Hash) and
        CompareKeys(Node^.KVP.Key, Node^.KVP.KeySize, key, KeySize) then
      begin
        SmallestNode := nil;
        if (Node^.Left <> nil) and (Node^.Right <> nil) and (Node^.Next = nil) then
          FindSmallestNode
        else if (Node^.Left = nil) and (Node^.Next = nil) and (Node^.Right <> nil) then
          ParentNodePtr^ := Node^.Right
        else if (Node^.Left <> nil) and (Node^.Next = nil) and (Node^.Right = nil) then
          ParentNodePtr^ := Node^.Left
        else if (Node^.Left = nil) and (Node^.Next = nil) and (Node^.Right = nil) then
          ParentNodePtr^ := nil
        else if Node^.Next <> nil then
        begin
          ParentNodePtr^ := Node^.Next;
          Node^.Next^.Left := Node^.Left;
          Node^.Next^.Right := Node^.Right;
        end;
        FreeKey(Node^.KVP.Key, Node^.KVP.KeySize);
        FreeValue(Node^.KVP.Value);
        if SmallestNode <> nil then
        begin
          if SmallestNode <> Node^.Right then
          begin
            SmallestNodeParent^.Left := SmallestNode^.Right;
            Node^.KVP := SmallestNode^.KVP;
            Node^.Next := SmallestNode^.Next;
            trieAllocators.DeAlloc(SmallestNode);
          end
          else
          begin
            ParentNodePtr^ := Node^.Right;
            Node^.Right^.Left := Node^.Left;
            trieAllocators.DeAlloc(Node);
          end;
        end
        else trieAllocators.DeAlloc(Node);
        Result := True;
        dec(FCount);
        exit;
      end;
    if Hash < Node^.KVP.Hash then
    begin
      ParentNodePtr := @Node^.Left;
      Node := Node^.Left;
    end
    else if Hash > Node^.KVP.Hash then
    begin
      ParentNodePtr := @Node^.Right;
      Node := Node^.Right;
    end
    else
    begin
      ParentNodePtr := @Node^.Next;
      Node := Node^.Next;
    end;
  end;
end;

procedure THashTrie.InitIterator(out AIterator: THashTrieIterator);
begin
  FContainer.InitIterator(AIterator.Base);
  AIterator.BackTrack := nil;
end;

procedure THashTrie.NewBacktrackNode(var AIterator: THashTrieIterator; Node:
    PKeyValuePairNode; NextMove: TIteratorMovement);
var
  BacktrackNode : PKeyValuePairBacktrackNode;
begin
  BacktrackNode := FKeyValuePairBacktrackNodeAllocator.Alloc;
  BacktrackNode^.Node := Node;
  BacktrackNode^.Next := AIterator.BackTrack;
  if AIterator.Backtrack <> nil then
    AIterator.Backtrack^.NextMove := NextMove;
  AIterator.BackTrack := BacktrackNode;
  BacktrackNode^.NextMove := imLeft;
end;

function THashTrie.NewKVPNode(const kvp: TKeyValuePair): PKeyValuePairNode;
begin
  Result := FKeyValuePairNodeAllocator.Alloc;
  Result^.KVP := kvp;
  Result^.Left := nil;
  Result^.Right := nil;
  Result^.Next := nil;
end;

procedure THashTrie.Pack;
label
  ContinueOuterLoopIteration;
var
  It : THashTrieIterator;
  i, AChildIndex : byte;
  Node : PHashTrieNode;
begin
  FContainer.InitIterator(It.Base);
  while FContainer.Next(It.Base) do
  begin
    Node := FContainer.GetObjectFromIterator(It.Base);
    for i := 0 to ChildrenPerBucket - 1 do
    begin
      if GetBusyIndicator(@Node^.Base, i) then
      begin
         AChildIndex := GetChildIndex(PTrieBranchNode(Node), i);
         if PHashTrieNodeArray(Node^.Children)^[AChildIndex] <> nil then
           goto ContinueOuterLoopIteration;
      end;
    end;
    Node^.Base.Busy := NOT_BUSY; // We mark the record as not busy anymore, will be collected by FContainer.Pack()
ContinueOuterLoopIteration:
  end;
  FContainer.Pack;
end;

function THashTrie.Next(var AIterator: THashTrieIterator): PKeyValuePair;
var
  AChildIndex, ABitFieldIndex : Byte;
  Node : PTrieBranchNode;
  KVPNode : PKeyValuePairNode;
begin
  if AIterator.BackTrack <> nil then
  begin
    KVPNode := AIterator.BackTrack^.Node;
    Result := @KVPNode^.KVP;
    NextLeafTreeNode(AIterator);
    exit;
  end;
  while FContainer.Next(AIterator.Base) do
  begin
    ABitFieldIndex := GetBitFieldIndex(AIterator.Base.LastResult64, TrieDepth - 1);
    Node := FContainer.GetObjectFromIterator(AIterator.Base);
    AChildIndex := GetChildIndex(Node, ABitFieldIndex);
    KVPNode := PHashTrieNodeArray(Node^.Children)^[AChildIndex];
    if KVPNode = nil then
      continue;
    Result := @KVPNode^.KVP;
    NewBacktrackNode(AIterator, KVPNode, imLeft);
    NextLeafTreeNode(AIterator);
    exit;
  end;
  Result := nil;
end;

procedure THashTrie.NextLeafTreeNode(var AIterator: THashTrieIterator;
    AFreeNodes: Boolean = False);
var
  BacktrackNode : PKeyValuePairBacktrackNode;
  procedure MoveUp;
  var
    kvp : PKeyValuePair;
  begin
    if AFreeNodes then
    begin
      kvp := @AIterator.BackTrack^.Node^.KVP;
      FreeKey(kvp^.Key, kvp^.KeySize);
      FreeValue(kvp^.Value);
      trieAllocators.DeAlloc(AIterator.BackTrack^.Node);
    end;
    BacktrackNode := AIterator.BackTrack;
    AIterator.BackTrack := BacktrackNode^.Next;
    trieAllocators.Dealloc(BacktrackNode);
  end;
begin
  while AIterator.BackTrack <> nil do
    begin
      case AIterator.BackTrack^.NextMove of
        imLeft : if AIterator.BackTrack^.Node^.Left <> nil then
        begin
          NewBacktrackNode(AIterator, AIterator.BackTrack^.Node^.Left, imNext);
          exit;
        end
        else
        begin
          inc(AIterator.BackTrack^.NextMove);
          continue;
        end;
        imNext : if AIterator.BackTrack^.Node^.Next <> nil then
        begin
          NewBacktrackNode(AIterator, AIterator.BackTrack^.Node^.Next, imRight);
          exit;
        end
        else
        begin
          inc(AIterator.BackTrack^.NextMove);
          continue;
        end;
        imRight : if AIterator.BackTrack^.Node^.Right <> nil then
        begin
          NewBacktrackNode(AIterator, AIterator.BackTrack^.Node^.Right, imUp);
          exit;
        end
        else MoveUp;
        imUp : MoveUp;
      end;
    end;
end;

end.
