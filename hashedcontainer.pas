unit hashedcontainer;

interface

type
  _Int64 = {$IFDEF FPC}Int64{$ELSE}UInt64{$ENDIF};

  PTrieBaseNode = ^TTrieBaseNode;
  TTrieBaseNode = record
    ChildrenCount : Word;
    Busy : Word;
  end;

  PTrieBranchNode = ^TTrieBranchNode;
  
  TTrieBranchNode = record
    Base : TTrieBaseNode;
    ChildIndex : Int64;
    Children : Pointer;
  end;

const
  BitsPerByte                = 8;
  BitsForChildIndexPerBucket = 4;   // Don't play with this knob, code designed to work on this specific value
  BucketMask                 = $F;  // Don't play with this knob, code designed to work on this specific value
  TrieDepth16Bits            = (sizeof(Word) * BitsPerByte) div BitsForChildIndexPerBucket;
  TrieDepth32Bits            = (sizeof(Integer) * BitsPerByte) div BitsForChildIndexPerBucket;
  TrieDepth64Bits            = (sizeof(Int64) * BitsPerByte) div BitsForChildIndexPerBucket;
  ChildrenPerBucket          = BitsForChildIndexPerBucket * BitsForChildIndexPerBucket;

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

type
  PTrieLeafNode = ^TTrieLeafNode;
  TTrieLeafNode = record
    Base : TTrieBaseNode;
  end;

  TTrieLeafNodeArray = array[0..ChildrenPerBucket - 1] of Byte;
  PTrieLeafNodeArray = ^TTrieLeafNodeArray;

type
  TFreeTrieNodeEvent = procedure(ANode : PTrieBaseNode; Level : Byte) of object;
  TInitLeafEvent = procedure(var Leaf) of object;
  THashedContainer = class
  private
    FHashSize: Byte;
    FOnFreeTrieNode : TFreeTrieNodeEvent;
    FOnInitLeaf : TInitLeafEvent;
    FLeafSize : Cardinal;
  protected
    FCount: Integer;
    function GetBitFieldIndex(const Data; Level : Byte): Byte;
    function GetBusyIndicator(ANode : PTrieBaseNode; BitFieldIndex : Byte): Boolean; inline;
    function GetChildIndex(ANode : PTrieBranchNode; BitFieldIndex : Byte): Byte; inline;
    procedure SetBusyIndicator(ANode : PTrieBaseNode; BitFieldIndex : Byte; Value : Boolean); inline;
    procedure SetChildIndex(ANode : PTrieBranchNode; BitFieldIndex, ChildIndex : Byte);
    procedure InitLeaf(var Leaf);
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
    property LeafSize : Cardinal read FLeafSize;
  public
    constructor Create(AHashSize: Byte; ALeafSize: Cardinal);
    procedure Clear; virtual; abstract;
    procedure Pack; virtual; abstract;
    procedure InitIterator(out AIterator); virtual; abstract;
    function Next(var _AIterator; ADepth: Byte = 0): Boolean; virtual; abstract;
    function Add(const Data; out Node : PTrieLeafNode; out WasBusy : Boolean) : Boolean; virtual; abstract;
    procedure Remove(const Data); virtual; abstract;
    function Find(const Data; out ANode: PTrieLeafNode; out AChildIndex:
                  Byte; LeafHasChildIndex: Boolean): Boolean; overload; virtual; abstract;
    property Count: Integer read FCount;
    property OnFreeTrieNode : TFreeTrieNodeEvent read FOnFreeTrieNode write FOnFreeTrieNode;
    property OnInitLeaf : TInitLeafEvent read FOnInitLeaf write FOnInitLeaf;
  end;

implementation

{ THashedContainer }

constructor THashedContainer.Create(AHashSize: Byte; ALeafSize: Cardinal);
begin
  inherited Create;
  FHashSize := AHashSize;
  FLeafSize := ALeafSize;
end;

procedure THashedContainer.FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
begin
  if assigned(FOnFreeTrieNode) then
    FOnFreeTrieNode(ANode, Level);
end;

function THashedContainer.GetBitFieldIndex(const Data; Level: Byte): Byte;
begin
  {$IFNDEF FPC}
  Result := 0;
  {$ENDIF}
  case FHashSize of
    sizeof(Word)     : Result := (Word(Data) shr ChildIndexShiftArray16[Level]) and BucketMask;
    sizeof(Cardinal) : Result := (Integer(Data) shr ChildIndexShiftArray32[Level]) and BucketMask;
    sizeof(Int64)    : Result := (Int64(Data) shr ChildIndexShiftArray64[Level]) and BucketMask;
  end;
end;

function THashedContainer.GetBusyIndicator(ANode: PTrieBaseNode; BitFieldIndex:
    Byte): Boolean;
begin
  Result := (ANode^.Busy and (Word(1) shl BitFieldIndex)) <> 0;
end;

function THashedContainer.GetChildIndex(ANode: PTrieBranchNode; BitFieldIndex:
    Byte): Byte;
begin
  Result := (ANode^.ChildIndex shr (Int64(BitFieldIndex) * BitsForChildIndexPerBucket)) and BucketMask;
end;

procedure THashedContainer.InitLeaf(var Leaf);
begin
  if assigned(FOnInitLeaf) then
    FOnInitLeaf(Leaf);
end;

procedure THashedContainer.SetBusyIndicator(ANode: PTrieBaseNode;
    BitFieldIndex: Byte; Value: Boolean);
begin
  if Value then
    ANode^.Busy := ANode^.Busy or (Word(1) shl BitFieldIndex)
  else ANode^.Busy := ANode^.Busy and not (Word(1) shl BitFieldIndex);
end;

procedure THashedContainer.SetChildIndex(ANode: PTrieBranchNode; BitFieldIndex,
    ChildIndex: Byte);
begin
  ANode^.ChildIndex := ANode^.ChildIndex and CleanChildIndexMask[BitFieldIndex];
  ANode^.ChildIndex := ANode^.ChildIndex or (_Int64(ChildIndex) shl (BitFieldIndex * BitsForChildIndexPerBucket));
end;

end.
