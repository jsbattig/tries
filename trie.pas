(*
  The MIT License (MIT)

  Copyright (c) 2015 Jose Sebastian Battig

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

  This class provides the basis to construct a Trie based container.
  On it's basic form it can be used to store 16, 32 and 64 bits based data elements.
  The structure provides a fixed depth Trie implementation, which in turns renders
  equal time to Find and Remove nodes, and consistent Add times incurring only in
  extra overhead when needing the acquire new nodes.
  To keep node size small, only 16 branches per node will be used and indicator flags
  and internal pointer indexes are encoded in a 16 bits word and in a 64 bits integer.
  Pointers to branches are managed dynamically so only an pointer is allocated on the
  pointers array when a new branch needs to be added, this minimizes waste of
  pre-allocated pointers array to lower level branches.
  Leafs are allocated in-place rather than as individual nodes pointed by the last
  branch node.
  Finally, Leaf nodes can be dynamically controlled by the derived class from TTrie
  allowing for easy implementation of dictionaries using TTrie as a base.
*)

unit Trie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  SysUtils, trieAllocators, HashedContainer;

const
  MaxTrieDepth = sizeof(Int64) * BitsPerByte div BitsForChildIndexPerBucket;

type
  TTrieNodeArray = array[0..ChildrenPerBucket - 1] of PTrieBranchNode;
  PTrieNodeArray = ^TTrieNodeArray;

  (*
    IMPORTANT NOTE ON Delphi 2007:

    Delphi 2007 compiler places the start of Int64 at a different address than
    the 32 bits counterpart on the union... Internal record layout related to
    alignment or packing differs... bug or feature. Go figure..
    FreePascal and higher
    versions of Delphi behave consistently placing all elements on the same
    starting address.

    The following record relies on some optimization that requires that all of the
    variant part of the record start on the same offset, that's why it's declared
    as packed and the fields are padded.
  *)
  TTrieIterator = packed record
    Base : THashedContainerIterator;
    Level : SmallInt; _Padding2 : array [1..2] of Byte;
    BreadCrumbs : array[0..MaxTrieDepth - 1] of SmallInt;
    NodeStack : array[0..MaxTrieDepth - 1] of PTrieBaseNode;
  end;

  { TTrie }

  TTrieRandomAccessMode = (ramDisabled, ramSequential, ramFull);

  ETrie = class(Exception);
  ETrieDuplicate = class(ETrie);
  ETrieRandomAccess = class(ETrie);

  TTrie = class(THashedContainer)
  private
    FRandomAccessMode: TTrieRandomAccessMode;
    FRoot : PTrieBranchNode;
    FRandomAccessIterator : TTrieIterator;
    FLastIndex : Integer;
    FLastMidBranchNode : Byte;
    FTrieBranchNodeAllocator : TFixedBlockHeap;
    FTrieDepth: Byte;
    function NewTrieBranchNode : PTrieBranchNode;
    function AddChild(ANode : PTrieBranchNode; Level : Byte) : Integer;
    function NextNode(ACurNode : PTrieBranchNode; ALevel, AChildIndex : Byte) : Pointer; inline;
    function GetItem(Index: Integer): Pointer;
    function IteratorBacktrack(var AIterator : TTrieIterator) : Boolean;
    procedure PackNode(var AIterator : TTrieIterator; const ChildrenBackup : array of Pointer);
    procedure FreeTrieBranchNodeArray(const Arr : PTrieNodeArray; ChildrenCount, Level : Byte);
    procedure FreeTrieLeafNodeArray(const Arr : PTrieLeafNodeArray; ChildrenCount, Level : Byte);
    procedure CleanLowBitsIteratorLastResult(var AIterator : TTrieIterator; ATrieDepth : Byte); inline;
    function TrieDepthToHashSize(ATrieDepth: Byte): Byte; inline;
  protected
    procedure InitLeaf(var Leaf);
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
    procedure RaiseTrieDepthError;
    property Items[Index: Integer]: Pointer read GetItem;
    property RandomAccessMode : TTrieRandomAccessMode read FRandomAccessMode write FRandomAccessMode;
    property TrieDepth: Byte read FTrieDepth;
  public
    constructor Create(ATrieDepth: Byte; ALeafSize: Cardinal = sizeof(TTrieLeafNode));
    destructor Destroy; override;
    procedure Clear; override;
    function Add(const Data; out Node : PTrieLeafNode; out WasBusy : Boolean) : Boolean; override;
    procedure Remove(const Data); override;
    function Find(const Data; out ANode: PTrieLeafNode; out AChildIndex: Byte;
                  LeafHasChildIndex: Boolean): Boolean; override;
    function GetObjectFromIterator(const _AIterator): Pointer; override;
    procedure InitIterator(out _AIterator); override;
    function Next(var _AIterator; ADepth: Byte = 0): Boolean; override;
    procedure Pack; override;
  end;

implementation

resourcestring
  STR_RANDOMACCESSNOTENABLED = 'Random access not enabled';
  STR_RANDOMACCESSENABLEDONLYFORSEQUENTIALACCESS = 'Random access enabled only for sequential access';
  STR_INDEXOUTOFBOUNDS = 'Index out of bounds';
  STR_TRIEDEPTHERROR = 'Only possible values for trie depth are 4, 8 and 16';
  STR_ITERATORATEND = 'Iterator reached the end of the trie unexpectedly';

{ TTrie }

constructor TTrie.Create(ATrieDepth: Byte; ALeafSize: Cardinal = sizeof(
    TTrieLeafNode));
begin
  inherited Create(TrieDepthToHashSize(ATrieDepth), ALeafSize);
  FTrieBranchNodeAllocator := TFixedBlockHeap.Create(sizeof(TTrieBranchNode), _64KB div sizeof(TTrieBranchNode));
  FRoot := NewTrieBranchNode();
  FLastIndex := -1;
  if (ATrieDepth < 4) or (ATrieDepth > 64) then
    RaiseTrieDepthError;
  FTrieDepth := ATrieDepth;
  FLastMidBranchNode := FTrieDepth - 3;
end;

destructor TTrie.Destroy;
begin
  FreeTrieNode(@FRoot^.Base, 0);
  FTrieBranchNodeAllocator.Free;
  inherited Destroy;
end;

function TTrie.NewTrieBranchNode : PTrieBranchNode;
begin
  Result := FTrieBranchNodeAllocator.Alloc;
  Result^.Base.Busy := 0;
  Result^.Base.ChildrenCount := 0;
  Result^.Children := nil;
  Result^.ChildIndex := 0;
end;

procedure TTrie.FreeTrieNode(ANode: PTrieBaseNode; Level: Byte);
begin
  inherited;
  if Level in [0..FLastMidBranchNode] then
    FreeTrieBranchNodeArray(PTrieNodeArray(PTrieBranchNode(ANode)^.Children), ANode^.ChildrenCount, Level + 1)
  else if Level = FLastMidBranchNode + 1 then
    FreeTrieLeafNodeArray(PTrieLeafNodeArray(PTrieBranchNode(ANode)^.Children), ANode^.ChildrenCount, Level + 1);
  if Level < FTrieDepth - 1 then
    trieAllocators.DeAlloc(ANode);
end;

procedure TTrie.RaiseTrieDepthError;
begin
  raise ETrie.Create(STR_TRIEDEPTHERROR);
end;

function TTrie.AddChild(ANode: PTrieBranchNode; Level: Byte
  ): Integer;
begin
  if Level <= FLastMidBranchNode then
  begin
    ReallocMem(ANode^.Children, (ANode^.Base.ChildrenCount + 1) * sizeof(Pointer));
    PTrieNodeArray(ANode^.Children)^[ANode^.Base.ChildrenCount] := NewTrieBranchNode();
  end
  else
  begin
    ReallocMem(ANode^.Children, Cardinal(ANode^.Base.ChildrenCount + 1) * LeafSize);
    InitLeaf(PTrieLeafNode(@PTrieLeafNodeArray(ANode^.Children)^[ANode^.Base.ChildrenCount * LeafSize])^);
  end;
  Result := ANode^.Base.ChildrenCount;
  inc(ANode^.Base.ChildrenCount);
end;

function TTrie.Find(const Data; out ANode: PTrieLeafNode; out AChildIndex:
    Byte; LeafHasChildIndex: Boolean): Boolean;
var
  i, BitFieldIndex, ATrieDepth : Byte;
  CurNode : PTrieBaseNode;
begin
  ANode := nil;
  Result := False;
  AChildIndex := 0;
  CurNode := @FRoot^.Base;
  ATrieDepth := FTrieDepth;
  for i := 0 to ATrieDepth - 1 do
  begin
    BitFieldIndex := GetBitFieldIndex(Data, i);
    if not GetBusyIndicator(CurNode, BitFieldIndex) then
      exit;
    if (i < ATrieDepth - 1) or LeafHasChildIndex then
      AChildIndex := GetChildIndex(PTrieBranchNode(CurNode), BitFieldIndex);
    if i = ATrieDepth - 1 then
      break;
    CurNode := NextNode(PTrieBranchNode(CurNode), i, AChildIndex);
  end;
  ANode := PTrieLeafNode(CurNode);
  Result := True;
end;

function TTrie.NextNode(ACurNode: PTrieBranchNode; ALevel,
  AChildIndex: Byte): Pointer;
begin
  if ALevel <= FLastMidBranchNode then
    Result := PTrieNodeArray(ACurNode^.Children)^[AChildIndex]
  else Result := @PTrieLeafNodeArray(ACurNode^.Children)^[AChildIndex * LeafSize];
end;

function TTrie.GetItem(Index: Integer): Pointer;
begin
  if FRandomAccessMode = ramDisabled then
    raise ETrieRandomAccess.Create(STR_RANDOMACCESSNOTENABLED);
  if (Index < 0) or (Index >= FCount) then
    raise ETrieRandomAccess.Create(STR_INDEXOUTOFBOUNDS);
  If FLastIndex = -1 then
    InitIterator(FRandomAccessIterator)
  else if (FRandomAccessMode = ramSequential) and ((Index = 0) or (not ((Index - FLastIndex) in [0..1]))) then
    raise ETrieRandomAccess.Create(STR_RANDOMACCESSENABLEDONLYFORSEQUENTIALACCESS)
  else if Index < FLastIndex then
  begin
    FLastIndex := -1;
    InitIterator(FRandomAccessIterator);
  end;
  Result := @FRandomAccessIterator.Base.LastResult64;
  if Index = FLastIndex then
    exit;
  repeat
    if not Next(FRandomAccessIterator) then
      raise ETrieRandomAccess.Create(STR_ITERATORATEND);
    inc(FLastIndex);
  until FLastIndex >= Index;
end;

procedure TTrie.Clear;
begin
  FreeTrieNode(@FRoot^.Base, 0);
  FCount := 0;
  FRoot := NewTrieBranchNode();
end;

function TTrie.Add(const Data; out Node: PTrieLeafNode; out WasBusy: Boolean
  ): Boolean;
var
  i, BitFieldIndex, ChildIndex, ATrieDepth : Byte;
  CurNode : PTrieBaseNode;
begin
  {$IFNDEF FPC}
  ChildIndex := 0;
  {$ENDIF}
  Result := False;
  CurNode := @FRoot^.Base;
  ATrieDepth := FTrieDepth;
  for i := 0 to ATrieDepth - 1 do
  begin
    BitFieldIndex := GetBitFieldIndex(Data, i);
    if i < ATrieDepth - 1 then
      if not GetBusyIndicator(CurNode, BitFieldIndex) then
      begin
        ChildIndex := AddChild(PTrieBranchNode(CurNode), i);
        SetChildIndex(PTrieBranchNode(CurNode), BitFieldIndex, ChildIndex);
        SetBusyIndicator(CurNode, BitFieldIndex, True);
        if i = ATrieDepth - 2 then
          Result := True;
      end
      else ChildIndex := GetChildIndex(PTrieBranchNode(CurNode), BitFieldIndex)
    else
    begin
      WasBusy := GetBusyIndicator(CurNode, BitFieldIndex);
      SetBusyIndicator(CurNode, BitFieldIndex, True);
      Node := PTrieLeafNode(CurNode);
      break;
    end;
    CurNode := NextNode(PTrieBranchNode(CurNode), i, ChildIndex);
  end;
  if not WasBusy then
    inc(FCount);
end;

procedure TTrie.Remove(const Data);
var
  ChildIndex : Byte;
  Node : PTrieLeafNode;
begin
  if Find(Data, Node, ChildIndex, False) then
  begin
    SetBusyIndicator(@Node^.Base, GetBitFieldIndex(Data, FTrieDepth - 1), False);
    dec(FCount);
  end;
end;

procedure TTrie.InitIterator(out _AIterator);
var
  i, ATrieDepth: Byte;
  AIterator : TTrieIterator absolute _AIterator;
begin
  inherited InitIterator(AIterator.Base);
  ATrieDepth := FTrieDepth;
  AIterator.Level := 0;
  for i := 0 to ATrieDepth - 1 do
  begin
    AIterator.BreadCrumbs[i] := 0;
    AIterator.NodeStack[i] := nil;
  end;
end;

procedure TTrie.Pack;
var
  BitFieldIndex, ChildIndex : Integer;
  AIterator : TTrieIterator;
  PackingNode : Boolean;
  ChildrenPointersBackup : array of Pointer;
  procedure BackupChildren;
  var
    i, _ChildIndex : Integer;
  begin
    for i := low(ChildrenPointersBackup) to high(ChildrenPointersBackup) do
      ChildrenPointersBackup[i] := nil;
    for i := 0 to BitFieldIndex - 1 do
    begin
      if GetBusyIndicator(AIterator.NodeStack[AIterator.Level], i) then
      begin
        _ChildIndex := GetChildIndex(PTrieBranchNode(AIterator.NodeStack[AIterator.Level]), i);
        ChildrenPointersBackup[i] := PTrieNodeArray(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children)^[_ChildIndex];
      end;
    end;
  end;
begin
  SetLength(ChildrenPointersBackup, ChildrenPerBucket);
  InitIterator(AIterator);
  while Next(AIterator, FTrieDepth - 1) do
  begin
    while AIterator.Level >= 0 do
    begin
      PackingNode := False;
      for BitFieldIndex := 0 to ChildrenPerBucket - 1 do
        if GetBusyIndicator(AIterator.NodeStack[AIterator.Level], BitFieldIndex) then
        begin
          ChildIndex := GetChildIndex(PTrieBranchNode(AIterator.NodeStack[AIterator.Level]), BitFieldIndex);
          if AIterator.Level = FLastMidBranchNode + 1 then
            if PTrieLeafNode(@PTrieLeafNodeArray(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children)^[ChildIndex * Integer(LeafSize)])^.Base.Busy = 0 then
            begin
              PackingNode := True;
              dec(AIterator.NodeStack[AIterator.Level]^.ChildrenCount);
              SetBusyIndicator(AIterator.NodeStack[AIterator.Level], BitFieldIndex, False);
              FreeTrieNode(@PTrieLeafNodeArray(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children)^[ChildIndex * Integer(LeafSize)], AIterator.Level + 1);
            end
            else { keep going, there's busy nodes on Children }
          else if PTrieNodeArray(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children)^[ChildIndex]^.Base.Busy = 0 then
          begin
            if not PackingNode then
            begin
              BackupChildren;
              PackingNode := True;
            end;
            dec(AIterator.NodeStack[AIterator.Level]^.ChildrenCount);
            SetBusyIndicator(AIterator.NodeStack[AIterator.Level], BitFieldIndex, False);
            FreeTrieNode(@PTrieNodeArray(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children)^[ChildIndex]^.Base, AIterator.Level + 1);
          end
          else if PackingNode then
            ChildrenPointersBackup[BitFieldIndex] := PTrieNodeArray(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children)^[ChildIndex];
        end;
      if PackingNode then
        PackNode(AIterator, ChildrenPointersBackup);
      dec(AIterator.Level);
    end;
    AIterator.Level := 0;
  end;
end;

function TTrie.Next(var _AIterator; ADepth: Byte = 0): Boolean;
var
  ATrieDepth : Byte;
  AIterator : TTrieIterator absolute _AIterator;
begin
  if AIterator.Base.AtEnd then
  begin
    Result := False;
    exit;
  end;
  if ADepth = 0 then
    ATrieDepth := FTrieDepth
  else ATrieDepth := ADepth;
  if AIterator.Level = 0 then
  begin
    AIterator.NodeStack[0] := @FRoot^.Base;
    AIterator.Base.LastResult64 := 0;
  end
  else CleanLowBitsIteratorLastResult(AIterator, ATrieDepth);
  repeat
    while AIterator.BreadCrumbs[AIterator.Level] < ChildrenPerBucket do
    begin
      if GetBusyIndicator(AIterator.NodeStack[AIterator.Level], AIterator.BreadCrumbs[AIterator.Level] ) then
      begin
        case ATrieDepth of
          1..TrieDepth16Bits : AIterator.Base.LastResult16 := AIterator.Base.LastResult16 or Word(AIterator.BreadCrumbs[AIterator.Level]);
          TrieDepth16Bits + 1..TrieDepth32Bits : AIterator.Base.LastResult32 := AIterator.Base.LastResult32 or Integer(AIterator.BreadCrumbs[AIterator.Level]);
          TrieDepth32Bits + 1..TrieDepth64Bits : AIterator.Base.LastResult64 := AIterator.Base.LastResult64 or _Int64(AIterator.BreadCrumbs[AIterator.Level]);
          else RaiseTrieDepthError;
        end;
        inc(AIterator.Level);
        if AIterator.Level >= ATrieDepth then
        begin
          dec(AIterator.Level);
          inc(AIterator.BreadCrumbs[AIterator.Level]);
          Result := True;
          exit;
        end;
        case ATrieDepth of
          1..TrieDepth16Bits : AIterator.Base.LastResult16 := AIterator.Base.LastResult16 shl BitsForChildIndexPerBucket;
          TrieDepth16Bits + 1..TrieDepth32Bits : AIterator.Base.LastResult32 := AIterator.Base.LastResult32 shl BitsForChildIndexPerBucket;
          TrieDepth32Bits + 1..TrieDepth64Bits : AIterator.Base.LastResult64 := AIterator.Base.LastResult64 shl BitsForChildIndexPerBucket;
          else RaiseTrieDepthError;
        end;
        AIterator.NodeStack[AIterator.Level] := NextNode(PTrieBranchNode(AIterator.NodeStack[AIterator.Level - 1]), AIterator.Level - 1,
                                                         GetChildIndex(PTrieBranchNode(AIterator.NodeStack[AIterator.Level - 1]),
                                                         AIterator.BreadCrumbs[AIterator.Level - 1]));
        break;
      end
      else inc(AIterator.BreadCrumbs[AIterator.Level]);
    end;
    if AIterator.BreadCrumbs[AIterator.Level]  >= ChildrenPerBucket then
      if not IteratorBacktrack(AIterator) then
        break;
  until False;
  AIterator.Base.AtEnd := True;
  Result := False;
end;

function TTrie.IteratorBacktrack(var AIterator: TTrieIterator): Boolean;
begin
  AIterator.BreadCrumbs[AIterator.Level]  := 0;
  dec(AIterator.Level);
  if AIterator.Level >= 0 then
    inc(AIterator.BreadCrumbs[AIterator.Level])
  else
  begin
    Result := False;
    exit;
  end;
  case FTrieDepth of
    1..TrieDepth16Bits : AIterator.Base.LastResult16 := AIterator.Base.LastResult16 shr BitsForChildIndexPerBucket;
    TrieDepth16Bits + 1..TrieDepth32Bits : AIterator.Base.LastResult32 := AIterator.Base.LastResult32 shr BitsForChildIndexPerBucket;
    TrieDepth32Bits + 1..TrieDepth64Bits : AIterator.Base.LastResult64 := AIterator.Base.LastResult64 shr BitsForChildIndexPerBucket;
    else RaiseTrieDepthError;
  end;
  CleanLowBitsIteratorLastResult(AIterator, FTrieDepth);
  Result := True;
end;

procedure TTrie.PackNode(var AIterator: TTrieIterator;
  const ChildrenBackup: array of Pointer);
var
  j, BitFieldIndex : Integer;
begin
  if AIterator.Level <= FLastMidBranchNode then
  begin
    if AIterator.NodeStack[AIterator.Level]^.ChildrenCount > 0 then
    begin
      ReallocMem(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children, AIterator.NodeStack[AIterator.Level]^.ChildrenCount * sizeof(Pointer));
      j := 0;
      PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.ChildIndex := 0;
      for BitFieldIndex := 0 to ChildrenPerBucket - 1 do
        if GetBusyIndicator(AIterator.NodeStack[AIterator.Level], BitFieldIndex) then
        begin
          PTrieNodeArray(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children)^[j] := ChildrenBackup[BitFieldIndex];
          SetChildIndex(PTrieBranchNode(AIterator.NodeStack[AIterator.Level]), BitFieldIndex, j);
          inc(j);
        end;
    end
    else
    begin
      FreeMem(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children);
      PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children := nil;
      inc(AIterator.BreadCrumbs[AIterator.Level]);
    end;
  end
  else
  begin
    if AIterator.NodeStack[AIterator.Level]^.ChildrenCount <= 0 then
    begin
      FreeMem(PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children);
      PTrieBranchNode(AIterator.NodeStack[AIterator.Level])^.Children := nil;
    end;
    inc(AIterator.BreadCrumbs[AIterator.Level]);
  end;
end;

procedure TTrie.FreeTrieBranchNodeArray(const Arr: PTrieNodeArray;
  ChildrenCount, Level: Byte);
var
  i : SmallInt;
begin
  for i := 0 to ChildrenCount - 1 do
    FreeTrieNode(@PTrieBranchNode(Arr^[i])^.Base, Level);
  FreeMem(Arr);
end;

procedure TTrie.FreeTrieLeafNodeArray(const Arr: PTrieLeafNodeArray;
  ChildrenCount, Level: Byte);
var
  i : Integer;
begin
  for i := 0 to ChildrenCount - 1 do
    FreeTrieNode(@PTrieLeafNode(@Arr^[i * Integer(LeafSize)])^.Base, Level);
  FreeMem(Arr);
end;

procedure TTrie.CleanLowBitsIteratorLastResult(var AIterator: TTrieIterator;
  ATrieDepth: Byte);
begin
  case ATrieDepth of
    1..TrieDepth16Bits : AIterator.Base.LastResult16 := AIterator.Base.LastResult16 and not Word(BucketMask);
    TrieDepth16Bits + 1..TrieDepth32Bits : AIterator.Base.LastResult32 := AIterator.Base.LastResult32 and not Integer(BucketMask);
    TrieDepth32Bits + 1..TrieDepth64Bits : AIterator.Base.LastResult64 := AIterator.Base.LastResult64 and not _Int64(BucketMask);
    else RaiseTrieDepthError;
  end;
end;

function TTrie.GetObjectFromIterator(const _AIterator): Pointer;
var
  AIterator : TTrieIterator absolute _AIterator;
begin
  Result := AIterator.NodeStack[AIterator.Level];
end;

procedure TTrie.InitLeaf(var Leaf);
begin
  TTrieLeafNode(Leaf).Base.Busy := 0;
  TTrieLeafNode(Leaf).Base.ChildrenCount := 0;
  inherited;
end;

function TTrie.TrieDepthToHashSize(ATrieDepth: Byte): Byte;
begin
  Result := ATrieDepth * BitsForChildIndexPerBucket;
end;

end.

