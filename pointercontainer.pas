unit PointerContainer;

{$mode objfpc}{$H+}
{.$DEFINE POINTERCONTAINER_COLLECTSTATS}

interface

uses
  Classes, SysUtils;

const
  (* The following three constants are dependant on each other, if you change one the three need
     to be kept in sync for the code to work properl. The numbers are set in a way to try to achieve
     a balance between space used and time to search *)
  BucketsPerContainer = 16; // Maximum addressable number of buckets given by mask BucketIndexMask number of bits
  LevelsCycle = 8; // Number of cycles to iterate all indexes within a hash using BucketIndexMask
  BucketIndexMask = $F; // one-filled bits up to OR hash parameter

type
  PBucket = ^TBucket;
  PBucketArray = ^TBucketArray;
  PBucketsContainer = ^TBucketsContainer;
  TBucket = record
    Value : Pointer;
    Child : PBucketsContainer;
  end;
  TBucketArray = array[0..BucketsPerContainer - 1] of TBucket;
  TBucketsContainer = record
    IterateCurIndex : Cardinal;
    Parent : PBucketsContainer;
    Buckets : TBucketArray;
  end;
  {$IFDEF POINTERCONTAINER_COLLECTSTATS}
  TStats = record
    Depth : Integer;
    BucketContainerCount : Integer;
    AttemptsToInsertOnBucketCount : Integer;
    ComparisonOnSearchCount : Integer;
  end;
  {$ENDIF}

const
  SzBucketContainer = sizeof(TBucketsContainer);
  SzOfByteInBits = 8;


type
  { TPointerContainer }

  EPointerContainer = class(Exception);
  TPointerContainer = class
  private
    FBuckets : PBucketsContainer;
    FCount : Cardinal;
    FCurContainer : PBucketsContainer;
    FCheckDuplicateOnInsertion : Boolean;
    FMultipleAttemptsPerBucketContainer: Boolean;
    PPrevIndex : Integer;
    {$IFDEF POINTERCONTAINER_COLLECTSTATS}
    FStats : TStats;
    {$ENDIF}
    FAttemptsPerBucket : Integer;
    procedure FreeBuckets(ABucketContainer : PBucketsContainer);
    procedure AllocNewBucketContainer(AParent : PBucketsContainer; var ABucketContainer : PBucketsContainer);
    function BucketIndexFromHash(AHash : Cardinal; IndexNumber : Integer) : Integer; inline;
    function GetCount: Integer; inline;
    function GetItem(Index : Cardinal): Pointer;
    function Hash(AValue : Pointer) : Cardinal; inline;
    procedure InternalAdd(AValue : Pointer; AHash : Cardinal;
                          ABucketContainer : PBucketsContainer; Level : Integer);
    function InternalFind(AValue : Pointer; AHash : Cardinal; ABucketContainer : PBucketsContainer;
                          Level : Integer; out ABucket : PBucket) : Boolean;
    function IterateNextBucket(ReturnFromChildren : Boolean) : Boolean;
    procedure SetMultipleAttemptsPerBucketContainer(Value : Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(AValue : Pointer); inline;
    function Find(AValue : Pointer) : Boolean; inline;
    function Remove(AValue : Pointer) : Boolean;
    procedure Clear;
    property Count : Integer read GetCount;
    property Items[Index : Cardinal] : Pointer read GetItem; default;
    property CheckDuplicateOnInsertion : Boolean read FCheckDuplicateOnInsertion write FCheckDuplicateOnInsertion;
    property MultipleAttemptsPerBucketContainer : Boolean read FMultipleAttemptsPerBucketContainer write SetMultipleAttemptsPerBucketContainer;
    {$IFDEF POINTERCONTAINER_COLLECTSTATS}
    property Stats : TStats read FStats;
    {$ENDIF}
  end;

implementation

resourcestring
  STR_KEYCANTBENIL = 'AKey can''t be nil';
  STR_INDEXOUTOFBOUNDS = 'Index of out bounds';
  STR_ISINDEXOUTOFBOUNDS = 'Index of out bounds?';
  STR_DUPLICATESNOTALLOWED = 'Duplicates not allowed';
  ASSERT_BUCKETISNIL = 'If Result is True ABucket must be <> nil';

function SuperFastHash(data: PByte; Len: Cardinal): Cardinal; forward;

constructor TPointerContainer.Create;
begin
  inherited;
  FCheckDuplicateOnInsertion := False;
  MultipleAttemptsPerBucketContainer := True;
  Clear;
end;

destructor TPointerContainer.Destroy;
begin
  FreeBuckets(FBuckets);
  inherited Destroy;
end;

procedure TPointerContainer.Add(AValue: Pointer);
begin
  if FCheckDuplicateOnInsertion and Find(AValue) then
    raise EPointerContainer.Create(STR_DUPLICATESNOTALLOWED);
  InternalAdd(AValue, Hash(AValue), FBuckets, 0);
end;

function TPointerContainer.Find(AValue: Pointer): Boolean;
var
  Dummy : PBucket;
begin
  Result := InternalFind(AValue, Hash(AValue), FBuckets, 0, Dummy);
end;

function TPointerContainer.Remove(AValue: Pointer): Boolean;
var
  ABucket : PBucket;
begin
  Result := InternalFind(AValue, Hash(AValue), FBuckets, 0, ABucket);
  if Result then
  begin
    Assert(ABucket <> nil, ASSERT_BUCKETISNIL);
    ABucket^.Value := nil;
    dec(FCount);
  end;
end;

procedure TPointerContainer.Clear;
begin
  if FBuckets <> nil then
    FreeBuckets(FBuckets);
  AllocNewBucketContainer(nil, FBuckets);
  {$IFDEF POINTERCONTAINER_COLLECTSTATS}
  FStats.BucketContainerCount := 0;
  FStats.Depth := 0;
  FStats.AttemptsToInsertOnBucketCount := 0;
  FStats.ComparisonOnSearchCount := 0;
  {$ENDIF}
  FCount := 0;
  PPrevIndex := -1;
end;

procedure TPointerContainer.FreeBuckets(ABucketContainer: PBucketsContainer);
var
  i : integer;
begin
  for i := low(ABucketContainer^.Buckets) to high(ABucketContainer^.Buckets) do
    if (ABucketContainer^.Buckets[i].Child <> nil) and (ABucketContainer^.Buckets[i].Child <> ABucketContainer) then
      FreeBuckets(ABucketContainer^.Buckets[i].Child);
  FreeMem(ABucketContainer);
end;

procedure TPointerContainer.AllocNewBucketContainer(AParent: PBucketsContainer;
  var ABucketContainer: PBucketsContainer);
begin
  GetMem(ABucketContainer, SzBucketContainer);
  FillChar(ABucketContainer^, SzBucketContainer, 0);
  ABucketContainer^.Parent := AParent;
  {$IFDEF POINTERCONTAINER_COLLECTSTATS}
  inc(FStats.BucketContainerCount);
  {$ENDIF}
end;

function TPointerContainer.BucketIndexFromHash(AHash: Cardinal;
  IndexNumber: Integer): Integer;
var
  ShiftBits : Integer;
begin
  ShiftBits := SzOfByteInBits * (IndexNumber mod LevelsCycle);
  Result := (AHash and (BucketIndexMask shl ShiftBits)) shr ShiftBits;
end;

function TPointerContainer.GetCount: Integer;
begin
  Result := FCount;
end;

function TPointerContainer.GetItem(Index: Cardinal): Pointer;
var
  i : Integer;
begin
  if Index >= FCount then
    raise EPointerContainer.Create(STR_INDEXOUTOFBOUNDS);
  if (Index = 0) or (Index <= Cardinal(PPrevIndex)) or (PPrevIndex = -1) then
  begin
    FCurContainer := FBuckets;
    FCurContainer^.IterateCurIndex := 0;
    PPrevIndex := -1;
  end;
  for i := PPrevIndex + 1 to Index do
  begin
    if IterateNextBucket(False) then
    begin
      Result := FCurContainer^.Buckets[FCurContainer^.IterateCurIndex].Value;
      inc(FCurContainer^.IterateCurIndex);
    end
    else
    begin
      PPrevIndex := -1; // Let's reset sequential cached  iterator when this error happens
      raise EPointerContainer.Create(STR_ISINDEXOUTOFBOUNDS);
    end;
  end;
  PPrevIndex := Index;
end;

function TPointerContainer.Hash(AValue: Pointer): Cardinal;
begin
  Result := SuperFastHash(@AValue, sizeof(AValue));
end;

procedure TPointerContainer.InternalAdd(AValue: Pointer; AHash: Cardinal;
  ABucketContainer: PBucketsContainer; Level: Integer);
var
  BucketIndex, i : Integer;
begin
  if AValue = nil then
    raise EPointerContainer.Create(STR_KEYCANTBENIL);
  {$IFDEF POINTERCONTAINER_COLLECTSTATS}
  if Level + 1 > FStats.Depth then
    FStats.Depth := Level + 1;
  {$ENDIF}
  for i := 0 to FAttemptsPerBucket - 1 do
  begin
    BucketIndex := BucketIndexFromHash(AHash, Level + i);
    {$IFDEF POINTERCONTAINER_COLLECTSTATS}
    inc(FStats.AttemptsToInsertOnBucketCount);
    {$ENDIF}
    if ABucketContainer^.Buckets[BucketIndex].Value = nil then
    begin
      ABucketContainer^.Buckets[BucketIndex].Value := AValue;
      inc(FCount);
      exit;
    end;
  end;
  if ABucketContainer^.Buckets[BucketIndex].Child = nil then
    AllocNewBucketContainer(ABucketContainer, ABucketContainer^.Buckets[BucketIndex].Child);
  InternalAdd(AValue, AHash, ABucketContainer^.Buckets[BucketIndex].Child, Level + 1);
end;

function TPointerContainer.InternalFind(AValue: Pointer; AHash: Cardinal;
  ABucketContainer: PBucketsContainer; Level: Integer; out ABucket : PBucket): Boolean;
var
  BucketIndex, i : Integer;
begin
  if AValue = nil then
    raise EPointerContainer.Create(STR_KEYCANTBENIL);
  for i := 0 to FAttemptsPerBucket - 1 do
  begin
    BucketIndex := BucketIndexFromHash(AHash, Level + i);
    {$IFDEF POINTERCONTAINER_COLLECTSTATS}
    inc(FStats.ComparisonOnSearchCount);
    {$ENDIF}
    if ABucketContainer^.Buckets[BucketIndex].Value = AValue then
    begin
      Result := True;
      ABucket := @ABucketContainer^.Buckets[BucketIndex];
      exit;
    end
  end;
  if ABucketContainer^.Buckets[BucketIndex].Child <> nil then
    Result := InternalFind(AValue, AHash, ABucketContainer^.Buckets[BucketIndex].Child, Level + 1, ABucket)
  else
  begin
    Result := False;
    ABucket := nil;
  end;
end;

function TPointerContainer.IterateNextBucket(ReturnFromChildren: Boolean): Boolean;
begin
  if FCurContainer^.IterateCurIndex >= BucketsPerContainer then
  begin
    FCurContainer := FCurContainer^.Parent;
    if FCurContainer <> nil then
      Result := IterateNextBucket(True)
    else Result := False;
    exit;
  end;
  if ReturnFromChildren then
  begin
    if FCurContainer^.Buckets[FCurContainer^.IterateCurIndex].Value <> nil then
      begin
        Result := True;
        exit;
      end;
    inc(FCurContainer^.IterateCurIndex);
  end;
  while FCurContainer^.IterateCurIndex< BucketsPerContainer do
  begin
    if FCurContainer^.Buckets[FCurContainer^.IterateCurIndex].Child <> nil then
    begin
      FCurContainer := FCurContainer^.Buckets[FCurContainer^.IterateCurIndex].Child;
      FcurContainer^.IterateCurIndex := 0;
      Result := IterateNextBucket(False);
      if Result then
        exit;
    end
    else if FCurContainer^.Buckets[FCurContainer^.IterateCurIndex].Value <> nil then
    begin
      Result := True;
      exit;
    end;
    inc(FCurContainer^.IterateCurIndex);
  end;
  if FCurContainer^.Parent <> nil then
  begin
    FCurContainer := FCurContainer^.Parent;
    Result := IterateNextBucket(True);
  end
  else Result := False;
end;

procedure TPointerContainer.SetMultipleAttemptsPerBucketContainer(Value: Boolean
  );
begin
  FMultipleAttemptsPerBucketContainer := Value;
  if Value then
    FAttemptsPerBucket := LevelsCycle
  else FAttemptsPerBucket := 1;
end;

(* Original code of SuperFastHash written in C by Paul Hsieh*)
function SuperFastHash(data: PByte; Len: Cardinal): Cardinal;
var
  tmp : Cardinal;
  rem : integer;
  i : integer;
  CurCardinal : Cardinal;
begin
  Result := len;
  if (len <= 0) or (data = nil)
    then
    begin
      Result := 0;
      exit;
    end;
  rem := len and 3;
  len := len shr 2;
  { Main loop }
  for i := len downto 1 do
    begin
      CurCardinal := PCardinal (data)^;
      inc (Result, PWord (@CurCardinal)^);
      tmp  := (PWord (@PByte(@CurCardinal) [2])^ shl 11) xor Result;
      Result := (Result shl 16) xor tmp;
      inc (Data, sizeof (Cardinal));
      inc (Result, Result shr 11);
    end;
  { Handle end cases }
  case rem of
    3 :
      begin
        CurCardinal := PWord (data)^ shl 8 + byte (data [sizeof (Word)]);
        inc (Result, PWord (@CurCardinal)^);
        Result := Result xor (Result shl 16);
        Result := Result xor (byte (PByte (@CurCardinal) [sizeof (Word)]) shl 18);
        inc (Result, Result shr 11);
      end;
    2 :
      begin
        CurCardinal := PWord (data)^;
        inc (Result, PWord (@CurCardinal)^);
        Result := Result xor (Result shl 11);
        inc (Result, Result shr 17);
      end;
    1 :
      begin
        inc (Result, byte (data^));
        Result := Result xor (Result shl 10);
        inc (Result, Result shr 1);
      end;
  end;

  { Force "avalanching" of final 127 bits }
  Result := Result xor (Result shl 3);
  inc (Result, Result shr 5);
  Result := Result xor (Result shl 4);
  inc (Result, Result shr 17);
  Result := Result xor (Result shl 25);
  inc (Result, Result shr 6);
end;

end.

