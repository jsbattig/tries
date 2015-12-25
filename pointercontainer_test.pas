unit PointerContainer_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, PointerContainer;

type

  { TTestPointerContainer }

  TTestPointerContainer= class(TTestCase)
  private
    FPointers : TPointerContainer;
    procedure InternalAddPointers(var APointers : array of Pointer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddOneSuccess;
    procedure TestAddALotAndFindThemSuccess;
    procedure TestAddManyFindThemRemoveSomeAndAddMoreSuccess;
    procedure TestAddDuplicatePointerFail;
    procedure TestAddDuplicatePointerAfterRemovalSuccess;
    procedure TestValuesIterateSequentiallyAndVerifyThemAllSuccess;
    procedure TestRandomAccessSuccess;
  end;

implementation

uses
  Dialogs;

procedure TTestPointerContainer.TestAddOneSuccess;
begin
  FPointers.Add(Self);
  CheckEquals(1, FPointers.Count, 'FPointers.Count shoul be equals to 1');
end;

procedure TTestPointerContainer.TestAddALotAndFindThemSuccess;
var
  Pointers : array of Pointer;
  i, j : integer;
begin
  for j := 0 to 1 do
  begin
    FPointers.Clear;
    FPointers.CheckDuplicateOnInsertion := False;
    FPointers.MultipleAttemptsPerBucketContainer:= j = 1;
    SetLength(Pointers, 256 * 1024);
    InternalAddPointers(Pointers);
    {ShowMessage(IntToStr(FPointers.Stats.BucketContainerCount) + ' ' +
                IntToStr(FPointers.Stats.Depth) + ' ' +
                IntToStr(FPointers.Stats.BucketContainerCount * sizeof(TBucketsContainer)) + ' ' +
                FloatToStr(100 * FPointers.Count / (FPointers.Stats.BucketContainerCount * BucketsPerContainer)) + ' ' +
                IntToStr(FPointers.Stats.AttemptsToInsertOnBucketCount));}
    for i := low(PointerS) to high(Pointers) do
      Check(FPointers.Find(Pointers[i]), 'Could not find pointer');
    for i := low(Pointers) to high(Pointers) do
      FreeMem(Pointers[i]);
  end;
end;

procedure TTestPointerContainer.TestAddManyFindThemRemoveSomeAndAddMoreSuccess;
var
  Pointers, Pointers2 : array of Pointer;
  i : integer;
begin
  SetLength(Pointers, 1024);
  InternalAddPointers(Pointers);
  for i := low(Pointers) to high(Pointers) do
    if i mod 2 = 0 then
    begin
      FPointers.Remove(Pointers[i]);
      FreeMem(Pointers[i]);
      Pointers[i] := nil;
    end;
  CheckEquals(length(Pointers) div 2, FPointers.Count, 'FPointers.Count doesn''t match expect value');
  SetLength(Pointers2, 1024);
  InternalAddPointers(Pointers2);
  CheckEquals(length(Pointers) div 2 + length(Pointers2), FPointers.Count, 'FPointers.Count doesn''t match expect value');
  for i := low(Pointers) to high(Pointers) do
    if Pointers[i] <> nil then
      FreeMem(Pointers[i]);
  for i := low(Pointers2) to high(Pointers2) do
    if Pointers2[i] <> nil then
      FreeMem(Pointers2[i]);
end;

procedure TTestPointerContainer.TestAddDuplicatePointerFail;
begin
  FPointers.CheckDuplicateOnInsertion := True;
  FPointers.Add(Self);
  try
    FPointers.Add(Self);
    Fail('Should have triggered exception adding duplicate value');
  except
    on EPointerContainer do {};
  end;
end;

procedure TTestPointerContainer.TestAddDuplicatePointerAfterRemovalSuccess;
begin
  FPointers.CheckDuplicateOnInsertion := True;
  FPointers.Add(Self);
  FPointers.Add(FPointers);
  FPointers.Remove(Self);
  FPointers.Add(Self);
end;

procedure TTestPointerContainer.TestValuesIterateSequentiallyAndVerifyThemAllSuccess;
var
  Pointers : array of Pointer;
  i, Idx : integer;
  VerifyList : TList;
  Item : Pointer;
begin
  VerifyList := TList.Create;
  try
    SetLength(Pointers, 1024);
    InternalAddPointers(Pointers);
    for i := low(Pointers) to high(Pointers) do
      VerifyList.Add(Pointers[i]);
    for i := 0 to FPointers.Count - 1 do
      begin
        Item := FPointers[i];
        Check(Item <> nil, 'Item should be <> nil');
        Idx := VerifyList.IndexOf(Item);
        CheckNotEquals(-1, Idx, 'Item should be found in VerifyList');
        VerifyList.Delete(Idx);
      end;
    CheckEquals(0, VerifyList.Count, 'VerifyEquals.Count should be zero at the end of the test');
    Check(FPointers.Stats.ComparisonOnSearchCount > FPointers.Count * 15, 'Comparisons must be 15 times more than Count of Pointers');
    Check(FPointers.Stats.ComparisonOnSearchCount < FPointers.Count * 16, 'Comparisons must be less than 16 times than Count of Pointers');
  finally
    VerifyList.Free;
  end;
  for i := low(Pointers) to high(Pointers) do
    if Pointers[i] <> nil then
      FreeMem(Pointers[i]);
end;

procedure TTestPointerContainer.TestRandomAccessSuccess;
var
  Pointers : array of Pointer;
  i : integer;
  VerifyList : TList;
  Item : Pointer;
begin
  VerifyList := TList.Create;
  try
    SetLength(Pointers, 1024);
    InternalAddPointers(Pointers);
    for i := 0 to FPointers.Count - 1 do
      begin
        Item := FPointers[i];
        Check(Item <> nil, 'Item should be <> nil');
        VerifyList.Add(Item);
      end;
    for i := FPointers.Count - 1 downto 0 do
      Check(VerifyList[i] = FPointers[i], 'Items in intermediate list should match');
  finally
    VerifyList.Free;
  end;
  for i := low(Pointers) to high(Pointers) do
    if Pointers[i] <> nil then
      FreeMem(Pointers[i]);
end;

procedure TTestPointerContainer.InternalAddPointers(
  var APointers: array of Pointer);
var
  i : integer;
  InitialCount : Integer;
begin
  InitialCount := FPointers.Count;
  for i := low(APointers) to high(APointers) do
  begin
    GetMem(APointers[i], 64);
    FPointers.Add(APointers[i]);
  end;
  CheckEquals(length(APointers), FPointers.Count - InitialCount, 'Number of expected elements doesn''t match');
  for i := low(APointers) to high(APointers) do
    Check(FPointers.Find(APointers[i]), 'Pointer not found');
end;

procedure TTestPointerContainer.SetUp;
begin
  FPointers := TPointerContainer.Create;
end;

procedure TTestPointerContainer.TearDown;
begin
  FPointers.Free;
end;

initialization
  RegisterTest(TTestPointerContainer);
end.

