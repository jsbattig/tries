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

unit Test_StringHashTrie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ELSE}
{$IF CompilerVersion >= 22}
  {$DEFINE HasGenerics}
{$IFEND}
{$ENDIF}

interface

uses
  Classes, SysUtils,
  {$IFDEF FPC}
  fpcunit, testregistry,
  {$ELSE}
  TestFramework, {$IFNDEF VER180} AnsiStrings, {$ENDIF}
  {$ENDIF}
  StringHashTrie;

type
  { TStringHashTrieTest }

  TStringHashTrieTest= class(TTestCase)
  private
    FStrHashTrie : TStringHashTrie;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
    procedure TraverseMeth({%H-}UserData: Pointer; Key: PAnsiChar; Data: TObject; var
        {%H-}Done: Boolean);
    {$IFDEF UNICODE}
    procedure TraverseMethUnicode({%H-}UserData: Pointer; Key: PChar; Data:
        TObject; var Done: Boolean);
    {$ENDIF}
  published
    procedure Add15KGUIDsRemoveHalfPackAndFindEachOne;
    procedure AddFromTestDataFile;
    procedure TestCreate;
    procedure TestAddAndFind;
    procedure TestAddRemoveAndReAddMultipleTimes;
    procedure TestAddSeveralAndFind;
    procedure TestAddReplaceAndFind;
    procedure TestAddAndTraverse;
    procedure TestAddAndFindCaseInsensitive;
    procedure TestAddAndFindManyEntries;
    procedure TestAddIterateAndFindManyEntries;
    procedure TestAddAndFindHash16;
    procedure TestAddAndFindHash64;
    procedure TestAddFindAndRemoveManyEntries;
    {$IFDEF HasGenerics}
    procedure TestAddAndFindManyEntriesUsingTDictionary;
    procedure TestAddIterateAndFindManyEntriesTDictionary;
    procedure TestAddAndFindManyEntriesFastTDictionary;
    {$ENDIF}
    procedure TestRemoveAndPackHash32;
    procedure TestIterator;
    procedure TestAutoFreeValue;
    procedure TestAddTwoValuesAndIterate;
    procedure TestAddAndFindManyEntriesFast;
    procedure TestAddAndFindManyEntriesFastUsing16bitsHash;
    {$IFDEF UNICODE}
    procedure TestUnicodeChars;
    procedure TestAddAndTraverseUnicode;
    procedure TestAddFindAndRemoveManyEntriesUsingTDictionary;
    procedure TestAddIterateAndFindManyEntriesHash32;
    procedure TestRemoveAndPack;
    {$ENDIF}
    procedure TestAddIterateRemovingCurrentNode;
    procedure TestStressRemoveAndPack;
  end;

implementation

uses
  Hash_Trie {$IFDEF HasGenerics}, Generics.Collections {$ENDIF};

procedure TStringHashTrieTest.Add15KGUIDsRemoveHalfPackAndFindEachOne;
const
  Loops = 15000;
  Scenario : array[0..3] of Integer = (2, 3740, 14998, 2);
var
  i, j : integer;
  List : TStringList;
  Found : Boolean;
begin
  if not FileExists('..\..\..\GUIDs.txt') then
    exit;
  for j := 0 to 3 do
  begin
    case j of
      0 : ; // use default FStrHashTrie
      1 :
      begin
        FStrHashTrie.Free;
        FStrHashTrie := TStringHashTrie.Create(16, True);
      end;
      2 :
      begin
        FStrHashTrie.Free;
        FStrHashTrie := TStringHashTrie.Create(32, False);
      end;
      3 :
      begin
        FStrHashTrie.Free;
        FStrHashTrie := TStringHashTrie.Create(20, True);
      end;
    end;
    List := TStringList.Create;
    try
      List.LoadFromFile('..\..\..\GUIDs.txt');
      for i := 1 to Loops do
      begin
        Check(FStrHashTrie.Add(List[i - 1]), 'Adding item');
      end;
      for i := 1 to Loops do
      begin
        Check(FStrHashTrie.Find(List[i - 1]), Format('First find test %d', [i - 1]));
      end;
      for i := 1 to Loops do
      begin
        Check(FStrHashTrie.Find(List[i - 1]), Format('Second find test %d', [i - 1]));
        if i mod 2 = 0 then
          Check(FStrHashTrie.Remove(List[i - 1]), 'Removing item');
        Check(FStrHashTrie.Find(List[Scenario[j]]), Format('Missing item %d after removing item %d', [Scenario[j], i - 1]));
      end;
      FStrHashTrie.Pack;
      Check(FStrHashTrie.Find(List[Scenario[j]]), Format('Missing item %d after pack', [Scenario[j]]));
      for i := 1 to Loops do
      begin
        Found := FStrHashTrie.Find(List[i - 1]);
        Check(((i mod 2 = 0) and (not Found)) or ((i mod 2 <> 0) and Found));
      end;
      for i := 1 to Loops do
      begin
        if i mod 2 = 0 then
        begin
          Check(FStrHashTrie.Find(List[Scenario[j]]), Format('Missing item %d before adding item %d', [Scenario[j], i - 1]));
          Check(FStrHashTrie.Add(List[i - 1]), Format('Adding again item %d', [i - 1]));
          Check(FStrHashTrie.Find(List[Scenario[j]]), Format('Missing item %d after adding item %d', [Scenario[j], i - 1]));
        end;
      end;
      Check(FStrHashTrie.Find(List[3740]), Format('Missing item %d after adding items', [Scenario[j]]));
      for i := 1 to Loops do
      begin
        Check(FStrHashTrie.Find(List[i - 1]), Format('Find after re-adding %d', [i - 1]));
      end;
    finally
      List.Free;
    end;
  end;
end;

procedure TStringHashTrieTest.AddFromTestDataFile;
var
  List : TStringList;
  i, j, k : integer;
begin
  if (not FileExists('..\..\..\TestData.txt')) or
     (not FileExists('..\..\..\TestData_2.txt')) then
    exit;
  List := TStringList.Create;
  try
    for k := 1 to 50 do
      for j := 0 to 3 do
      begin
        if j <= 1 then
          List.LoadFromFile('..\..\..\TestData.txt')
        else
          List.LoadFromFile('..\..\..\TestData_2.txt');
        if j in [1, 3] then
        begin
          FStrHashTrie.Free;
          FStrHashTrie := TStringHashTrie.Create(16, True);
        end;
        FStrHashTrie.AutoFreeValue := True;
        FStrHashTrie.AutoFreeValueMode := afmFree;
        for i := 0 to List.Count - 1 do
          FStrHashTrie.Add(List[i], TObject.Create);
        for i := 0 to List.Count - 1 do
          Check(FStrHashTrie.Find(List[i]));
        for i := 0 to List.Count - 1 do
          if i mod k = 0 then
          begin
            Check(FStrHashTrie.Find(List[i]), Format('Element #%d "%s" not found. k=%d', [i, List[i], k]));
            Check(FStrHashTrie.Remove(List[i]), Format('Error removing element #%d "%s"', [i, List[i]]));
          end;
        FStrHashTrie.Pack;  
        for i := 0 to List.Count - 1 do
          if i mod k = 0 then
          begin
            Check(not FStrHashTrie.Find(List[i]), Format('Element #%d "%s" found?', [i, List[i]]));
            Check(FStrHashTrie.Add(List[i], TObject.Create), Format('Element #%d "%s" re added', [i, List[i]]));
            Check(FStrHashTrie.Find(List[i]), Format('Element #%d "%s" not found?', [i, List[i]]));
          end;
        for i := 0 to List.Count - 1 do
          Check(FStrHashTrie.Find(List[i]));
      end;
  finally
    List.Free;
  end;
end;

procedure TStringHashTrieTest.TestCreate;
begin
  Check(FStrHashTrie <> nil, 'Failed to create FStrHashTrie');
end;

procedure TStringHashTrieTest.TestAddAndFind;
var
  Value : Pointer;
begin
  FStrHashTrie.Add('Hello World', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
end;

procedure TStringHashTrieTest.TestAddAndFindManyEntries;
const
  Count = 1024 * 64;
var
  List : TStringList;
  i : integer;
  AIterator : THashTrieIterator;
  AKey : AnsiString;
  AValue : Pointer;
begin
  List := TStringList.Create;
  try
    for i := 0 to Count - 1 do
    begin
      List.Add(IntToStr(i) + 'hello ' + IntToStr(Count - i));
      FStrHashTrie.Add(AnsiString(List[i]), {%H-}Pointer(i));
    end;
    CheckEquals(Count, FStrHashTrie.Count, 'Count doesn''t match');
    List.Sorted := True;
    FStrHashTrie.InitIterator(AIterator);
    while FStrHashTrie.Next(AIterator, AKey, AValue) do
    begin
      i := List.IndexOf(AKey);
      if i = -1 then
        CheckEquals('', AKey);
      CheckNotEquals(-1, i, 'Key not found in original list');
      CheckEquals(IntToStr({%H-}NativeInt(AValue)) + 'hello ' + IntToStr(Count - {%H-}NativeInt(AValue)), AKey, 'Expected key value doesn''t match');
      List.Delete(i);
    end;
    if List.Count > 0 then
      CheckEquals('', List.CommaText);
  finally
    List.Free;
  end;
end;

procedure TStringHashTrieTest.TestAddIterateAndFindManyEntries;
const
  Count = 1024 * 1024 * 1;
var
  i, Cnt : integer;
  AIterator : THashTrieIterator;
  AKey : AnsiString;
  AValue : Pointer;
begin
  for i := 0 to Count - 1 do
    FStrHashTrie.Add(AnsiString(IntToStr(i)) + 'hello', Self);
  Check(FStrHashTrie.Find('0hello'), 'Should find first element');
  FStrHashTrie.InitIterator(AIterator);
  Cnt := 0;
  while FStrHashTrie.Next(AIterator, AKey, AValue) do
  begin
    Check(FStrHashTrie.Find(AKey, AValue), 'Item not found');
    inc(Cnt);
  end;
  CheckEquals(Count, Cnt, 'Count of iterated values doesn''t match');
end;

procedure TStringHashTrieTest.TestAddAndFindHash16;
var
  Value : Pointer;
begin
  FStrHashTrie.Free;
  FStrHashTrie := TStringHashTrie.Create(16);
  FStrHashTrie.Add('Hello World', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
end;

procedure TStringHashTrieTest.TestAddAndFindHash64;
var
  Value : Pointer;
begin
  FStrHashTrie.Free;
  FStrHashTrie := TStringHashTrie.Create(64);
  FStrHashTrie.Add('Hello World', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
end;

procedure TStringHashTrieTest.TestRemoveAndPackHash32;
var
  Value : Pointer;
begin
  FStrHashTrie.Free;
  FStrHashTrie := TStringHashTrie.Create(32);
  FStrHashTrie.Add('Hello World', Self);
  FStrHashTrie.Add('Hello World 2', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  FStrHashTrie.Pack;
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  FStrHashTrie.Remove('Hello World');
  Check(not FStrHashTrie.Find('Hello World', Value), 'Item found');
  FStrHashTrie.Pack;
end;

procedure TStringHashTrieTest.TestIterator;
var
  AIterator : THashTrieIterator;
  AKey : AnsiString;
  AValue : Pointer;
begin
  FStrHashTrie.Add('Hello World', Self);
  FStrHashTrie.InitIterator(AIterator);
  Check(FStrHashTrie.Next(AIterator, AKey, AValue), 'Value of FStrHashTrie.Next doesn''t match');
  CheckEquals('Hello World', AKey, 'AKey doesn''t match');
  Check(AValue = Pointer(Self), 'Value of AValue doesn''t match');
  Check(not FStrHashTrie.Next(AIterator, AKey, AValue), 'Value of FStrHashTrie.Next doesn''t match');
end;

procedure TStringHashTrieTest.TestAutoFreeValue;
var
  Value : Pointer;
  Obj : TObject;
begin
  GetMem(Value, 1024);
  FStrHashTrie.AutoFreeValue := True;
  FStrHashTrie.AutoFreeValueMode := afmFreeMem;
  FStrHashTrie.Add('Hello World', Value);
  FStrHashTrie.Clear;
  FStrHashTrie.AutoFreeValueMode := afmFree;
  Obj := TObject.Create;
  FStrHashTrie.Add('Hello World', Obj);
  Obj := TObject.Create;
  FStrHashTrie.Add('Hello World', Obj);
  FStrHashTrie.Clear;
end;

procedure TStringHashTrieTest.TestAddTwoValuesAndIterate;
var
  AIterator : THashTrieIterator;
  AKey : AnsiString;
  AValue : Pointer;
begin
  FStrHashTrie.Add('Hello World', Self);
  FStrHashTrie.Add('Hello World 2', Self);
  FStrHashTrie.InitIterator(AIterator);
  Check(FStrHashTrie.Next(AIterator, AKey, AValue), 'Value of FStrHashTrie.Next doesn''t match');
  CheckEquals('Hello World', AKey, 'AKey doesn''t match');
  Check(FStrHashTrie.Next(AIterator, AKey, AValue), 'Value of FStrHashTrie.Next doesn''t match');
  CheckEquals('Hello World 2', AKey, 'AKey doesn''t match');
  Check(not FStrHashTrie.Next(AIterator, AKey, AValue), 'Value of FStrHashTrie.Next doesn''t match');
end;

procedure TStringHashTrieTest.SetUp;
begin
  FStrHashTrie := TStringHashTrie.Create;
end;

procedure TStringHashTrieTest.TearDown;
begin
  if FStrHashTrie = nil then
    exit;
  FStrHashTrie.Pack;
  FStrHashTrie.Free;
end;

procedure TStringHashTrieTest.TestAddRemoveAndReAddMultipleTimes;
var
  Value : Pointer;
  i : integer;
begin
  for i := 1 to 200 do
  begin
    FStrHashTrie.Add('Hello World');
    Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
    FStrHashTrie.Remove('Hello World');
    Check(not FStrHashTrie.Find('Hello World', Value), 'Item found');
  end;
end;

procedure TStringHashTrieTest.TestAddSeveralAndFind;
var
  Value : Pointer;
begin
  FStrHashTrie.Add('Hello World', Self);
  FStrHashTrie.Add('Hello World 2', Self);
  FStrHashTrie.Add('Hello World 3', Self);
  FStrHashTrie.Add('Hello World 4', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
end;

procedure TStringHashTrieTest.TestAddReplaceAndFind;
var
  Value : Pointer;
begin
  FStrHashTrie.Add('Hello World', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
  FStrHashTrie.Add('Hello World', FStrHashTrie);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(Value = Pointer(FStrHashTrie), 'Item found doesn''t match expected value');
  CheckEquals(1, FStrHashTrie.Count, 'There should be only one item in the hashtrie');
  Check(FStrHashTrie.Remove('Hello World'), 'Remove should return true');
  Check(not FStrHashTrie.Find('Hello World', Value), 'Item found');
end;

procedure TStringHashTrieTest.TestAddAndTraverse;
begin
  FStrHashTrie.Add('Hello World', Self);
  FStrHashTrie.Traverse(nil, {$IFDEF FPC}@{$ENDIF}TraverseMeth);
end;

procedure TStringHashTrieTest.TestAddAndFindCaseInsensitive;
var
  Value : Pointer;
begin
  FStrHashTrie.CaseInsensitive := True;
  FStrHashTrie.Add(AnsiString('Hello World'), Pointer(Self));
  Check(FStrHashTrie.Find(AnsiString('hello world'), Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
end;

procedure TStringHashTrieTest.TestAddFindAndRemoveManyEntries;
const
  Count = 1024 * 1024 * 1;
var
  List : TStringList;
  i : integer;
begin
  List := TStringList.Create;
  try
    for i := 0 to Count - 1 do
    begin
      List.Add(IntToStr(i) + 'hello ' + IntToStr(Count - i));
      FStrHashTrie.Add(AnsiString(List[i]), {%H-}Pointer(i));
    end;
    CheckEquals(Count, FStrHashTrie.Count, 'Count doesn''t match');
    for i := 0 to List.Count - 1 do
      Check(FStrHashTrie.Find(List[i]), 'Item not found');
    for i := 0 to List.Count - 1 do
      Check(FStrHashTrie.Remove(List[i]), 'Failed to remove item ' + List[i]);
    CheckEquals(0, FStrHashTrie.Count);
  finally
    List.Free;
  end;
end;

{$IFDEF HasGenerics}
procedure TStringHashTrieTest.TestAddAndFindManyEntriesFastTDictionary;
const
  Count = 1024 * 1024 * 1;
var
  i : integer;
  FDict : TDictionary<AnsiString, Pointer>;
  AValue : Pointer;
begin
  FDict := TDictionary<AnsiString, pointer>.Create;
  try
    for i := 0 to Count - 1 do
      FDict.Add(AnsiString(IntToStr(i)) + 'hello', Self);
    for i := 0 to Count - 1 do
      Check(FDict.TryGetValue(AnsiString(IntToStr(i)) + 'hello', AValue), 'Item not found');
  finally
    FDict.Free;
  end;
end;

procedure TStringHashTrieTest.TestAddAndFindManyEntriesUsingTDictionary;
const
  Count = 1024 * 64;
var
  List : TStringList;
  i : integer;
  AKey : AnsiString;
  AValue : Pointer;
  FDict : TDictionary<AnsiString, Pointer>;
  Enum : TPair<AnsiString, Pointer>;
begin
  FDict := TDictionary<AnsiString, Pointer>.Create;
  try
    List := TStringList.Create;
    try
      for i := 0 to Count - 1 do
      begin
        List.Add(IntToStr(i) + 'hello ' + IntToStr(Count - i));
        FDict.Add(AnsiString(List[i]), Pointer(i));
      end;
      CheckEquals(Count, FDict.Count, 'Count doesn''t match');
      List.Sorted := True;
      for Enum in FDict do
      begin
        AKey := Enum.Key;
        AValue := Enum.Value;
        i := List.IndexOf(AKey);
        if i = -1 then
          CheckEquals('', AKey);
        CheckNotEquals(-1, i, 'Key not found in original list');
        CheckEquals(IntToStr(NativeInt(AValue)) + 'hello ' + IntToStr(Count - NativeInt(AValue)), AKey, 'Expected key value doesn''t match');
        List.Delete(i);
      end;
      if List.Count > 0 then
        CheckEquals('', List.CommaText);
    finally
      List.Free;
    end;
  finally
    FDict.Free;
  end;
end;

procedure TStringHashTrieTest.TestAddIterateAndFindManyEntriesTDictionary;
const
  Count = 1024 * 1024 * 1;
var
  i, Cnt : integer;
  AValue : Pointer;
  FDict : TDictionary<AnsiString, Pointer>;
  Enum : TPair<AnsiString, Pointer>;
begin
  FDict := TDictionary<AnsiString, Pointer>.Create;
  try
    for i := 0 to Count - 1 do
      FDict.Add(AnsiString(IntToStr(i)) + 'hello', Self);
    Cnt := 0;
    for Enum in FDict do
    begin
      Check(FDict.TryGetValue(Enum.Key, AValue), 'Item not found');
      inc(Cnt);
    end;
    CheckEquals(Count, Cnt, 'Count of iterated values doesn''t match');
  finally
    FDict.Free;
  end;
end;
{$ENDIF}

{$IFDEF UNICODE}
procedure TStringHashTrieTest.TestUnicodeChars;
var
  Value : Pointer;
begin
  FStrHashTrie.Add('Привет мир', Self);
  Check(FStrHashTrie.Find('Привет мир', Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
end;
{$ENDIF}

procedure TStringHashTrieTest.TraverseMeth(UserData: Pointer; Key: PAnsiChar;
    Data: TObject; var Done: Boolean);
begin
  CheckEquals('Hello World', {$IFDEF UNICODE}AnsiStrings.{$ENDIF}StrPas(Key), 'Item not found');
  Check(Data = TObject(Self), 'Item found doesn''t match expected value');
end;

procedure TStringHashTrieTest.TestAddAndFindManyEntriesFast;
const
  Count = 1024 * 1024 * 1;
var
  i : integer;
begin
  FStrHashTrie.Free;
  FStrHashTrie := TStringHashTrie.Create(20, True);
  for i := 0 to Count - 1 do
    FStrHashTrie.Add(AnsiString(IntToStr(i)) + 'hello', Self);
  for i := 0 to Count - 1 do
    FStrHashTrie.Find(AnsiString(IntToStr(i)) + 'hello');
end;

procedure TStringHashTrieTest.TestAddAndFindManyEntriesFastUsing16bitsHash;
const
  Count = 1024 * 1024 * 1;
var
  i : integer;
begin
  FStrHashTrie.Free;
  FStrHashTrie := TStringHashTrie.Create(16);
  for i := 0 to Count - 1 do
    FStrHashTrie.Add(AnsiString(IntToStr(i)) + 'hello', Self);
  for i := 0 to Count - 1 do
    FStrHashTrie.Find(AnsiString(IntToStr(i)) + 'hello');
end;

{$IFDEF UNICODE}
procedure TStringHashTrieTest.TestAddAndTraverseUnicode;
begin
  FStrHashTrie.Add('Привет мир', Self);
  FStrHashTrie.Traverse(nil, TraverseMethUnicode);
end;

procedure TStringHashTrieTest.TestAddFindAndRemoveManyEntriesUsingTDictionary;
const
  Count = 1024 * 1024 * 1;
var
  List : TStringList;
  i : integer;
  FDict : TDictionary<AnsiString, pointer>;
  AValue : Pointer;
begin
  FDict := TDictionary<AnsiString, pointer>.Create;
  try
    List := TStringList.Create;
    try
      for i := 0 to Count - 1 do
      begin
        List.Add(IntToStr(i) + 'hello ' + IntToStr(Count - i));
        FDict.Add(AnsiString(List[i]), {%H-}Pointer(i));
      end;
      CheckEquals(Count, FDict.Count, 'Count doesn''t match');
      for i := 0 to List.Count - 1 do
        Check(FDict.TryGetValue(AnsiString(List[i]), AValue), 'Item not found');
      for i := 0 to List.Count - 1 do
        FDict.Remove(AnsiString(List[i]));
      CheckEquals(0, FDict.Count);
    finally
      List.Free;
    end;
  finally
    FDict.Free;
  end;
end;

procedure TStringHashTrieTest.TestAddIterateAndFindManyEntriesHash32;
const
  Count = 1024 * 1024;
var
  i, Cnt : integer;
  AIterator : THashTrieIterator;
  AKey : AnsiString;
  AValue : Pointer;
begin
  FStrHashTrie.Free;
  FStrHashTrie := TStringHashTrie.Create(32);
  for i := 0 to Count - 1 do
    FStrHashTrie.Add(AnsiString(IntToStr(i)) + 'hello', Self);
  Check(FStrHashTrie.Find('0hello'), 'Should find first element');
  FStrHashTrie.InitIterator(AIterator);
  Cnt := 0;
  while FStrHashTrie.Next(AIterator, AKey, AValue) do
  begin
    Check(FStrHashTrie.Find(AKey, AValue), 'Item not found');
    inc(Cnt);
  end;
  CheckEquals(Count, Cnt, 'Count of iterated values doesn''t match');
end;

procedure TStringHashTrieTest.TestAddIterateRemovingCurrentNode;
const
  LOOPS = 100000;
var
  i, cnt : integer;
  GUID : TGUID;
  It : THashTrieIterator;
  s : AnsiString;
  v : Pointer;
begin
  for i := 1 to LOOPS do
  begin
    CreateGUID(GUID);
    FStrHashTrie.Add(GUIDToString(GUID) + '-' + IntToStr(i));
  end;
  FStrHashTrie.InitIterator(It);
  cnt := 0;
  while FStrHashTrie.Next(It, s, v) do
  begin
    inc(cnt);
    FStrHashTrie.RemoveCurrentNode(It);
  end;
  CheckEquals(LOOPS, cnt, 'Count of loops must match');
  FStrHashTrie.Pack;
  CheckEquals(0, FStrHashTrie.Count, 'There should be no nodes left');
end;

procedure TStringHashTrieTest.TestRemoveAndPack;
var
  Value : Pointer;
begin
  FStrHashTrie.Add('Hello World', Self);
  FStrHashTrie.Add('Hello World 2', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  FStrHashTrie.Pack;
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  FStrHashTrie.Remove('Hello World');
  Check(not FStrHashTrie.Find('Hello World', Value), 'Item found');
  FStrHashTrie.Pack;
end;

procedure TStringHashTrieTest.TraverseMethUnicode({%H-}UserData: Pointer; Key:
    PChar; Data: TObject; var Done: Boolean);
begin
  CheckEquals('Привет мир', StrPas(Key), 'Item not found');
  Check(Data = TObject(Self), 'Item found doesn''t match expected value');
end;
{$ENDIF}

procedure TStringHashTrieTest.TestStressRemoveAndPack;
var
  s : AnsiString;
  i, k : Integer;
begin
  for k := 0 to 1 do
    begin
      case k of
        0 : { keep going };
        1 : FStrHashTrie := TStringHashTrie.Create(16, True);  
      end;
      for i := 0 to 100000 - 1 do
      begin
        s := AnsiString(Format('%d Hello %d', [Random(10000), Random(10000)]));
        FStrHashTrie.Add(s);
        if i mod 10 = 0 then
          FStrHashTrie.Remove(s);
        if i mod 100 = 0 then
          FStrHashTrie.Pack;
      end;
      FreeAndNil(FStrHashTrie);
    end;
end;

initialization
  {$IFDEF FPC}
  RegisterTest(TStringHashTrieTest);
  {$ELSE}
  RegisterTest(TStringHashTrieTest.Suite);
  {$ENDIF}
end.

