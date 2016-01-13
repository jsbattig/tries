unit hash_table;

interface

uses
  HashedContainer, uAllocators;

const
  MAX_HASH_TABLE_INDEX = 65535;

type
  THashTableIterator = record
    Base : THashedContainerIterator;
    Index : Word;
    BitFieldIndex : SmallInt;
    Node : PTrieLeafNode;
  end;

  THashTable = class(THashedContainer)
  private
    FHashTable : array[Word] of PTrieLeafNode;
    FLeafNodesAllocator : TFixedBlockHeap;
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
                  LeafHasChildIndex: Boolean): Boolean; overload; override;
    function GetObjectFromIterator(const _AIterator): Pointer; override;
    procedure InitIterator(out _AIterator); override;
    function Next(var _AIterator; ADepth: Byte = 0): Boolean; override;
    procedure Pack; override;
    procedure Remove(const Data); override;
  end;

implementation

resourcestring
  SNotSupportedHashSize = 'Not supported hash size';

{ THashTable }

constructor THashTable.Create(AHashSize: Byte; ALeafSize: Cardinal);
var
  i : integer;
begin
  if AHashSize <> sizeof(Word) then
    raise EHashedContainer.Create(SNotSupportedHashSize);
  inherited;
  for i := Low(FHashTable) to High(FHashTable) do
    FHashTable[i] := nil;
  FLeafNodesAllocator := TFixedBlockHeap.Create(LeafSize, MAX_MEDIUM_BLOCK_SIZE div LeafSize);
end;

destructor THashTable.Destroy;
begin
  inherited;
  Clear;
  FLeafNodesAllocator.Free;
end;

function THashTable.Add(const Data; out Node : PTrieLeafNode; out WasBusy :
    Boolean): Boolean;
var
  ABitFieldIndex : Byte;
begin
  Result := FHashTable[Word(Data) div ChildrenPerBucket] = nil;
  if Result then
  begin
    Node := FLeafNodesAllocator.Alloc;
    InitLeaf(Node^);
    FHashTable[Word(Data) div ChildrenPerBucket] := Node;
  end
  else Node := FHashTable[Word(Data) div ChildrenPerBucket];
  ABitFieldIndex := GetBitFieldIndex(Data, HashSizeToTrieDepth(HashSize) - 1);
  WasBusy := GetBusyIndicator(@Node^.Base, ABitFieldIndex);
  if not WasBusy then
    SetBusyIndicator(@Node^.Base, ABitFieldIndex, True);
end;

procedure THashTable.Clear;
var
  i : integer;
begin
  for i := Low(FHashTable) to High(FHashTable) do
    if FHashTable[i] <> nil then
    begin
      FreeTrieNode(@FHashTable[i]^.Base, HashSizeToTrieDepth(HashSize) - 1);
      FHashTable[i] := nil;
    end;
end;

function THashTable.Find(const Data; out ANode: PTrieLeafNode; out AChildIndex:
    Byte; LeafHasChildIndex: Boolean): Boolean;
var
  ABitFieldIndex : Byte;
begin
  ABitFieldIndex := GetBitFieldIndex(Data, HashSizeToTrieDepth(HashSize) - 1);
  Result := (FHashTable[Word(Data) div ChildrenPerBucket] <> nil) and
             GetBusyIndicator(@FHashTable[Word(Data) div ChildrenPerBucket]^.Base, ABitFieldIndex);
  if Result then
  begin
    ANode := FHashTable[Word(Data) div ChildrenPerBucket];
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
  uAllocators.DeAlloc(ANode);
end;

function THashTable.GetObjectFromIterator(const _AIterator): Pointer;
begin
  Result := THashTableIterator(_AIterator).Node;
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
var
  AIterator : THashTableIterator absolute _AIterator;
begin
  AIterator.Node := nil;
  repeat
    if AIterator.Base.AtEnd then
      break;
    AIterator.Node := FHashTable[AIterator.Index];
    if AIterator.Node <> nil then
    begin
      inc(AIterator.BitFieldIndex);
      while AIterator.BitFieldIndex < ChildrenPerBucket do
      begin
        if GetBusyIndicator(@PTrieLeafNode(AIterator.Node)^.Base, AIterator.BitFieldIndex) then
          break;
        inc(AIterator.BitFieldIndex);
      end;
    end;
    if (AIterator.Node = nil) or (AIterator.BitFieldIndex >= ChildrenPerBucket) then
    begin
      if AIterator.Index = MAX_HASH_TABLE_INDEX then
      begin
        AIterator.Base.AtEnd := True;
        break;
      end
      else
      begin
        inc(AIterator.Index);
        AIterator.BitFieldIndex := -1;
        AIterator.Node := nil;
      end;
    end;
  until AIterator.Base.AtEnd or (AIterator.Node <> nil);
  AIterator.Base.LastResult64 := (AIterator.Index * ChildrenPerBucket) + AIterator.BitFieldIndex;
  Result := AIterator.Node <> nil;
end;

procedure THashTable.Pack;
var
  i : integer;
begin
  for i := Low(FHashTable) to High(FHashTable) do
    if (FHashTable[i] <> nil) and (FHashTable[i]^.Base.Busy = NOT_BUSY) then
    begin
      FreeTrieNode(@FHashTable[i]^.Base, HashSizeToTrieDepth(HashSize) - 1);
      FHashTable[i] := nil;
    end;
end;

procedure THashTable.Remove(const Data);
begin
  if FHashTable[Word(Data)] <> nil then
  begin
    FreeTrieNode(@FHashTable[Word(Data)]^.Base, HashSizeToTrieDepth(HashSize) - 1);
    FHashTable[Word(Data)] := nil;
  end;
end;

function THashTable.HashSizeToTrieDepth(AHashSize: Byte): Byte;
begin
  if AHashSize <= sizeof(Word) then
    Result := TrieDepth16Bits
  else if AHashSize <= sizeof(Cardinal) then
    Result := TrieDepth32Bits
  else Result := TrieDepth64Bits;
end;

procedure THashTable.InitLeaf(var Leaf);
begin
  TTrieLeafNode(Leaf).Base.Busy := NOT_BUSY;
  TTrieLeafNode(Leaf).Base.ChildrenCount := 0;
  inherited;
end;

end.
