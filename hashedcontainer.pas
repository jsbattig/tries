unit hashedcontainer;

interface

uses
  SysUtils;

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
  NOT_BUSY                   = 0;
  BitsPerByte                = 8;
  BitsForChildIndexPerBucket = 4;   // Don't play with this knob, code designed to work on this specific value
  BucketMask                 = $F;  // Don't play with this knob, code designed to work on this specific value
  TrieDepth16Bits            = (sizeof(Word) * BitsPerByte) div BitsForChildIndexPerBucket;
  TrieDepth32Bits            = (sizeof(Integer) * BitsPerByte) div BitsForChildIndexPerBucket;
  TrieDepth64Bits            = (sizeof(Int64) * BitsPerByte) div BitsForChildIndexPerBucket;
  TrieDepthPointerSize       = (sizeof(Pointer) * BitsPerByte) div BitsForChildIndexPerBucket;
  ChildrenPerBucket          = BitsForChildIndexPerBucket * BitsForChildIndexPerBucket;

  ChildIndexShiftArray : array[TrieDepth16Bits..TrieDepth64Bits, 0..ChildrenPerBucket - 1] of Byte =
    ((12, 8,   4,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0),
     (16, 12,  8,  4,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0),
     (20, 16, 12,  8,  4,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0),
     (24, 20, 16, 12,  8,  4,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0),
     (28, 24, 20, 16, 12,  8,  4,  0,  0,  0,  0,  0,  0,  0,  0,  0),
     (32, 28, 24, 20, 16, 12,  8,  4,  0,  0,  0,  0,  0,  0,  0,  0),
     (36, 32, 28, 24, 20, 16, 12,  8,  4,  0,  0,  0,  0,  0,  0,  0),
     (40, 36, 32, 28, 24, 20, 16, 12,  8,  4,  0,  0,  0,  0,  0,  0),
     (44, 40, 36, 32, 28, 24, 20, 16, 12,  8,  4,  0,  0,  0,  0,  0),
     (48, 44, 40, 36, 32, 28, 24, 20, 16, 12,  8,  4,  0,  0,  0,  0),
     (52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12,  8,  4,  0,  0,  0),
     (56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12,  8,  4,  0,  0),
     (60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12,  8,  4,  0));
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
  EHashedContainer = class(Exception);
  TFreeTrieNodeEvent = procedure(ANode : PTrieBaseNode; Level : Byte) of object;
  TInitLeafEvent = procedure(var Leaf) of object;

  THashedContainerIterator = packed record
    AtEnd : Boolean; _Padding1 : array [1..3] of Byte;
    case Integer of
      TrieDepth16Bits       : (LastResult16 : Word;);
      TrieDepth32Bits       : (LastResult32 : Integer;);
      TrieDepth64Bits       : (LastResult64 : _Int64;);
      -TrieDepthPointerSize : (LastResultPtr : Pointer;);
  end;

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
    procedure RaiseHashSizeError; inline;
    property LeafSize : Cardinal read FLeafSize;
    property HashSize : Byte read FHashSize;
  public
    constructor Create(AHashSize: Byte; ALeafSize: Cardinal);
    procedure Clear; virtual; abstract;
    procedure Pack; virtual; abstract;
    procedure InitIterator(out _AIterator); virtual;
    function Next(var _AIterator; ADepth: Byte = 0): Boolean; virtual; abstract;
    function Add(const Data; out Node : PTrieLeafNode; out WasBusy : Boolean) : Boolean; virtual; abstract;
    procedure Remove(const Data); virtual; abstract;
    function Find(const Data; out ANode: PTrieLeafNode; out AChildIndex: Byte; LeafHasChildIndex: Boolean): Boolean; virtual; abstract;
    function GetObjectFromIterator(const _AIterator): Pointer; virtual; abstract;
    function _Find(const Data): Boolean; overload;
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

function THashedContainer._Find(const Data): Boolean;
var
  DummyChildIndex : Byte;
  DummyNode : PTrieLeafNode;
begin
  Result := Find(Data, DummyNode, DummyChildIndex, False);
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
    1..sizeof(Word) * BitsPerByte :
      Result := (Word(Data) shr ChildIndexShiftArray[FHashSize div BitsForChildIndexPerBucket, Level]) and BucketMask;
    sizeof(Word) * BitsPerByte + 1..sizeof(Cardinal) * BitsPerByte :
      Result := (Integer(Data) shr ChildIndexShiftArray[FHashSize div BitsForChildIndexPerBucket, Level]) and BucketMask;
    sizeof(Cardinal) * BitsPerByte + 1..sizeof(Int64) * BitsPerByte :
      Result := (Int64(Data) shr ChildIndexShiftArray[FHashSize div BitsForChildIndexPerBucket, Level]) and BucketMask;
    else RaiseHashSizeError;
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

procedure THashedContainer.InitIterator(out _AIterator);
var
  AIterator : THashedContainerIterator absolute _AIterator;
begin
  AIterator.AtEnd := False;
  AIterator.LastResult64 := 0;
end;

procedure THashedContainer.InitLeaf(var Leaf);
begin
  if assigned(FOnInitLeaf) then
    FOnInitLeaf(Leaf);
end;

procedure THashedContainer.RaiseHashSizeError;
const
  STR_HASHSIZEERROR = 'Wrong hash size';
begin
  raise EHashedContainer.Create(STR_HASHSIZEERROR);
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
