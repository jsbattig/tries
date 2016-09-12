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

unit hashedcontainer;

interface

uses
  SysUtils;

const
  HashSizeNotSupportedError = 'Hashsize %d not supported';

type
  _Int64 = {$IFDEF FPC}Int64{$ELSE}UInt64{$ENDIF};

  PTrieBaseNode = ^TTrieBaseNode;
  TTrieBaseNode = record
    ChildrenCount : Word;
    Busy : Word;
  end;

const
  ChildIndexArrayLength = 2;

type
  PTrieBranchNode = ^TTrieBranchNode;
  TTrieBranchNode = record
    Base : TTrieBaseNode;
    ChildIndex : array[0..ChildIndexArrayLength - 1] of Cardinal;
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
  ChildIndexesPerBitField    = ChildrenPerBucket div ChildIndexArrayLength;

type
  PTrieLeafNode = ^TTrieLeafNode;
  TTrieLeafNode = record
    Base : TTrieBaseNode;
  end;

  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;
  TTrieLeafNodeArray = TByteArray;
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
const
  LevelNotSupportedError = 'Level %d not supported for Hashsize %d';
begin
  case HashSize of
    16 :
      case Level of
        0 : Result := 12;
        1 : Result := 8;
        2 : Result := 4;
        3 : Result := 0;
        else raise EHashedContainer.CreateFmt(LevelNotSupportedError, [Level, HashSize]);
      end;
    20 :
      case Level of
        0 : Result := 16;
        1 : Result := 12;
        2 : Result := 8;
        3 : Result := 4;
        4 : Result := 0;
        else raise EHashedContainer.CreateFmt(LevelNotSupportedError, [Level, HashSize]);
      end;
    32 :
      case Level of
        0 : Result := 28;
        1 : Result := 24;
        2 : Result := 20;
        3 : Result := 16;
        4 : Result := 12;
        5 : Result := 8;
        6 : Result := 4;
        7 : Result := 0;
        else raise EHashedContainer.CreateFmt(LevelNotSupportedError, [Level, HashSize]);
      end;
    64 :
      case Level of
        0  : Result := 60;
        1  : Result := 56;
        2  : Result := 52;
        3  : Result := 48;
        4  : Result := 44;
        5  : Result := 40;
        6  : Result := 36;
        7  : Result := 32;
        8  : Result := 28;
        9  : Result := 24;
        10 : Result := 20;
        11 : Result := 16;
        12 : Result := 12;
        13 : Result := 8;
        14 : Result := 4;
        15 : Result := 0;
        else raise EHashedContainer.CreateFmt(LevelNotSupportedError, [Level, HashSize]);
      end
    else raise EHashedContainer.CreateFmt(HashSizeNotSupportedError, [HashSize]);
  end;
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
var
  ChildIndexArrayIndex : Byte;
  RealBitFieldIndex : Cardinal;
begin
  ChildIndexArrayIndex := BitFieldIndex div ChildIndexesPerBitField;
  RealBitFieldIndex := BitFieldIndex mod ChildIndexesPerBitField;
  Result := (ANode^.ChildIndex[ChildIndexArrayIndex] shr (RealBitFieldIndex * BitsForChildIndexPerBucket)) and BucketMask;
end;

procedure TBaseHashedContainer.InitLeaf(var Leaf);
begin
  if assigned(FOnInitLeaf) then
    FOnInitLeaf(Leaf);
end;

procedure TBaseHashedContainer.RaiseHashSizeError;
begin
  raise EHashedContainer.CreateFmt(HashSizeNotSupportedError, [FHashSize]);
end;

procedure TBaseHashedContainer.SetBusyIndicator(ANode: PTrieBaseNode;
    BitFieldIndex: Byte; Value: Boolean);
begin
  if Value then
    ANode^.Busy := ANode^.Busy or (Word(1) shl BitFieldIndex)
  else ANode^.Busy := ANode^.Busy and not (Word(1) shl BitFieldIndex);
end;

function CleanChildIndexMask(BitFieldIndex : Byte): Cardinal; inline;
begin
  case BitFieldIndex of
    0 : Result := $FFFFFFF0;
    1 : Result := $FFFFFF0F;
    2 : Result := $FFFFF0FF;
    3 : Result := $FFFF0FFF;
    4 : Result := $FFF0FFFF;
    5 : Result := $FF0FFFFF;
    6 : Result := $F0FFFFFF;
    7 : Result := $0FFFFFFF;
    else raise EHashedContainer.CreateFmt('Wrong value for BitFieldIndex %d', [BitFieldIndex]);
  end;
end;

procedure TBaseHashedContainer.SetChildIndex(ANode: PTrieBranchNode; BitFieldIndex,
    ChildIndex: Byte);
var
  ChildIndexArrayIndex : Byte;
  RealBitFieldIndex : Cardinal;
  ChildIndexEncodedValue : Cardinal;
begin
  ChildIndexArrayIndex := BitFieldIndex div ChildIndexesPerBitField;
  RealBitFieldIndex := BitFieldIndex mod ChildIndexesPerBitField;
  ChildIndexEncodedValue := ANode^.ChildIndex[ChildIndexArrayIndex];
  ChildIndexEncodedValue := ChildIndexEncodedValue and CleanChildIndexMask(RealBitFieldIndex);
  ChildIndexEncodedValue := ChildIndexEncodedValue or (Cardinal(ChildIndex) shl (RealBitFieldIndex * BitsForChildIndexPerBucket));
  ANode^.ChildIndex[ChildIndexArrayIndex] := ChildIndexEncodedValue;
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
