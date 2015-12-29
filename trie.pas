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
*)

unit Trie;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  BitsPerByte = 8;
  BitsForChildIndexPerBucket = 4;
  BucketMask = $F;
  MaxTrieDepth = sizeof(Int64) * BitsPerByte div BitsForChildIndexPerBucket;
  ChildrenPerBucket = BitsForChildIndexPerBucket * BitsForChildIndexPerBucket;
  TrieDepth16Bits = 4;
  TrieDepth32Bits = 8;
  TrieDepth64Bits = 16;

type
  PTrieBaseNode = ^TTrieBaseNode;
  TTrieBaseNode = record
    ChildrenCount : Word;
    Busy : Word;
  end;

  PTrieBranchNode = ^TTrieBranchNode;

  TTrieNodeArray = array[0..ChildrenPerBucket - 1] of PTrieBranchNode;
  PTrieNodeArray = ^TTrieNodeArray;

  TTrieBranchNode = record
    Base : TTrieBaseNode;
    ChildIndex : Int64;
    Children : Pointer;
  end;

  PTrieLeafNode = ^TTrieLeafNode;
  TTrieLeafNode = record
    Base : TTrieBaseNode;
  end;

  TTrieLeafNodeArray = array[0..MaxInt - 1] of Byte;
  PTrieLeafNodeArray = ^TTrieLeafNodeArray;

  TTrieStats = record
    NodeCount : Integer;
    TotalMemAlloced : Int64;
  end;

  TTrieIterator = record
    AtEnd : Boolean;
    Level : SmallInt;
    BreadCrumbs : array[0..MaxTrieDepth - 1] of SmallInt;
    ANodeStack : array[0..MaxTrieDepth - 1] of PTrieBaseNode;
    case Integer of
      TrieDepth16Bits : (LastResult16 : Word;);
      TrieDepth32Bits : (LastResult32 : Integer;);
      TrieDepth64Bits : (LastResult64 : Int64;);
      0               : (LastResultPtr : Pointer;);
  end;

  { TTrie }

  TTrieRandomAccessMode = (ramDisabled, ramSequential, ramFull);

  ETrie = class(Exception);
  ETrieDuplicate = class(ETrie);
  ETrieRandomAccess = class(ETrie);

  TTrie = class
  private
    FRandomAccessMode: TTrieRandomAccessMode;
    FRoot : PTrieBranchNode;
    FAllowDuplicates : Boolean;
    FStats : TTrieStats;
    FCount : Integer;
    FRandomAccessIterator : TTrieIterator;
    FLastIndex : Integer;
    FTrieDepth : Byte;
    FLastMidBranchNode : Byte;
    function NewTrieBranchNode : PTrieBranchNode;
    function AddChild(ANode : PTrieBranchNode; Level : Byte) : Integer;
    function GetBitFieldIndex(const Data; Level : Byte) : Byte;
    function GetChildIndex(ANode : PTrieBranchNode; BitFieldIndex : Byte) : Byte; inline;
    procedure SetChildIndex(ANode : PTrieBranchNode; BitFieldIndex, ChildIndex : Byte); inline;
    function GetBusyIndicator(ANode : PTrieBaseNode; BitFieldIndex : Byte) : Boolean; inline;
    procedure SetBusyIndicator(ANode : PTrieBaseNode; BitFieldIndex : Byte; Value : Boolean); inline;
    function InternalFind(const Data; out ANode : PTrieLeafNode; out AChildIndex : Byte) : Boolean;
    function NextNode(ACurNode : PTrieBranchNode; ALevel, AChildIndex : Byte) : Pointer; inline;
    function GetItem(Index: Integer): Pointer;
    function IteratorBacktrack(var AIterator : TTrieIterator) : Boolean;
    procedure PackNode(var AIterator : TTrieIterator; const ChildrenBackup : array of Pointer);
    procedure FreeTrieBranchNodeArray(const Arr : PTrieNodeArray; ChildrenCount, Level : Byte);
    procedure FreeTrieLeafNodeArray(const Arr : PTrieLeafNodeArray; ChildrenCount, Level : Byte);
  protected
    procedure Add(const Data);
    function Find(const Data) : Boolean;
    procedure Remove(const Data);
    function Next(var AIterator : TTrieIterator; ADepth : Byte = 0) : Boolean;
    function LeafSize : Cardinal; virtual;
    procedure InitLeaf(var Leaf); virtual;
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte); virtual;
    property Items[Index: Integer]: Pointer read GetItem;
    property TrieDepth : Byte read FTrieDepth;
  public
    constructor Create(ATrieDepth : Byte);
    destructor Destroy; override;
    procedure Clear; virtual;
    procedure InitIterator(out AIterator : TTrieIterator);
    procedure Pack;
    property AllowDuplicates : Boolean read FAllowDuplicates write FAllowDuplicates;
    property Count : Integer read FCount;
    property RandomAccessMode : TTrieRandomAccessMode read FRandomAccessMode write FRandomAccessMode;
    property Stats : TTrieStats read FStats;
  end;

implementation

const
  ChildIndexShiftArray16 : array[0..TrieDepth16Bits - 1] of Byte =
    (12, 8, 4, 0);
  ChildIndexShiftArray32 : array[0..TrieDepth32Bits - 1] of Byte =
    (28, 24, 20, 16, 12, 8, 4, 0);
  ChildIndexShiftArray64 : array[0..TrieDepth64Bits - 1] of Byte =
    (60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12, 8, 4, 0);
  CleanChildIndexMask : array[0..ChildrenPerBucket - 1] of Int64 =
    ($FFFFFFFFFFFFFFF0, $FFFFFFFFFFFFFF0F, $FFFFFFFFFFFFF0FF, $FFFFFFFFFFFF0FFF,
     $FFFFFFFFFFF0FFFF, $FFFFFFFFFF0FFFFF, $FFFFFFFFF0FFFFFF, $FFFFFFFF0FFFFFFF,
     $FFFFFFF0FFFFFFFF, $FFFFFF0FFFFFFFFF, $FFFFF0FFFFFFFFFF, $FFFF0FFFFFFFFFFF,
     $FFF0FFFFFFFFFFFF, $FF0FFFFFFFFFFFFF, $F0FFFFFFFFFFFFFF, $0FFFFFFFFFFFFFFF);

resourcestring
  STR_DUPLICATESNOTALLOWED = 'Duplicates not allowed';
  STR_RANDOMACCESSNOTENABLED = 'Random access not enabled';
  STR_RANDOMACCESSENABLEDONLYFORSEQUENTIALACCESS = 'Random access enabled only for sequential access';
  STR_INDEXOUTOFBOUNDS = 'Index out of bounds';
  STR_TRIEDEPTHERROR = 'Only possible values for trie depth are 4, 8 and 16';
  STR_ITERATORATEND = 'Iterator reached the end of the trie unexpectedly';

{ TTrie }

constructor TTrie.Create(ATrieDepth: Byte);
begin
  inherited Create;
  FRoot := NewTrieBranchNode();
  FLastIndex := -1;
  if (ATrieDepth <> TrieDepth32Bits) and (ATrieDepth <> TrieDepth64Bits) and
     (ATrieDepth <> TrieDepth16Bits) then
    raise ETrie.Create(STR_TRIEDEPTHERROR);
  FTrieDepth := ATrieDepth;
  FLastMidBranchNode := FTrieDepth - 3;
end;

destructor TTrie.Destroy;
begin
  FreeTrieNode(@FRoot^.Base, 0);
  inherited Destroy;
end;

function TTrie.NewTrieBranchNode : PTrieBranchNode;
begin
  GetMem(Result, sizeof(TTrieBranchNode));
  Result^.Base.Busy := 0;
  Result^.Base.ChildrenCount := 0;
  Result^.Children := nil;
  Result^.ChildIndex := 0;
  inc(FStats.NodeCount);
  inc(FStats.TotalMemAlloced, sizeof(TTrieBranchNode));
end;

procedure TTrie.FreeTrieNode(ANode: PTrieBaseNode; Level: Byte);
begin
  if Level in [0..FLastMidBranchNode] then
    FreeTrieBranchNodeArray(PTrieNodeArray(PTrieBranchNode(ANode)^.Children), ANode^.ChildrenCount, Level + 1)
  else if Level = FLastMidBranchNode + 1 then
    FreeTrieLeafNodeArray(PTrieLeafNodeArray(PTrieBranchNode(ANode)^.Children), ANode^.ChildrenCount, Level + 1);
  if Level < FTrieDepth - 1 then
  begin
    FreeMem(ANode);
    dec(FStats.TotalMemAlloced, sizeof(TTrieBranchNode));
    dec(FStats.NodeCount);
  end;
end;

function TTrie.AddChild(ANode: PTrieBranchNode; Level: Byte
  ): Integer;
  procedure ReallocArray(var Arr : Pointer; NewCount, ObjSize : Cardinal);
  begin
    ReallocMem(Arr, NewCount * ObjSize);
    inc(FStats.TotalMemAlloced, ObjSize);
  end;
begin
  if Level <= FLastMidBranchNode then
  begin
    ReallocArray(ANode^.Children, ANode^.Base.ChildrenCount + 1, sizeof(Pointer));
    PTrieNodeArray(ANode^.Children)^[ANode^.Base.ChildrenCount] := NewTrieBranchNode();
  end
  else
  begin
    ReallocArray(ANode^.Children, ANode^.Base.ChildrenCount + 1, LeafSize);
    InitLeaf(PTrieLeafNode(@PTrieLeafNodeArray(ANode^.Children)^[ANode^.Base.ChildrenCount * LeafSize])^);
  end;
  Result := ANode^.Base.ChildrenCount;
  inc(ANode^.Base.ChildrenCount);
end;

function TTrie.GetBitFieldIndex(const Data; Level: Byte): Byte;
begin
  case FTrieDepth of
    TrieDepth16Bits : Result := (Word(Data) shr ChildIndexShiftArray16[Level]) and BucketMask;
    TrieDepth32Bits : Result := (Integer(Data) shr ChildIndexShiftArray32[Level]) and BucketMask;
    else Result := (Int64(Data) shr ChildIndexShiftArray64[Level]) and BucketMask;
  end;
end;

function TTrie.GetChildIndex(ANode: PTrieBranchNode; BitFieldIndex: Byte
  ): Byte;
begin
  Result := (ANode^.ChildIndex shr (Int64(BitFieldIndex) * BitsForChildIndexPerBucket)) and BucketMask;
end;

procedure TTrie.SetChildIndex(ANode: PTrieBranchNode; BitFieldIndex,
  ChildIndex: Byte);
begin
  ANode^.ChildIndex := ANode^.ChildIndex and CleanChildIndexMask[BitFieldIndex];
  ANode^.ChildIndex := ANode^.ChildIndex or (Int64(ChildIndex) shl (BitFieldIndex * BitsForChildIndexPerBucket));
end;

function TTrie.GetBusyIndicator(ANode: PTrieBaseNode;
  BitFieldIndex: Byte): Boolean;
begin
  Result := (ANode^.Busy and (Word(1) shl BitFieldIndex)) <> 0;
end;

procedure TTrie.SetBusyIndicator(ANode: PTrieBaseNode;
  BitFieldIndex: Byte; Value: Boolean);
begin
  if Value then
    ANode^.Busy := ANode^.Busy or (Word(1) shl BitFieldIndex)
  else ANode^.Busy := ANode^.Busy and not (Word(1) shl BitFieldIndex);
end;

function TTrie.InternalFind(const Data; out ANode: PTrieLeafNode; out
  AChildIndex: Byte): Boolean;
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
    if i = ATrieDepth - 1 then
      break;
    AChildIndex := GetChildIndex(PTrieBranchNode(CurNode), BitFieldIndex);
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
  Result := @FRandomAccessIterator.LastResult64;
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
  FStats.TotalMemAlloced := 0;
  FStats.NodeCount := 0;
  FCount := 0;
  FRoot := NewTrieBranchNode();
end;

procedure TTrie.Add(const Data);
var
  i, BitFieldIndex, ChildIndex, ATrieDepth : Byte;
  CurNode : PTrieBaseNode;
begin
  CurNode := @FRoot^.Base;
  ATrieDepth := FTrieDepth;
  for i := 0 to ATrieDepth - 1 do
  begin
    BitFieldIndex := GetBitFieldIndex(Data, i);
    if (not FAllowDuplicates) and ( i = ATrieDepth - 1) and
       GetBusyIndicator(CurNode, BitFieldIndex) then
      raise ETrieDuplicate.Create(STR_DUPLICATESNOTALLOWED);
    if i < ATrieDepth - 1 then
      if not GetBusyIndicator(CurNode, BitFieldIndex) then
      begin
        ChildIndex := AddChild(PTrieBranchNode(CurNode), i);
        SetChildIndex(PTrieBranchNode(CurNode), BitFieldIndex, ChildIndex);
        SetBusyIndicator(CurNode, BitFieldIndex, True);
      end
      else ChildIndex := GetChildIndex(PTrieBranchNode(CurNode), BitFieldIndex)
    else
    begin
      SetBusyIndicator(CurNode, BitFieldIndex, True);
      break;
    end;
    CurNode := NextNode(PTrieBranchNode(CurNode), i, ChildIndex);
  end;
  inc(FCount);
end;

function TTrie.Find(const Data): Boolean;
var
  DummyChildIndex : Byte;
  DummyNode : PTrieLeafNode;
begin
  Result := InternalFind(Data, DummyNode, DummyChildIndex);
end;

procedure TTrie.Remove(const Data);
var
  ChildIndex : Byte;
  Node : PTrieLeafNode;
begin
  if InternalFind(Data, Node, ChildIndex) then
  begin
    SetBusyIndicator(@Node^.Base, GetBitFieldIndex(Data, FTrieDepth - 1), False);
    dec(FCount);
  end;
end;

procedure TTrie.InitIterator(out AIterator: TTrieIterator);
var
  i, ATrieDepth: Byte;
begin
  ATrieDepth := FTrieDepth;
  AIterator.AtEnd := False;
  AIterator.Level := 0;
  AIterator.LastResult64 := 0;
  for i := 0 to ATrieDepth - 1 do
  begin
    AIterator.BreadCrumbs[i] := 0;
    AIterator.ANodeStack[i] := nil;
  end;
end;

procedure TTrie.Pack;
var
  BitFieldIndex, ChildIndex : Integer;
  AIterator : TTrieIterator;
  NodePacked : Boolean;
  ChildrenBackup : array of Pointer;
  procedure BackupChildren;
  var
    i, ChildIndex : Integer;
  begin
    for i := low(ChildrenBackup) to high(ChildrenBackup) do
      ChildrenBackup[i] := nil;
    for i := 0 to BitFieldIndex - 1 do
    begin
      if GetBusyIndicator(AIterator.ANodeStack[AIterator.Level], i) then
      begin
        ChildIndex := GetChildIndex(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level]), i);
        ChildrenBackup[i] := PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex];
      end;
    end;
  end;
begin
  SetLength(ChildrenBackup, ChildrenPerBucket);
  InitIterator(AIterator);
  while Next(AIterator, FTrieDepth - 1) do
  begin
    while AIterator.Level >= 0 do
    begin
      NodePacked := False;
      for BitFieldIndex := 0 to ChildrenPerBucket - 1 do
        if GetBusyIndicator(AIterator.ANodeStack[AIterator.Level], BitFieldIndex) then
        begin
          ChildIndex := GetChildIndex(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level]), BitFieldIndex);
          if AIterator.Level = FLastMidBranchNode + 1 then
            if PTrieLeafNode(@PTrieLeafNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex * Integer(LeafSize)])^.Base.Busy = 0 then
            begin
              NodePacked := True;
              SetBusyIndicator(AIterator.ANodeStack[AIterator.Level], BitFieldIndex, False);
              FreeTrieNode(@PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex * Integer(LeafSize)]^.Base, AIterator.Level + 1);
              dec(AIterator.ANodeStack[AIterator.Level]^.ChildrenCount);
            end
            else { keep going, there's busy nodes on Children }
          else if PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex]^.Base.Busy = 0 then
          begin
            if not NodePacked then
            begin
              BackupChildren;
              NodePacked := True;
            end;
            dec(AIterator.ANodeStack[AIterator.Level]^.ChildrenCount);
            SetBusyIndicator(AIterator.ANodeStack[AIterator.Level], BitFieldIndex, False);
            FreeTrieNode(@PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex]^.Base, AIterator.Level + 1);
          end
          else if NodePacked then
            ChildrenBackup[BitFieldIndex] := PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex];
        end;
      if NodePacked then
        PackNode(AIterator, ChildrenBackup);
      dec(AIterator.Level);
    end;
    AIterator.Level := 0;
  end;
end;

function TTrie.Next(var AIterator: TTrieIterator; ADepth: Byte = 0): Boolean;
var
  ATrieDepth : Byte;
begin
  if AIterator.AtEnd then
  begin
    Result := False;
    exit;
  end;
  if ADepth = 0 then
    ATrieDepth := FTrieDepth
  else ATrieDepth := ADepth;
  if AIterator.Level = 0 then
  begin
    AIterator.ANodeStack[0] := @FRoot^.Base;
    AIterator.LastResult64 := 0;
  end;
  repeat
    while AIterator.BreadCrumbs[AIterator.Level] < ChildrenPerBucket do
    begin
      if GetBusyIndicator(AIterator.ANodeStack[AIterator.Level], AIterator.BreadCrumbs[AIterator.Level] ) then
      begin
        case ATrieDepth of
          TrieDepth16Bits : AIterator.LastResult16 := AIterator.LastResult16 or AIterator.BreadCrumbs[AIterator.Level];
          TrieDepth32Bits : AIterator.LastResult32 := AIterator.LastResult32 or AIterator.BreadCrumbs[AIterator.Level];
          else AIterator.LastResult64 := AIterator.LastResult64 or AIterator.BreadCrumbs[AIterator.Level];
        end;
        inc(AIterator.Level);
        if AIterator.Level >= ATrieDepth then
        begin
          inc(AIterator.BreadCrumbs[AIterator.Level - 1]);
          dec(AIterator.Level);
          Result := True;
          exit;
        end;
        case ATrieDepth of
          TrieDepth16Bits : AIterator.LastResult16 := AIterator.LastResult16 shl BitsForChildIndexPerBucket;
          TrieDepth32Bits : AIterator.LastResult32 := AIterator.LastResult32 shl BitsForChildIndexPerBucket;
          else AIterator.LastResult64 := AIterator.LastResult64 shl BitsForChildIndexPerBucket;
        end;
        AIterator.ANodeStack[AIterator.Level] := NextNode(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level - 1]), AIterator.Level - 1,
                                                          GetChildIndex(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level - 1]),
                                                          AIterator.BreadCrumbs[AIterator.Level - 1]));
        break;
      end
      else inc(AIterator.BreadCrumbs[AIterator.Level] );
    end;
    if AIterator.BreadCrumbs[AIterator.Level]  >= ChildrenPerBucket then
      if not IteratorBacktrack(AIterator) then
        break;
  until False;
  AIterator.AtEnd := True;
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
    TrieDepth16Bits :
    begin
      AIterator.LastResult16 := AIterator.LastResult16 shr BitsForChildIndexPerBucket;
      AIterator.LastResult16 := AIterator.LastResult16 and not Word(BucketMask);
    end;
    TrieDepth32Bits :
    begin
      AIterator.LastResult32 := AIterator.LastResult32 shr BitsForChildIndexPerBucket;
      AIterator.LastResult32 := AIterator.LastResult32 and not Integer(BucketMask);
    end;
    else
    begin
      AIterator.LastResult64 := AIterator.LastResult64 shr BitsForChildIndexPerBucket;
      AIterator.LastResult64 := AIterator.LastResult64 and not Int64(BucketMask);
    end;
  end;
  Result := True;
end;

procedure TTrie.PackNode(var AIterator: TTrieIterator;
  const ChildrenBackup: array of Pointer);
var
  j, BitFieldIndex : Integer;
begin
  if AIterator.Level <= FLastMidBranchNode then
  begin
    if AIterator.ANodeStack[AIterator.Level]^.ChildrenCount > 0 then
    begin
      ReallocMem(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children, AIterator.ANodeStack[AIterator.Level]^.ChildrenCount * sizeof(Pointer));
      j := 0;
      PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.ChildIndex := 0;
      for BitFieldIndex := 0 to ChildrenPerBucket - 1 do
        if GetBusyIndicator(AIterator.ANodeStack[AIterator.Level], BitFieldIndex) then
        begin
          PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[j] := ChildrenBackup[BitFieldIndex];
          SetChildIndex(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level]), BitFieldIndex, j);
          inc(j);
        end;
    end
    else
    begin
      FreeMem(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children);
      PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children := nil;
      inc(AIterator.BreadCrumbs[AIterator.Level]);
    end;
  end
  else
  begin
    if AIterator.ANodeStack[AIterator.Level]^.ChildrenCount <= 0 then
    begin
      FreeMem(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children);
      PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children := nil;
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

function TTrie.LeafSize: Cardinal;
begin
  Result := sizeof(TTrieLeafNode);
end;

procedure TTrie.InitLeaf(var Leaf);
begin
  TTrieLeafNode(Leaf).Base.Busy := 0;
  TTrieLeafNode(Leaf).Base.ChildrenCount := 0;
end;

end.

