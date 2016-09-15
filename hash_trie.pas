unit Hash_Trie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  Trie, hash_table, trieAllocators, HashedContainer, Classes;

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

  TIteratorMovement = (imLeft, imNext, imRight);
  PKeyValuePairBacktrackNode = ^TKeyValuePairBacktrackNode;
  TKeyValuePairBacktrackNode = record
    NodeParent : PPKeyValuePairNode;
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
    CurNodeParent : PPKeyValuePairNode;
    CurNode : PKeyValuePairNode;
    RemoveOperationCount : Cardinal;
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

  TAutoFreeMode = (afmFree, afmFreeMem, afmStrDispose, afmReleaseInterface);
  TDuplicatesMode = (dmNotAllow, dmAllowed, dmReplaceExisting);

  { THashTrie }

  EHashTrie = class(EHashedContainer);
  THashTrie = class(TBaseHashedContainer)
  private
    FContainer : THashedContainer;
    FAutoFreeValue : Boolean;
    FAutoFreeValueMode : TAutoFreeMode;
    FRemoveOperationCount: Cardinal;
    FLastNodeRemoved : PKeyValuePairNode;
    FPackingRequired : Boolean;
    FKeyValuePairNodeAllocator : TFixedBlockHeap;
    FKeyValuePairBacktrackNodeAllocator : TFixedBlockHeap;
    FTrieDepth: Byte;
    procedure NewBacktrackNode(var AIterator: THashTrieIterator; Node:
                               PKeyValuePairNode; ParentNodePtr: PPKeyValuePairNode; NextMove:
                               TIteratorMovement = imLeft);
    { Methods to manage key/value pair linked to each array entry on Trie leaf nodes }
    function AddOrReplaceKVPTreeNode(var Root: PKeyValuePairNode; const kvp: TKeyValuePair): Boolean;
    procedure FreeKVPTreeNode(var CurNode: PKeyValuePairNode);
    function NewKVPTreeNode(const kvp: TKeyValuePair): PKeyValuePairNode;
    procedure NextKVPTreeNode(var AIterator: THashTrieIterator; AFreeNodes: Boolean = False);
    procedure RemoveKVPTreeNode(ParentNodePtr: PPKeyValuePairNode; Node: PKeyValuePairNode);
    {$IFDEF DEBUG}
    procedure InvalidateKVPTreeNode(ANode : PKeyValuePairNode);
    {$ENDIF}
  protected
    procedure InitLeaf(var Leaf); {$IFNDEF FPC} inline; {$ENDIF}
    procedure FreeKey({%H-}key: Pointer; {%H-}KeySize: Cardinal); virtual;
    procedure FreeValue({%H-}value : Pointer); virtual;
    function CompareKeys(key1: Pointer; KeySize1: Cardinal; key2: Pointer;
                         KeySize2: Cardinal): Boolean; virtual; abstract;
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
    procedure CalcHash(out Hash: THashRecord; key: Pointer; KeySize: Cardinal;
                       ASeed: _Int64; AHashSize: Byte); virtual;
    function Hash16(key: Pointer; KeySize, ASeed: Cardinal): Word; virtual;
    function Hash32(key: Pointer; KeySize, {%H-}ASeed: Cardinal): Cardinal; virtual;
    function Hash64(key: Pointer; KeySize: Cardinal; ASeed: _Int64): Int64; virtual;
    function Add(var kvp: TKeyValuePair): Boolean;
    function InternalFind(key: Pointer; KeySize: Cardinal; out HashTrieNode:
                          PHashTrieNode; out AChildIndex: Byte): PKeyValuePair;
    function Remove(key: Pointer; KeySize: Cardinal): Boolean;
    function Next(var AIterator : THashTrieIterator) : PKeyValuePair;
    property TrieDepth: Byte read FTrieDepth;
  public
    constructor Create(AHashSize: Byte; AUseHashTable: Boolean);
    destructor Destroy; override;
    procedure Clear;
    procedure InitIterator(out AIterator : THashTrieIterator);
    procedure DoneIterator(var AIterator : THashTrieIterator);
    procedure RemoveCurrentNode(const AIterator : THashTrieIterator);
    procedure Pack;
    function ListOfValues: TList;
    property AutoFreeValue : Boolean read FAutoFreeValue write FAutoFreeValue;
    property AutoFreeValueMode : TAutoFreeMode read FAutoFreeValueMode write FAutoFreeValueMode;
  end;

function HashSizeToTrieDepth(AHashSize: Byte): Byte; inline;

implementation

uses
  xxHash, SysUtils, uSuperFastHash {$IFDEF UNICODE}, AnsiStrings {$ENDIF};

resourcestring
  SInternalErrorUseHashTableWithHashSize = 'Internal error: if AUseHashTable is True then AHashSize must be <= 20 calling constructor THashTrie.Create()';
  SInternalErrorCheckParameterAHashSize = 'Internal error: check parameter AHashSize calling THashTrie.Create() constructor';
  StrIteratorWasInvalidated = 'Iterator was invalidated by removing a different node than the currently being pointed at by it';
  SHashTableMaxHashSizeIs20 = 'HashTable mode maximum hashsize is 20bits';

function HashSizeToTrieDepth(AHashSize: Byte): Byte;
begin
  Result := AHashSize div BitsForChildIndexPerBucket;
end;

const
  TRIE_HASH_SEED = $FEA0945B;
  TREE_HASH_SEED = $AFC456EB;

{ THashTrie }

constructor THashTrie.Create(AHashSize: Byte; AUseHashTable: Boolean);
begin
  if (AHashSize mod BitsForChildIndexPerBucket <> 0) or (AHashSize < 16) or (AHashSize > 64) then
    raise EHashTrie.Create(SInternalErrorCheckParameterAHashSize);
  if AUseHashTable and (AHashSize > 20) then
    raise EHashTrie.Create(SInternalErrorUseHashTableWithHashSize);
  FTrieDepth := HashSizeToTrieDepth(AHashSize);
  inherited Create(AHashSize, sizeof(THashTrieNode));
  if (AHashSize > 20) and AUseHashTable then
    raise EHashTrie.Create(SHashTableMaxHashSizeIs20);
  if AUseHashTable then
    FContainer := THashTable.Create(AHashSize, sizeof(THashTrieNode))
  else FContainer := TTrie.Create(FTrieDepth, sizeof(THashTrieNode));
  FContainer.OnFreeTrieNode := {$IFDEF FPC}@{$ENDIF}FreeTrieNode;
  FContainer.OnInitLeaf := {$IFDEF FPC}@{$ENDIF}InitLeaf;
  FKeyValuePairNodeAllocator := TFixedBlockHeap.Create(sizeof(TKeyValuePairNode), _16KB div sizeof(TKeyValuePairNode));
  FKeyValuePairBacktrackNodeAllocator := TFixedBlockHeap.Create(sizeof(TKeyValuePairBacktrackNode), _16KB div sizeof(TKeyValuePairBacktrackNode));
end;

destructor THashTrie.Destroy;
begin
  inherited;
  if FContainer <> nil then
  begin
    Clear;
    FreeAndNil(FContainer);
  end;
  if FKeyValuePairBacktrackNodeAllocator <> nil then
    FreeAndNil(FKeyValuePairBacktrackNodeAllocator);
  if FKeyValuePairNodeAllocator <> nil then
    FreeAndNil(FKeyValuePairNodeAllocator);
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
  //Result := SuperFastHash(key, KeySize, False);
  Result := xxHash32Calc(key, KeySize, ASeed);
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

procedure THashTrie.CalcHash(out Hash: THashRecord; key: Pointer; KeySize:
    Cardinal; ASeed: _Int64; AHashSize: Byte);
begin
  case AHashSize of
    16 : Hash.Hash16 := Hash16(key, KeySize, ASeed);
    20, 32 : Hash.Hash32 := Hash32(key, KeySize, ASeed);
    64 : Hash.Hash64 := Hash64(key, KeySize, ASeed);
    else RaiseHashSizeError;
  end;
end;

procedure THashTrie.InitLeaf(var Leaf);
begin
  THashTrieNode(Leaf).Children := nil;
  THashTrieNode(Leaf).ChildIndex[0] := 0;
  THashTrieNode(Leaf).ChildIndex[1] := 0;
end;

procedure THashTrie.FreeKey(key: Pointer; KeySize: Cardinal);
begin
  // Descendants of this class may implement some key disposal if required
end;

procedure THashTrie.FreeValue(value: Pointer);
begin
  if FAutoFreeValue then
    case FAutoFreeValueMode of
      afmFree             : TObject(value).Free;
      afmFreeMem          : FreeMem(value);
      afmStrDispose       : {$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrDispose(PAnsiChar(value));
      afmReleaseInterface : IUnknown(Value)._Release;
    end;
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
      NewBacktrackNode(AIterator, ListNode, @PHashTrieNodeArray(PHashTrieNode(ANode)^.Children)^[i]);
      repeat
        NextKVPTreeNode(AIterator, True);
      until AIterator.BackTrack = nil;
    end;
    if PHashTrieNode(ANode)^.Base.ChildrenCount > 0 then
    begin
      FreeMem(PHashTrieNode(ANode)^.Children);
      PHashTrieNode(ANode)^.Children := nil;
      PHashTrieNode(ANode)^.Base.ChildrenCount := 0;
    end;
  end;
end;

function THashTrie.Add(var kvp: TKeyValuePair): Boolean;
var
  Node : PHashTrieNode;
  Hash, TreeHash : THashRecord;
  WasNodeBusy : Boolean;
  ChildIndex : Byte;
begin
  if HashSize = 64 then
  begin
    CalcHash(Hash, kvp.Key, kvp.KeySize, TRIE_HASH_SEED, HashSize);
    CalcHash(TreeHash, kvp.Key, kvp.KeySize, TREE_HASH_SEED, HashSize);
    kvp.Hash := TreeHash.Hash16;
  end
  else
  begin
    CalcHash(Hash, kvp.Key, kvp.KeySize, TRIE_HASH_SEED, 64);
    kvp.Hash := Hash.Hash16_3;
  end;
  FContainer.Add(Hash, PTrieLeafNode(Node), WasNodeBusy);
  if not WasNodeBusy then
  begin
    ChildIndex := Node^.Base.ChildrenCount;
    inc(Node^.Base.ChildrenCount);
    Assert(Node^.Base.ChildrenCount <= ChildrenPerBucket, 'Node^.Base.ChildrenCount must be equal or lesser then ChildrenPerBucket');
    SetChildIndex(PTrieBranchNode(Node), GetBitFieldIndex(Hash, TrieDepth - 1), ChildIndex);
    ReallocMem(Node^.Children, Node^.Base.ChildrenCount * sizeof(Pointer));
    PHashTrieNodeArray(Node^.Children)^[ChildIndex] := nil;
  end
  else ChildIndex := GetChildIndex(PTrieBranchNode(Node), GetBitFieldIndex(Hash, TrieDepth - 1));
  Result := AddOrReplaceKVPTreeNode(PHashTrieNodeArray(Node^.Children)^[ChildIndex], kvp);
  if Result then
    inc(FCount);
end;

function THashTrie.AddOrReplaceKVPTreeNode(var Root: PKeyValuePairNode; const
    kvp: TKeyValuePair): Boolean;
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
          if (Node^.KVP.Value <> nil) and (Node^.KVP.Value <> kvp.Value) then
            FreeValue(Node^.KVP.Value);
          Node^.KVP.Value := kvp.Value;
          Result := False;
          exit;
        end
        else Node := Node^.Next;
      end;
      PrevNode^.Next := NewKVPTreeNode(kvp);
      Result := True;
      exit;
    end;
  end;
  if PrevNode <> nil then
    if WentRight then
      PrevNode^.Right := NewKVPTreeNode(kvp)
    else PrevNode^.Left := NewKVPTreeNode(kvp)
  else Root := NewKVPTreeNode(kvp);
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

procedure THashTrie.FreeKVPTreeNode(var CurNode: PKeyValuePairNode);
var
  kvp : PKeyValuePair;
begin
  kvp := @CurNode^.KVP;
  FreeKey(kvp^.Key, kvp^.KeySize);
  if kvp^.Value <> nil then
    FreeValue(kvp^.Value);
  {$IFDEF DEBUG}
  InvalidateKVPTreeNode(CurNode);
  {$ENDIF}
  trieAllocators.DeAlloc(CurNode);
  CurNode := nil;
end;

function THashTrie.InternalFind(key: Pointer; KeySize: Cardinal; out
    HashTrieNode: PHashTrieNode; out AChildIndex: Byte): PKeyValuePair;
var
  Hash, TreeHash : THashRecord;
  Node : PKeyValuePairNode;
begin
  if HashSize = 64 then
  begin
    CalcHash(Hash, key, KeySize, TRIE_HASH_SEED, HashSize);
    CalcHash(TreeHash, key, KeySize, TREE_HASH_SEED, HashSize);
  end
  else
  begin
    CalcHash(Hash, key, KeySize, TRIE_HASH_SEED, 64);
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
  Node : PKeyValuePairNode;
  HashTrieNode : PHashTrieNode;
  TreeHash : THashRecord;
  Hash : Word;
begin
  Result := False;
  kvp := InternalFind(key, KeySize, HashTrieNode, AChildIndex);
  if kvp = nil then
    exit;
  ParentNodePtr := @PHashTrieNodeArray(HashTrieNode^.Children)^[AChildIndex];
  Node := PHashTrieNodeArray(HashTrieNode^.Children)^[AChildIndex];
  if HashSize = 64 then
  begin
    CalcHash(TreeHash, key, KeySize, TREE_HASH_SEED, HashSize);
    Hash := TreeHash.Hash16;
  end
  else
  begin
    CalcHash(TreeHash, key, KeySize, TRIE_HASH_SEED, 64);
    Hash := TreeHash.Hash16_3;
  end;
  while Node <> nil do
  begin
    if (Hash = Node^.KVP.Hash) and
        CompareKeys(Node^.KVP.Key, Node^.KVP.KeySize, key, KeySize) then
      begin
        RemoveKVPTreeNode(ParentNodePtr, Node);
        Result := True;
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
      Assert(Node^.Left = nil, 'Node linked list present. Node^.Left must be nil');
      Assert(Node^.Right = nil, 'Node linked list present. Node^.Right must be nil');
    end;
  end;
end;

procedure THashTrie.InitIterator(out AIterator: THashTrieIterator);
begin
  FContainer.InitIterator(AIterator.Base);
  AIterator.BackTrack := nil;
  AIterator.CurNodeParent := nil;
  AIterator.CurNode := nil;
  AIterator.RemoveOperationCount := FRemoveOperationCount;
  FLastNodeRemoved := nil;
end;

{$IFDEF DEBUG}
procedure THashTrie.InvalidateKVPTreeNode(ANode : PKeyValuePairNode);
begin
  {$IFNDEF CPUX64}
  ANode^.Left := Pointer($FEFEFEFE);
  ANode^.Next := Pointer($FEFEFEFE);
  ANode^.Right := Pointer($FEFEFEFE);
  {$ELSE}
  ANode^.Left := Pointer($FEFEFEFEFEFEFEFE);
  ANode^.Next := Pointer($FEFEFEFEFEFEFEFE);
  ANode^.Right := Pointer($FEFEFEFEFEFEFEFE);
  {$ENDIF}
end;
{$ENDIF}

procedure THashTrie.NewBacktrackNode(var AIterator: THashTrieIterator; Node:
    PKeyValuePairNode; ParentNodePtr: PPKeyValuePairNode; NextMove:
    TIteratorMovement = imLeft);
var
  BacktrackNode : PKeyValuePairBacktrackNode;
begin
  BacktrackNode := FKeyValuePairBacktrackNodeAllocator.Alloc;
  BacktrackNode^.Node := Node;
  BacktrackNode^.NodeParent := ParentNodePtr;
  BacktrackNode^.Next := AIterator.BackTrack;
  if AIterator.Backtrack <> nil then
    AIterator.Backtrack^.NextMove := NextMove;
  AIterator.BackTrack := BacktrackNode;
  BacktrackNode^.NextMove := imLeft;
end;

function THashTrie.NewKVPTreeNode(const kvp: TKeyValuePair): PKeyValuePairNode;
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
  if not FPackingRequired then
    exit;
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
  FPackingRequired := False;
end;

function THashTrie.Next(var AIterator: THashTrieIterator): PKeyValuePair;
var
  AChildIndex, ABitFieldIndex : Byte;
  Node : PTrieBranchNode;
  KVPNode : PKeyValuePairNode;
begin
  if (FRemoveOperationCount - AIterator.RemoveOperationCount > 1) or
     ((FRemoveOperationCount - AIterator.RemoveOperationCount = 1) and
      (FLastNodeRemoved <> AIterator.CurNode)) then
    raise EHashTrie.Create(StrIteratorWasInvalidated);
  AIterator.RemoveOperationCount := FRemoveOperationCount;
  if AIterator.BackTrack <> nil then
  begin
    NextKVPTreeNode(AIterator);
    Assert(AIterator.CurNode <> nil, 'If AIterator.BackTrack <> nil then AIterator.CurNode must be <> nil after call to NextKVPTreeNode()');
    KVPNode := AIterator.CurNode;
    Result := @KVPNode^.KVP;
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
    NewBacktrackNode(AIterator, KVPNode, @PHashTrieNodeArray(Node^.Children)^[AChildIndex]);
    NextKVPTreeNode(AIterator);
    Assert(AIterator.CurNode <> nil, 'AIterator.CurNode must be <> nil after call to NextKVPTreeNode() when KVPNode was <> nil');
    Result := @AIterator.CurNode^.KVP;
    exit;
  end;
  Result := nil;
end;

procedure THashTrie.NextKVPTreeNode(var AIterator: THashTrieIterator;
    AFreeNodes: Boolean = False);
  procedure MoveUp;
  var
    BacktrackNode : PKeyValuePairBacktrackNode;
  begin
    BacktrackNode := AIterator.BackTrack;
    AIterator.CurNode := BacktrackNode^.Node;
    AIterator.CurNodeParent := BacktrackNode^.NodeParent;
    AIterator.BackTrack := BacktrackNode^.Next;
    trieAllocators.Dealloc(BacktrackNode);
  end;
begin
  while AIterator.BackTrack <> nil do
    begin
      case AIterator.BackTrack^.NextMove of
        imLeft : if AIterator.BackTrack^.Node^.Left <> nil then
            NewBacktrackNode(AIterator, AIterator.BackTrack^.Node^.Left, @AIterator.BackTrack^.Node^.Left, imNext)
          else inc(AIterator.BackTrack^.NextMove);
        imNext : if AIterator.BackTrack^.Node^.Next <> nil then
            NewBacktrackNode(AIterator, AIterator.BackTrack^.Node^.Next, @AIterator.BackTrack^.Node^.Next, imRight)
          else inc(AIterator.BackTrack^.NextMove);
        imRight :
          begin
            if AIterator.BackTrack^.Node^.Right <> nil then
            begin
              // Moving to the right. We will keep the Backtrack node and move on to next pointer on right
              // When unwinding it will go up to the parent of *this node* (that potentially
              // was removed during the iteration)
              AIterator.CurNode := AIterator.BackTrack^.Node;
              AIterator.CurNodeParent := AIterator.BackTrack^.NodeParent;
              AIterator.BackTrack^.Node := AIterator.BackTrack^.Node^.Right;
              AIterator.BackTrack^.NextMove := imLeft;
            end
            else MoveUp;
            break;
          end;
      end;
    end;
  if AFreeNodes and (AIterator.CurNode <> nil) then
    FreeKVPTreeNode(AIterator.CurNode);
end;

procedure THashTrie.RemoveCurrentNode(const AIterator : THashTrieIterator);
begin
  RemoveKVPTreeNode(AIterator.CurNodeParent, AIterator.CurNode);
end;

procedure THashTrie.RemoveKVPTreeNode(ParentNodePtr: PPKeyValuePairNode; Node:
    PKeyValuePairNode);
var
  SmallestNode, SmallestNodeParent : PKeyValuePairNode;
  procedure FindSmallestNodeOnRight;
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
  SmallestNode := nil;
  if Node^.Next <> nil then
  begin
    // There's more nodes with the same exact hash. We will pull up
    // the next node in the linked list of same exact hash nodes
    ParentNodePtr^ := Node^.Next;
    Node^.Next^.Left := Node^.Left;
    Node^.Next^.Right := Node^.Right;
  end
  else if (Node^.Left <> nil) and (Node^.Right <> nil) then
    FindSmallestNodeOnRight // Nodes left and right, find smallest node on right side
  // Following cases are the "easy" cases where only one node left or right
  // is connected to a subtree
  else if (Node^.Left = nil) and (Node^.Right <> nil) then
    ParentNodePtr^ := Node^.Right
  else if (Node^.Left <> nil) and (Node^.Right = nil) then
    ParentNodePtr^ := Node^.Left
  else if (Node^.Left = nil) and (Node^.Right = nil) then
    ParentNodePtr^ := nil; // Removing a terminal node with no linked list
  FreeKey(Node^.KVP.Key, Node^.KVP.KeySize);
  if Node^.KVP.Value <> nil then
    FreeValue(Node^.KVP.Value);
  if SmallestNode <> nil then
  begin
    if SmallestNode <> Node^.Right then
    begin
      // When the smallest node is any other node than the one on the immediate
      // right of the one being removed, we will copy the contents of the smallest
      // node to the actual node being "removed", adjust some pointers and really
      // remove the smalles node
      SmallestNodeParent^.Left := SmallestNode^.Right;
      Node^.KVP := SmallestNode^.KVP;
      Node^.Next := SmallestNode^.Next;
      trieAllocators.DeAlloc(SmallestNode);
    end
    else
    begin
      // When the smallest node is the one on the immediate right, we will
      // connect the parent of the node being removed to the one on the immediate
      // right, connect this one to the whole left branch of the one being removed
      // and then dealloc the node being removed.
      // We can do this connection to the left pointer of the node to the right
      // because we know this node doesn't have any tree on its left by definition
      ParentNodePtr^ := Node^.Right;
      Assert(Node^.Right^.Left = nil, 'Node^.Right^.Left must be nil on this branch');
      Node^.Right^.Left := Node^.Left;
      {$IFDEF DEBUG}
      InvalidateKVPTreeNode(Node);
      {$ENDIF}
      trieAllocators.DeAlloc(Node);
    end;
  end
  else trieAllocators.DeAlloc(Node);
  dec(FCount);
  FPackingRequired := True;
  inc(FRemoveOperationCount);
  FLastNodeRemoved := Node;
end;

function THashTrie.ListOfValues: TList;
var
  It : THashTrieIterator;
  kvp : PKeyValuePair;
begin
  Result := TList.Create;
  try
    Result.Capacity := FCount;
    InitIterator(It);
    try
      repeat
        kvp := Next(It);
        if kvp = nil then
          break;
        Result.Add(kvp^.Value);
      until False;
    finally
      DoneIterator(It);
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
