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
begin
  WasBusy := FHashTable[Word(Data)] <> nil;
  if not WasBusy then
  begin
    Node := FLeafNodesAllocator.Alloc;
    InitLeaf(Node^);
    Node^.Base.Busy := Word(not NOT_BUSY);
    FHashTable[Word(Data)] := Node;
    Result := True;
  end
  else
  begin
    Node := FHashTable[Word(Data)];
    Result := False;
  end;
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
begin
  Result := FHashTable[Word(Data)] <> nil;
  if Result then
  begin
    ANode := FHashTable[Word(Data)];
    AChildIndex := 0;
  end
  else ANode := nil;
end;

procedure THashTable.FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
begin
  inherited FreeTrieNode(ANode, Level);
  uAllocators.DeAlloc(ANode);
end;

procedure THashTable.InitIterator(out _AIterator);
var
  AIterator : THashTableIterator absolute _AIterator;
begin
  inherited InitIterator(AIterator.Base);
  AIterator.Index := 0;
end;

function THashTable.Next(var _AIterator; ADepth: Byte = 0): Boolean;
var
  AIterator : THashTableIterator absolute _AIterator;
begin
  AIterator.Base.LastResultPtr := nil;
  repeat
    if not AIterator.Base.AtEnd then
    begin
      AIterator.Base.LastResultPtr := FHashTable[AIterator.Index];
      AIterator.Base.AtEnd := AIterator.Index = MAX_HASH_TABLE_INDEX;
      inc(AIterator.Index);
    end
    else break;
  until AIterator.Base.AtEnd or (AIterator.Base.LastResultPtr <> nil);
  Result := AIterator.Base.LastResultPtr <> nil;
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
