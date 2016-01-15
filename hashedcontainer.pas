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

  TBaseHashedContainer = class
  private
    FHashSize: Byte;
    FOnFreeTrieNode : TFreeTrieNodeEvent;
    FOnInitLeaf : TInitLeafEvent;
    FLeafSize : Cardinal;
  protected
    FCount: Integer;
    function GetBitFieldIndex(const Data; Level : Byte): Byte; {$IFNDEF FPC} inline; {$ENDIF}
    function GetBusyIndicator(ANode : PTrieBaseNode; BitFieldIndex : Byte): Boolean; inline;
    function GetChildIndex(ANode : PTrieBranchNode; BitFieldIndex : Byte): Byte; inline;
    procedure SetBusyIndicator(ANode : PTrieBaseNode; BitFieldIndex : Byte; Value : Boolean); inline;
    procedure SetChildIndex(ANode : PTrieBranchNode; BitFieldIndex, ChildIndex : Byte); inline;
    procedure InitLeaf(var Leaf); {$IFNDEF FPC} inline; {$ENDIF}
    procedure FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
    procedure RaiseHashSizeError; inline;
    property LeafSize : Cardinal read FLeafSize;
    property HashSize : Byte read FHashSize;
  public
    constructor Create(AHashSize: Byte; ALeafSize: Cardinal);
    property Count: Integer read FCount;
    property OnFreeTrieNode : TFreeTrieNodeEvent read FOnFreeTrieNode write FOnFreeTrieNode;
    property OnInitLeaf : TInitLeafEvent read FOnInitLeaf write FOnInitLeaf;
  end;

  THashedContainer = class(TBaseHashedContainer)
  public
    function _Find(const Data): Boolean; overload;
    procedure Clear; virtual; abstract;
    procedure Pack; virtual; abstract;
    function Next(var _AIterator; ADepth: Byte = 0): Boolean; virtual; abstract;
    function Add(const Data; out Node : PTrieLeafNode; out WasBusy : Boolean) : Boolean; virtual; abstract;
    procedure Remove(const Data); virtual; abstract;
    function Find(const Data; out ANode: PTrieLeafNode; out AChildIndex: Byte; LeafHasChildIndex: Boolean): Boolean; virtual; abstract;
    function GetObjectFromIterator(const _AIterator): Pointer; virtual; abstract;
    procedure InitIterator(out _AIterator); virtual;
  end;

implementation

{ THashedContainer }

constructor TBaseHashedContainer.Create(AHashSize: Byte; ALeafSize: Cardinal);
begin
  inherited Create;
  FHashSize := AHashSize;
  FLeafSize := ALeafSize;
end;

procedure TBaseHashedContainer.FreeTrieNode(ANode : PTrieBaseNode; Level : Byte);
begin
  if assigned(FOnFreeTrieNode) then
    FOnFreeTrieNode(ANode, Level);
end;

function ChildIndexShift(HashSize, Level : Byte) : Byte; inline;
begin
  Result := (HashSize div BitsForChildIndexPerBucket - Level - 1) * BitsForChildIndexPerBucket;
end;

function TBaseHashedContainer.GetBitFieldIndex(const Data; Level: Byte): Byte;
begin
  {$IFNDEF FPC}
  Result := 0;
  {$ENDIF}
  case FHashSize of
    1..sizeof(Word) * BitsPerByte :
      Result := (Word(Data) shr ChildIndexShift(FHashSize, Level)) and BucketMask;
    sizeof(Word) * BitsPerByte + 1..sizeof(Cardinal) * BitsPerByte :
      Result := (Integer(Data) shr ChildIndexShift(FHashSize, Level)) and BucketMask;
    sizeof(Cardinal) * BitsPerByte + 1..sizeof(Int64) * BitsPerByte :
      Result := (Int64(Data) shr ChildIndexShift(FHashSize, Level)) and BucketMask;
    else RaiseHashSizeError;
  end;
end;

function TBaseHashedContainer.GetBusyIndicator(ANode: PTrieBaseNode; BitFieldIndex:
    Byte): Boolean;
begin
  Result := (ANode^.Busy and (Word(1) shl BitFieldIndex)) <> 0;
end;

function TBaseHashedContainer.GetChildIndex(ANode: PTrieBranchNode; BitFieldIndex:
    Byte): Byte;
begin
  Result := (ANode^.ChildIndex shr (Int64(BitFieldIndex) * BitsForChildIndexPerBucket)) and BucketMask;
end;

procedure TBaseHashedContainer.InitLeaf(var Leaf);
begin
  if assigned(FOnInitLeaf) then
    FOnInitLeaf(Leaf);
end;

procedure TBaseHashedContainer.RaiseHashSizeError;
const
  STR_HASHSIZEERROR = 'Wrong hash size';
begin
  raise EHashedContainer.Create(STR_HASHSIZEERROR);
end;

procedure TBaseHashedContainer.SetBusyIndicator(ANode: PTrieBaseNode;
    BitFieldIndex: Byte; Value: Boolean);
begin
  if Value then
    ANode^.Busy := ANode^.Busy or (Word(1) shl BitFieldIndex)
  else ANode^.Busy := ANode^.Busy and not (Word(1) shl BitFieldIndex);
end;

function CleanChildIndexMask(BitFieldIndex : Byte) : Int64; inline;
begin
  Result := Int64(-1) xor (Int64(BucketMask) shl (BitFieldIndex * BitsForChildIndexPerBucket));
end;

procedure TBaseHashedContainer.SetChildIndex(ANode: PTrieBranchNode; BitFieldIndex,
    ChildIndex: Byte);
begin
  ANode^.ChildIndex := ANode^.ChildIndex and CleanChildIndexMask(BitFieldIndex);
  ANode^.ChildIndex := ANode^.ChildIndex or (_Int64(ChildIndex) shl (BitFieldIndex * BitsForChildIndexPerBucket));
end;

{ THashedContainer }

function THashedContainer._Find(const Data): Boolean;
var
  DummyChildIndex : Byte;
  DummyNode : PTrieLeafNode;
begin
  Result := Find(Data, DummyNode, DummyChildIndex, False);
end;

procedure THashedContainer.InitIterator(out _AIterator);
var
  AIterator : THashedContainerIterator absolute _AIterator;
begin
  AIterator.AtEnd := False;
  AIterator.LastResult64 := 0;
end;

end.
