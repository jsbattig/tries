unit hash_table;

interface

uses
  HashedContainer, trieAllocators;

const
  MAX_HASH_TABLE_INDEX = 65535;

type
  PHashTableNodeArray = ^THashTableNodeArray;
  THashTableNodeArray = array[Word] of PTrieLeafNode;
  THashTableIterator = record
    Base : THashedContainerIterator;
    Index : Word;
    BitFieldIndex : SmallInt;
    Node : PTrieLeafNode;
  end;

  THashTable = class(THashedContainer)
  private
    FHashTable : PHashTableNodeArray;
    FHashTableMaxNodeCount : Cardinal;
    FLeafNodesAllocator : TFixedBlockHeap;
    function GetTableIndex(const Data): Word;
    function HashSizeToTrieDepth(AHashSize: Byte): Byte; inline;
  protected
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
    procedure InitLeaf(var Leaf);
  public
    constructor Create(AHashSize: Byte; ALeafSize: Cardinal);
    destructor Destroy; override;
    function Add(const Data; out Node : PTrieLeafNode; out WasBusy : Boolean): Boolean; override;
    procedure Clear; override;
    function Find(const Data; out ANode: PTrieLeafNode; out AChildIndex: Byte;
                  {%H-}LeafHasChildIndex: Boolean): Boolean; overload; override;
    function GetObjectFromIterator(const _AIterator): Pointer; override;
    procedure InitIterator(out _AIterator); override;
    function Next(var _AIterator; {%H-}ADepth: Byte = 0): Boolean; override;
    procedure Pack; override;
    procedure Remove(const Data); override;
  end;

implementation

resourcestring
  SNotSupportedHashSize = 'Not supported hash size. Valid sizes are 16 to 20 bits';

{ THashTable }

constructor THashTable.Create(AHashSize: Byte; ALeafSize: Cardinal);
var
  i : integer;
begin
  if (AHashSize < sizeof(Word) * BitsPerByte) or (AHashSize > sizeof(Word) * BitsPerByte + BitsForChildIndexPerBucket) then
    raise EHashedContainer.Create(SNotSupportedHashSize);
  inherited;
  FHashTableMaxNodeCount := (1 shl AHashSize) div ChildrenPerBucket;
  GetMem(FHashTable, FHashTableMaxNodeCount * sizeof(PTrieLeafNode));
  for i := 0 to FHashTableMaxNodeCount - 1 do
    FHashTable^[i] := nil;
  FLeafNodesAllocator := TFixedBlockHeap.Create(LeafSize, _64KB div LeafSize);
end;

destructor THashTable.Destroy;
begin
  inherited;
  Clear;
  FLeafNodesAllocator.Free;
  FreeMem(FHashTable);
end;

function THashTable.Add(const Data; out Node : PTrieLeafNode; out WasBusy :
    Boolean): Boolean;
var
  ABitFieldIndex : Byte;
  ATableIndex : Word;
begin
  ATableIndex := GetTableIndex(Data);
  Result := FHashTable^[ATableIndex] = nil;
  if Result then
  begin
    Node := FLeafNodesAllocator.Alloc;
    InitLeaf(Node^);
    FHashTable^[ATableIndex] := Node;
  end
  else Node := FHashTable^[ATableIndex];
  ABitFieldIndex := GetBitFieldIndex(Data, HashSizeToTrieDepth(HashSize) - 1);
  WasBusy := GetBusyIndicator(@Node^.Base, ABitFieldIndex);
  if not WasBusy then
    SetBusyIndicator(@Node^.Base, ABitFieldIndex, True);
end;

procedure THashTable.Clear;
var
  i : integer;
begin
  for i := 0 to FHashTableMaxNodeCount - 1 do
    if FHashTable^[i] <> nil then
    begin
      FreeTrieNode(@FHashTable^[i]^.Base, HashSizeToTrieDepth(HashSize) - 1);
      FHashTable^[i] := nil;
    end;
end;

function THashTable.Find(const Data; out ANode: PTrieLeafNode; out AChildIndex:
    Byte; LeafHasChildIndex: Boolean): Boolean;
var
  ABitFieldIndex : Byte;
  ATableIndex : Word;
begin
  ATableIndex := GetTableIndex(Data);
  ABitFieldIndex := GetBitFieldIndex(Data, HashSizeToTrieDepth(HashSize) - 1);
  Result := (FHashTable^[ATableIndex] <> nil) and
             GetBusyIndicator(@FHashTable^[ATableIndex]^.Base, ABitFieldIndex);
  if Result then
  begin
    ANode := FHashTable^[ATableIndex];
    AChildIndex := GetChildIndex(@ANode^.Base, ABitFieldIndex);
  end
  else
  begin
    ANode := nil;
    AChildIndex := 0;
  end;
end;

procedure THashTable.FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
begin
  inherited FreeTrieNode(ANode, Level);
  trieAllocators.DeAlloc(ANode);
end;

function THashTable.GetObjectFromIterator(const _AIterator): Pointer;
begin
  Result := THashTableIterator(_AIterator).Node;
end;

function THashTable.GetTableIndex(const Data): Word;
begin
  if HashSize <= 16 then
    Result := Word(Data) div ChildrenPerBucket
  else Result := Cardinal(Data) div ChildrenPerBucket;
end;

procedure THashTable.InitIterator(out _AIterator);
var
  AIterator : THashTableIterator absolute _AIterator;
begin
  inherited InitIterator(AIterator.Base);
  AIterator.Index := 0;
  AIterator.BitFieldIndex := -1;
  AIterator.Node := nil;
end;

function THashTable.Next(var _AIterator; ADepth: Byte = 0): Boolean;
label
  TableLoopExit;
var
  AIterator : THashTableIterator absolute _AIterator;
begin
  if AIterator.Base.AtEnd then
  begin
    Result := False;
    exit;
  end;
  repeat
    AIterator.Node := FHashTable^[AIterator.Index];
    if AIterator.Node <> nil then
    begin
      inc(AIterator.BitFieldIndex);
      while AIterator.BitFieldIndex < ChildrenPerBucket do
      begin
        if GetBusyIndicator(@PTrieLeafNode(AIterator.Node)^.Base, AIterator.BitFieldIndex) then
          goto TableLoopExit;
        inc(AIterator.BitFieldIndex);
      end;
    end;
    if AIterator.BitFieldIndex >= ChildrenPerBucket then
      AIterator.Node := nil;
    if AIterator.Node = nil then
    begin
      if AIterator.Index = FHashTableMaxNodeCount - 1 then
      begin
        AIterator.Base.AtEnd := True;
        break;
      end
      else
      begin
        inc(AIterator.Index);
        AIterator.BitFieldIndex := -1;
      end;
    end;
  until False;
TableLoopExit:
  Result := AIterator.Node <> nil;
  if Result then
    AIterator.Base.LastResult64 := (Int64(AIterator.Index) * ChildrenPerBucket) + Int64(AIterator.BitFieldIndex);
end;

procedure THashTable.Pack;
var
  i : integer;
begin
  for i := 0 to FHashTableMaxNodeCount - 1 do
    if (FHashTable^[i] <> nil) and (FHashTable^[i]^.Base.Busy = NOT_BUSY) then
    begin
      FreeTrieNode(@FHashTable^[i]^.Base, HashSizeToTrieDepth(HashSize) - 1);
      FHashTable^[i] := nil;
    end;
end;

procedure THashTable.Remove(const Data);
var
  ATableIndex : Word;
begin
  ATableIndex := GetTableIndex(Data);
  if FHashTable^[ATableIndex] <> nil then
    SetBusyIndicator(@FHashTable^[ATableIndex]^.Base, GetBitFieldIndex(Data, HashSizeToTrieDepth(HashSize) - 1), False);
end;

function THashTable.HashSizeToTrieDepth(AHashSize: Byte): Byte;
begin
  Result := AHashSize div BitsForChildIndexPerBucket;
end;

procedure THashTable.InitLeaf(var Leaf);
begin
  TTrieLeafNode(Leaf).Base.Busy := NOT_BUSY;
  TTrieLeafNode(Leaf).Base.ChildrenCount := 0;
  inherited;
end;

end.
