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

unit PointerTrie_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, PointerTrie, Trie;

type

  { TTestPointerTrie }

  TTestPointerTrie= class(TTestCase)
  private
    procedure InternalAddPointers(var APointers : array of Pointer);
  protected
    FPointerTrie : TPointerTrie;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCreateSuccess;
    procedure TestAddPointerSuccess;
    procedure TestAddDuplicatePointerFailure;
    procedure TestAddPointerAndFindSuccess;
    procedure TestAddPointerAndFindNonExistingPointerFailure;
    procedure TestAddALotOfPointersAndFindThemSuccess;
    procedure TestAddDuplicatePointerAfterRemovalSuccess;
    procedure TestAddTwoPointersIterateSuccess;
    procedure TestAddALotOfPointersIterateThemAndCheckThem;
    procedure TestRandomAccessSuccess;
    procedure TestPackSuccess;
    procedure TestPackStressSuccess;
  end;

implementation

uses
  Dialogs;

procedure TTestPointerTrie.InternalAddPointers(
  var APointers: array of Pointer);
var
  i : integer;
  InitialCount : Integer;
begin
  InitialCount := FPointerTrie.Count;
  for i := low(APointers) to high(APointers) do
  begin
    GetMem(APointers[i], 32);
    FPointerTrie.Add(APointers[i]);
  end;
  CheckEquals(length(APointers), FPointerTrie.Count - InitialCount, 'Number of expected elements doesn''t match');
  for i := low(APointers) to high(APointers) do
    Check(FPointerTrie.Find(APointers[i]), 'Pointer not found');
end;

procedure TTestPointerTrie.TestCreateSuccess;
begin
  Check(FPointerTrie <> nil, 'FPointerTrie must be <> nil');
end;

procedure TTestPointerTrie.TestAddDuplicatePointerFailure;
begin
  FPointerTrie.AllowDuplicates := False;
  FPointerTrie.Add(Self);
  try
    FPointerTrie.Add(Self);
    Fail('Expected exception EPointerTrieDuplicate');
  except
    on E : ETrieDuplicate do {};
  end;
end;

procedure TTestPointerTrie.TestAddPointerSuccess;
begin
  FPointerTrie.Add(Self);
end;

procedure TTestPointerTrie.TestAddPointerAndFindSuccess;
begin
  FPointerTrie.Add(Self);
  Check(FPointerTrie.Find(Self), 'Could not find Self in PointerTrie');
end;

procedure TTestPointerTrie.TestAddPointerAndFindNonExistingPointerFailure;
var
  p : NativeUInt;
begin
  FPointerTrie.Add(Self);
  p := NativeUInt(Self) - 1;
  Check(not FPointerTrie.Find({%H-}Pointer(p)), 'Non existing pointer should not be found');
end;

procedure TTestPointerTrie.TestAddALotOfPointersAndFindThemSuccess;
var
  Pointers : array of Pointer;
  i : integer;
begin
  SetLength(Pointers, 256 * 1024);
  InternalAddPointers(Pointers);
  {ShowMessage(IntToStr(FPointerTrie.Stats.NodeCount) + ' ' +
              IntToStr(FPointerTrie.Stats.TotalMemAlloced));}
  for i := low(Pointers) to high(Pointers) do
    try
      Check(FPointerTrie.Find(Pointers[i]), 'Could not find pointer');
    except
      Fail('Failed ' + IntToStr(i));
    end;
  CheckEquals(length(Pointers), FPointerTrie.Count, 'Number of elements mismatch');
  for i := low(Pointers) to high(Pointers) do
    FreeMem(Pointers[i]);
end;

procedure TTestPointerTrie.TestAddDuplicatePointerAfterRemovalSuccess;
begin
  FPointerTrie.AllowDuplicates := False;
  FPointerTrie.Add(Self);
  FPointerTrie.Add(FPointerTrie);
  CheckEquals(2, FPointerTrie.Count, 'Count doesn''t match');
  FPointerTrie.Remove(Self);
  CheckEquals(1, FPointerTrie.Count, 'Count doesn''t match');
  FPointerTrie.Add(Self);
  CheckEquals(2, FPointerTrie.Count, 'Count doesn''t match');
end;

procedure TTestPointerTrie.TestAddTwoPointersIterateSuccess;
var
  Iterator : TTrieIterator;
  p1, p2, p3 : Pointer;
begin
  FPointerTrie.Add(Self);
  FPointerTrie.Add(FPointerTrie);
  FPointerTrie.InitIterator(Iterator);
  p1 := FPointerTrie.Next(Iterator);
  Check((p1 = Pointer(Self)) or (p1 = Pointer(FPointerTrie)), 'p1 doesn''t match any of the two pointers in the trie');
  p2 := FPointerTrie.Next(Iterator);
  Check((p2 = Pointer(Self)) or (p2 = Pointer(FPointerTrie)), 'p2 doesn''t match any of the two pointers in the trie');
  Check(p2 <> p1, 'p2 must be <> p1');
  p3 := FPointerTrie.Next(Iterator);
  Check(p3 = nil, 'p3 should be nil');
end;

procedure TTestPointerTrie.TestAddALotOfPointersIterateThemAndCheckThem;
var
  Pointers : array of Pointer;
  i : integer;
  p : Pointer;
  It : TTrieIterator;
begin
  SetLength(Pointers, 256 * 1024);
  InternalAddPointers(Pointers);
  FPointerTrie.InitIterator(It);
  i := 0;
  repeat
    p := FPointerTrie.Next(It);
    Check((p = nil) or (FPointerTrie.Find(p)), 'Could not find pointer');
    inc(i);
  until p = nil;
  CheckEquals(FPointerTrie.Count + 1, i, 'i should be equals to FPointerTrie.Count + 1');
  for i := low(Pointers) to high(Pointers) do
    FreeMem(Pointers[i]);
end;

procedure TTestPointerTrie.TestRandomAccessSuccess;
var
  Pointers : array of Pointer;
  i : integer;
  VerifyList : TList;
  Item : Pointer;
begin
  FPointerTrie.RandomAccessMode := ramFull;
  VerifyList := TList.Create;
  try
    SetLength(Pointers, 1024);
    InternalAddPointers(Pointers);
    for i := 0 to FPointerTrie.Count - 1 do
      begin
        Item := FPointerTrie[i];
        Check(Item <> nil, 'Item should be <> nil');
        VerifyList.Add(Item);
      end;
    for i := FPointerTrie.Count - 1 downto 0 do
      Check(VerifyList[i] = FPointerTrie[i], 'Items in intermediate list should match');
  finally
    VerifyList.Free;
  end;
  for i := low(Pointers) to high(Pointers) do
    if Pointers[i] <> nil then
      FreeMem(Pointers[i]);
end;

procedure TTestPointerTrie.TestPackSuccess;
begin
  FPointerTrie.Add(Pointer($00000001));
  FPointerTrie.Add(Pointer($00000002));
  FPointerTrie.Add(Pointer($10000000));
  FPointerTrie.Pack;
  Check(FPointerTrie.Find(Pointer($00000001)), 'Pointer($00000001) not found');
  Check(FPointerTrie.Find(Pointer($00000002)), 'Pointer($0000002) not found');
  Check(FPointerTrie.Find(Pointer($10000000)), 'Pointer($10000000) not found');
  FPointerTrie.Remove(Pointer($00000001));
  Check(not FPointerTrie.Find(Pointer($00000001)), 'Pointer($00000001) found');
  Check(FPointerTrie.Find(Pointer($00000002)), 'Pointer($0000002) not found');
  Check(FPointerTrie.Find(Pointer($10000000)), 'Pointer($10000000) not found');
  FPointerTrie.Pack;
  Check(not FPointerTrie.Find(Pointer($00000001)), 'Pointer($00000001) found');
  Check(FPointerTrie.Find(Pointer($00000002)), 'Pointer($0000002) not found');
  Check(FPointerTrie.Find(Pointer($10000000)), 'Pointer($10000000) not found');
  FPointerTrie.Remove(Pointer($00000002));
  FPointerTrie.Pack;
  Check(not FPointerTrie.Find(Pointer($00000001)), 'Pointer($00000001) found');
  Check(not FPointerTrie.Find(Pointer($00000002)), 'Pointer($0000002) found');
  Check(FPointerTrie.Find(Pointer($10000000)), 'Pointer($10000000) not found');
end;

procedure TTestPointerTrie.TestPackStressSuccess;
var
  Pointers : array of Pointer;
  i : integer;
  p : Pointer;
  It : TTrieIterator;
  PointersRemoved, PointersNotRemoved : TList;
begin
  SetLength(Pointers, 1024);
  InternalAddPointers(Pointers);
  FPointerTrie.InitIterator(It);
  PointersRemoved := TList.Create;
  try
    PointersNotRemoved := TList.Create;
    try
      i := 0;
      repeat
        p := FPointerTrie.Next(It);
        if i mod 2 = 0 then
        begin
          FPointerTrie.Remove(p);
          PointersRemoved.Add(p);
        end
        else PointersNotRemoved.Add(p);
        inc(i);
      until p = nil;
      FPointerTrie.Pack;
      CheckEquals(512, FPointerTrie.Count, 'i should be equals to FPointerTrie.Count + 1');
      for i := 0 to PointersRemoved.Count - 1 do
        Check(not FPointerTrie.Find(PointersRemoved[i]), 'Pointer should not be found');
      for i := 0 to PointersNotRemoved.Count - 1 do
        Check(FPointerTrie.Find(PointersNotRemoved[i]), 'Pointer should be found');
      for i := low(Pointers) to high(Pointers) do
        FreeMem(Pointers[i]);
    finally
      PointersNotRemoved.Free;
    end;
  finally
    PointersRemoved.Free;
  end;
end;

procedure TTestPointerTrie.SetUp;
begin
  FPointerTrie := TPointerTrie.Create;
end;

procedure TTestPointerTrie.TearDown;
begin
  FPointerTrie.Free;
end;

initialization
  RegisterTest(TTestPointerTrie);
end.

