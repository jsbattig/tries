unit Hash_Trie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  Trie, uAllocators, HashedContainer;

type
  THashSize = (hs16, hs32, hs64);

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
    Base : TTrieIterator;
    BackTrack : PKeyValuePairBacktrackNode;
  end;

  THashRecord = record
    case THashSize of
      hs16 : (Hash16 : Word);
      hs32 : (Hash32 : Cardinal);
      hs64 : (Hash64 : Int64);
  end;

  TAutoFreeMode = (afmFree, afmFreeMem);
  TDuplicatesMode = (dmNotAllow, dmAllowed, dmReplaceExisting);

  { THashTrie }

  THashTrie = class(THashedContainer)
  private
    FContainer : THashedContainer;
    FHashSize : THashSize;
    FAutoFreeValue : Boolean;
    FAutoFreeValueMode : TAutoFreeMode;
    FKeyValuePairNodeAllocator : TFixedBlockHeap;
    FKeyValuePairBacktrackNodeAllocator : TFixedBlockHeap;
    FTrieDepth: Byte;
    function AddOrReplaceNode(var Root: PKeyValuePairNode; const kvp:
        TKeyValuePair): Boolean;
    procedure NewBacktrackNode(var AIterator: THashTrieIterator; Node:
        PKeyValuePairNode; NextMove: TIteratorMovement);
    function NewKVPNode(const kvp: TKeyValuePair): PKeyValuePairNode;
    procedure NextLeafTreeNode(var AIterator: THashTrieIterator; AFreeNodes:
        Boolean = False);
  protected
    procedure InitLeaf(var Leaf);
    procedure FreeKey({%H-}key : Pointer); virtual;
    procedure FreeValue({%H-}value : Pointer); virtual;
    function CompareKeys(key1: Pointer; KeySize1: Cardinal; key2: Pointer;
        KeySize2: Cardinal): Boolean; virtual; abstract;
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
    procedure CalcHash(out Hash: THashRecord; key: Pointer; KeySize, ASeed:
        Cardinal); virtual;
    function Hash16(key: Pointer; KeySize, ASeed: Cardinal): Word; virtual;
    function Hash32(key: Pointer; KeySize, ASeed: Cardinal): Cardinal; virtual;
    function Hash64(key: Pointer; KeySize, ASeed: Cardinal): Int64; virtual;
    function Add(var kvp: TKeyValuePair): Boolean; reintroduce;
    function InternalFind(key: Pointer; KeySize: Cardinal; out HashTrieNode:
                          PHashTrieNode; out AChildIndex: Byte): PKeyValuePair; reintroduce;
    function Remove(key: Pointer; KeySize: Cardinal): Boolean; reintroduce;
    function Next(var AIterator : THashTrieIterator) : PKeyValuePair; reintroduce;
    procedure RaiseHashSizeError; inline;
    property HashSize : THashSize read FHashSize;
    property TrieDepth: Byte read FTrieDepth;
  public
    constructor Create(AHashSize : THashSize);
    destructor Destroy; override;
    procedure Clear; override;
    procedure InitIterator(out AIterator : THashTrieIterator); reintroduce;
    procedure DoneIterator(var AIterator : THashTrieIterator);
    procedure Pack; override;
    property AutoFreeValue : Boolean read FAutoFreeValue write FAutoFreeValue;
    property AutoFreeValueMode : TAutoFreeMode read FAutoFreeValueMode write FAutoFreeValueMode;
  end;

implementation

uses
  xxHash;

const
  TRIE_HASH_SEED = $FEA0945B;
  TREE_HASH_SEED = $AFC456EB;

{ THashTrie }

constructor THashTrie.Create(AHashSize: THashSize);
const
  HashSizeToTrieDepth : array[hs16..hs64] of Byte = (4, 8, 16);
  THashSizeToHashSize : array[hs16..hs64] of Byte = (sizeof(Word), sizeof(Cardinal), sizeof(Int64));
begin
  FTrieDepth := HashSizeToTrieDepth[AHashSize];
  inherited Create(THashSizeToHashSize[AHashSize], sizeof(THashTrieNode));
  FContainer := TTrie.Create(HashSizeToTrieDepth[AHashSize], sizeof(THashTrieNode));
  FContainer.OnFreeTrieNode := FreeTrieNode;
  FContainer.OnInitLeaf := InitLeaf;
  FHashSize := AHashSize;
  FKeyValuePairNodeAllocator := TFixedBlockHeap.Create(sizeof(TKeyValuePairNode), 2048 div sizeof(TKeyValuePairNode));
  FKeyValuePairBacktrackNodeAllocator := TFixedBlockHeap.Create(sizeof(TKeyValuePairBacktrackNode), 2048 div sizeof(TKeyValuePairBacktrackNode));
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
  Result := Cardinal(xxHash32Calc(key, KeySize, ASeed));
end;

function THashTrie.Hash64(key: Pointer; KeySize, ASeed: Cardinal): Int64;
var
  AHash32_1, AHash32_2 : Cardinal;
begin
  AHash32_1 := Hash32(PAnsiChar(key), KeySize div 2, ASeed);
  AHash32_2 := Hash32(@PAnsiChar(key)[KeySize div 2], KeySize - (KeySize div 2), ASeed);
  Result := Int64(AHash32_1) + Int64(AHash32_2) shl 32;
end;

procedure THashTrie.CalcHash(out Hash: THashRecord; key: Pointer; KeySize,
    ASeed: Cardinal);
begin
  case FHashSize of
    hs16 : Hash.Hash16 := Hash16(key, KeySize, ASeed);
    hs32 : Hash.Hash32 := Hash32(key, KeySize, ASeed);
    hs64 : Hash.Hash64 := Hash64(key, KeySize, ASeed);
    else RaiseHashSizeError;
  end;
end;

procedure THashTrie.InitLeaf(var Leaf);
begin
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
  CalcHash(Hash, kvp.Key, kvp.KeySize, TRIE_HASH_SEED);
  CalcHash(TreeHash, kvp.Key, kvp.KeySize, TREE_HASH_SEED);
  kvp.Hash := TreeHash.Hash16;
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
    uAllocators.DeAlloc(TmpNode);
  end;
  AIterator.BackTrack := nil;
end;

function THashTrie.InternalFind(key: Pointer; KeySize: Cardinal; out
    HashTrieNode: PHashTrieNode; out AChildIndex: Byte): PKeyValuePair;
var
  Hash : THashRecord;
  Node : PKeyValuePairNode;
begin
  CalcHash(Hash, key, KeySize, TRIE_HASH_SEED);
  if FContainer.Find(Hash, PTrieLeafNode(HashTrieNode), AChildIndex, True) then
  begin
    CalcHash(Hash, key, KeySize, TREE_HASH_SEED);
    Node := PHashTrieNodeArray(PHashTrieNode(HashTrieNode)^.Children)^[AChildIndex];
    while Node <> nil do
    begin
      if (Hash.Hash16 = Node^.KVP.Hash) and
          CompareKeys(Node^.KVP.Key, Node^.KVP.KeySize, key, KeySize) then
      begin
        Result := @Node^.KVP;
        exit;
      end;
      if Hash.Hash16 < Node^.KVP.Hash then
        Node := Node^.Left
      else if Hash.Hash16 > Node^.KVP.Hash then
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
  CalcHash(TreeHash, key, KeySize, TREE_HASH_SEED);
  Hash := TreeHash.Hash16;
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
        FreeKey(Node^.KVP.Key);
        FreeValue(Node^.KVP.Value);
        if SmallestNode <> nil then
        begin
          if SmallestNode <> Node^.Right then
          begin
            SmallestNodeParent^.Left := SmallestNode^.Right;
            Node^.KVP := SmallestNode^.KVP;
            Node^.Next := SmallestNode^.Next;
            uAllocators.DeAlloc(SmallestNode);
          end
          else
          begin
            ParentNodePtr^ := Node^.Right;
            Node^.Right^.Left := Node^.Left;
            uAllocators.DeAlloc(Node);
          end;
        end
        else uAllocators.DeAlloc(Node);
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
  It : TTrieIterator;
  i, AChildIndex : byte;
  ATrieDepth : Byte;
  Node : PHashTrieNode;
begin
  ATrieDepth := TrieDepth;
  FContainer.InitIterator(It);
  while FContainer.Next(It) do
  begin
    Node := PHashTrieNode(It.NodeStack[ATrieDepth - 1]);
    for i := 0 to ChildrenPerBucket - 1 do
    begin
      if GetBusyIndicator(@Node^.Base, i) then
      begin
         AChildIndex := GetChildIndex(PTrieBranchNode(Node), i);
         if PHashTrieNodeArray(Node^.Children)^[AChildIndex] <> nil then
           goto ContinueOuterLoopIteration;
      end;
    end;
    Node^.Base.Busy := 0; // We mark the record as not busy anymore, will be collected by FContainer.Pack()
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
    Node := PTrieBranchNode(AIterator.Base.NodeStack[TrieDepth - 1]);
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
  begin
    if AFreeNodes then
    begin
      FreeKey(AIterator.BackTrack^.Node^.KVP.Key);
      FreeValue(AIterator.BackTrack^.Node^.KVP.Value);
      uAllocators.DeAlloc(AIterator.BackTrack^.Node);
    end;
    BacktrackNode := AIterator.BackTrack;
    AIterator.BackTrack := BacktrackNode^.Next;
    uAllocators.Dealloc(BacktrackNode);
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

procedure THashTrie.RaiseHashSizeError;
const
  STR_HASHSIZEERROR = 'Wrong hash size';
begin
  raise ETrie.Create(STR_HASHSIZEERROR);
end;

end.
