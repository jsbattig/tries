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
  SysUtils;

const
  BitsPerByte                = 8;
  BitsForChildIndexPerBucket = 4;
  BucketMask                 = $F;
  MaxTrieDepth               = sizeof(Int64) * BitsPerByte div BitsForChildIndexPerBucket;
  ChildrenPerBucket          = BitsForChildIndexPerBucket * BitsForChildIndexPerBucket;
  TrieDepth16Bits            = (sizeof(Word) * BitsPerByte) div BitsForChildIndexPerBucket;
  TrieDepth32Bits            = (sizeof(Integer) * BitsPerByte) div BitsForChildIndexPerBucket;
  TrieDepth64Bits            = (sizeof(Int64) * BitsPerByte) div BitsForChildIndexPerBucket;
  TrieDepthPointerSize       = (sizeof(Pointer) * BitsPerByte) div BitsForChildIndexPerBucket;

type
  _Int64 = {$IFDEF FPC}Int64{$ELSE} UInt64 {$ENDIF};

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
      TrieDepth16Bits       : (LastResult16 : Word;);
      TrieDepth32Bits       : (LastResult32 : Integer;);
      TrieDepth64Bits       : (LastResult64 : _Int64;);
      -TrieDepthPointerSize : (LastResultPtr : Pointer;);
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
    FRandomAccessIterator : TTrieIterator;
    FLastIndex : Integer;
    FTrieDepth : Byte;
    FLastMidBranchNode : Byte;
    function NewTrieBranchNode : PTrieBranchNode;
    function AddChild(ANode : PTrieBranchNode; Level : Byte) : Integer;
    function GetBusyIndicator(ANode : PTrieBaseNode; BitFieldIndex : Byte) : Boolean; inline;
    procedure SetBusyIndicator(ANode : PTrieBaseNode; BitFieldIndex : Byte; Value : Boolean); inline;
    function NextNode(ACurNode : PTrieBranchNode; ALevel, AChildIndex : Byte) : Pointer; inline;
    function GetItem(Index: Integer): Pointer;
    function IteratorBacktrack(var AIterator : TTrieIterator) : Boolean;
    procedure PackNode(var AIterator : TTrieIterator; const ChildrenBackup : array of Pointer);
    procedure FreeTrieBranchNodeArray(const Arr : PTrieNodeArray; ChildrenCount, Level : Byte);
    procedure FreeTrieLeafNodeArray(const Arr : PTrieLeafNodeArray; ChildrenCount, Level : Byte);
  protected
    FStats : TTrieStats;
    FCount : Integer;
    function InternalFind(const Data; out ANode : PTrieLeafNode; out AChildIndex : Byte) : Boolean;
    function GetChildIndex(ANode : PTrieBranchNode; BitFieldIndex : Byte) : Byte; inline;
    procedure SetChildIndex(ANode : PTrieBranchNode; BitFieldIndex, ChildIndex : Byte); {$IFDEF FPC} inline; {$ENDIF}
    function GetBitFieldIndex(const Data; Level : Byte) : Byte;
    function Add(const Data; out Node : PTrieLeafNode; out WasBusy : Boolean) : Boolean;
    function Find(const Data) : Boolean;
    procedure Remove(const Data);
    function Next(var AIterator : TTrieIterator; ADepth : Byte = 0) : Boolean;
    function LeafSize : Cardinal; virtual;
    procedure InitLeaf(var Leaf); virtual;
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte); virtual;
    procedure RaiseTrieDepthError;
    procedure RaiseDuplicateKeysNotAllowed;
    property Items[Index: Integer]: Pointer read GetItem;
    property TrieDepth : Byte read FTrieDepth;
    property AllowDuplicates : Boolean read FAllowDuplicates write FAllowDuplicates;
    property RandomAccessMode : TTrieRandomAccessMode read FRandomAccessMode write FRandomAccessMode;
  public
    constructor Create(ATrieDepth : Byte);
    destructor Destroy; override;
    procedure Clear; virtual;
    procedure InitIterator(out AIterator : TTrieIterator);
    procedure Pack;
    property Count : Integer read FCount;
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
  CleanChildIndexMask : array[0..ChildrenPerBucket - 1] of _Int64 =
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
    RaiseTrieDepthError;
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
  end
  else dec(FStats.TotalMemAlloced, LeafSize);
  dec(FStats.NodeCount);
end;

procedure TTrie.RaiseTrieDepthError;
begin
  raise ETrie.Create(STR_TRIEDEPTHERROR);
end;

procedure TTrie.RaiseDuplicateKeysNotAllowed;
begin
  raise ETrieDuplicate.Create(STR_DUPLICATESNOTALLOWED);
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
    inc(FStats.NodeCount);
  end;
  Result := ANode^.Base.ChildrenCount;
  inc(ANode^.Base.ChildrenCount);
end;

function TTrie.GetBitFieldIndex(const Data; Level: Byte): Byte;
begin
  {$IFNDEF FPC}
  Result := 0;
  {$ENDIF}
  case FTrieDepth of
    TrieDepth16Bits : Result := (Word(Data) shr ChildIndexShiftArray16[Level]) and BucketMask;
    TrieDepth32Bits : Result := (Integer(Data) shr ChildIndexShiftArray32[Level]) and BucketMask;
    TrieDepth64Bits : Result := (Int64(Data) shr ChildIndexShiftArray64[Level]) and BucketMask;
    else RaiseTrieDepthError;
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
  ANode^.ChildIndex := ANode^.ChildIndex or (_Int64(ChildIndex) shl (BitFieldIndex * BitsForChildIndexPerBucket));
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
  {$IFDEF VER180}
  if FTrieDepth > TrieDepth32Bits then
    Result := @FRandomAccessIterator.LastResult64
  else Result := @FRandomAccessIterator.LastResult32;
  {$ELSE}
  Result := @FRandomAccessIterator.LastResult64;
  {$ENDIF}
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
    if (not FAllowDuplicates) and ( i = ATrieDepth - 1) and
       GetBusyIndicator(CurNode, BitFieldIndex) then
      RaiseDuplicateKeysNotAllowed;
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
  {$IFDEF VER180}
  AIterator.LastResult32 := 0;
  {$ENDIF}
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
      if GetBusyIndicator(AIterator.ANodeStack[AIterator.Level], i) then
      begin
        _ChildIndex := GetChildIndex(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level]), i);
        ChildrenPointersBackup[i] := PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[_ChildIndex];
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
        if GetBusyIndicator(AIterator.ANodeStack[AIterator.Level], BitFieldIndex) then
        begin
          ChildIndex := GetChildIndex(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level]), BitFieldIndex);
          if AIterator.Level = FLastMidBranchNode + 1 then
            if PTrieLeafNode(@PTrieLeafNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex * Integer(LeafSize)])^.Base.Busy = 0 then
            begin
              PackingNode := True;
              dec(AIterator.ANodeStack[AIterator.Level]^.ChildrenCount);
              SetBusyIndicator(AIterator.ANodeStack[AIterator.Level], BitFieldIndex, False);
              FreeTrieNode(@PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex * Integer(LeafSize)]^.Base, AIterator.Level + 1);
            end
            else { keep going, there's busy nodes on Children }
          else if PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex]^.Base.Busy = 0 then
          begin
            if not PackingNode then
            begin
              BackupChildren;
              PackingNode := True;
            end;
            dec(AIterator.ANodeStack[AIterator.Level]^.ChildrenCount);
            dec(FStats.TotalMemAlloced, sizeof(Pointer));
            SetBusyIndicator(AIterator.ANodeStack[AIterator.Level], BitFieldIndex, False);
            FreeTrieNode(@PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex]^.Base, AIterator.Level + 1);
          end
          else if PackingNode then
            ChildrenPointersBackup[BitFieldIndex] := PTrieNodeArray(PTrieBranchNode(AIterator.ANodeStack[AIterator.Level])^.Children)^[ChildIndex];
        end;
      if PackingNode then
        PackNode(AIterator, ChildrenPointersBackup);
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
    {$IFDEF VER180}
    { Delphi 2007 compiler places the start of Int64 at a different address than
      the 32 bits counterpart on the union... Go figure.. FreePascal and higher
      versions of Delphi behave consistently placing all elements on the same
      starting address }
    if ATrieDepth > TrieDepth32Bits then
      AIterator.LastResult64 := 0
    else AIterator.LastResult32 := 0;
    {$ELSE}
    AIterator.LastResult64 := 0;
    {$ENDIF}
  end
  else
  begin
    // We need to clean the lowest four bits when re-entering Next()
    case ATrieDepth of
      1..TrieDepth16Bits : AIterator.LastResult16 := AIterator.LastResult16 and not Word(BucketMask);
      TrieDepth16Bits + 1..TrieDepth32Bits : AIterator.LastResult32 := AIterator.LastResult32 and not Integer(BucketMask);
      TrieDepth32Bits + 1..TrieDepth64Bits : AIterator.LastResult64 := AIterator.LastResult64 and not _Int64(BucketMask);
      else RaiseTrieDepthError;
    end;
  end;
  repeat
    while AIterator.BreadCrumbs[AIterator.Level] < ChildrenPerBucket do
    begin
      if GetBusyIndicator(AIterator.ANodeStack[AIterator.Level], AIterator.BreadCrumbs[AIterator.Level] ) then
      begin
        case ATrieDepth of
          1..TrieDepth16Bits : AIterator.LastResult16 := AIterator.LastResult16 or Word(AIterator.BreadCrumbs[AIterator.Level]);
          TrieDepth16Bits + 1..TrieDepth32Bits : AIterator.LastResult32 := AIterator.LastResult32 or AIterator.BreadCrumbs[AIterator.Level];
          TrieDepth32Bits + 1..TrieDepth64Bits : AIterator.LastResult64 := AIterator.LastResult64 or AIterator.BreadCrumbs[AIterator.Level];
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
          1..TrieDepth16Bits : AIterator.LastResult16 := AIterator.LastResult16 shl BitsForChildIndexPerBucket;
          TrieDepth16Bits + 1..TrieDepth32Bits : AIterator.LastResult32 := AIterator.LastResult32 shl BitsForChildIndexPerBucket;
          TrieDepth32Bits + 1..TrieDepth64Bits : AIterator.LastResult64 := AIterator.LastResult64 shl BitsForChildIndexPerBucket;
          else RaiseTrieDepthError;
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
    TrieDepth64Bits :
    begin
      AIterator.LastResult64 := AIterator.LastResult64 shr BitsForChildIndexPerBucket;
      AIterator.LastResult64 := AIterator.LastResult64 and not _Int64(BucketMask);
    end;
    else RaiseTrieDepthError;
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

