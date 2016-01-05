unit Test_StringHashTrie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

{$IF CompilerVersion >= 22}
  {$DEFINE HasGenerics}
{$IFEND}

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
  published
    procedure TestCreate;
    procedure TestAddAndFind;
    procedure TestAddAndFindManyEntries;
    procedure TestAddAndIterateManyEntries;
    procedure TestAddDuplicateAndFind;
    procedure TestAddDuplicatesFailure;
    procedure TestAddAndFindHash16;
    procedure TestAddAndFindHash64;
    {$IFDEF HasGenerics}
    procedure TestAddAndFindManyEntriesUsingTDictionary;
    {$ENDIF}
    procedure TestRemove;
    procedure TestIterator;
    procedure TestIteratorDuplicateString;
    procedure TestAutoFreeValue;
    procedure TestAddTwoValuesAndIterate;
  end;

implementation

uses
  Hash_Trie, Trie {$IFDEF HasGenerics}, Generics.Collections {$ENDIF};

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

procedure TStringHashTrieTest.TestAddAndIterateManyEntries;
const
  Count = 1024 * 256;
var
  i, Cnt : integer;
  AIterator : THashTrieIterator;
  AKey : AnsiString;
  AValue : Pointer;
begin
  for i := 0 to Count - 1 do
    FStrHashTrie.Add(AnsiString(IntToStr(i)) + 'hello', Self);
  FStrHashTrie.InitIterator(AIterator);
  Cnt := 0;
  while FStrHashTrie.Next(AIterator, AKey, AValue) do
    inc(Cnt);
  CheckEquals(Count, Cnt, 'Count of iterated values doesn''t match');
end;

procedure TStringHashTrieTest.TestAddDuplicateAndFind;
var
  Value : Pointer;
begin
  FStrHashTrie.Add('Hello World', Self);
  FStrHashTrie.Add('Hello World', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(FStrHashTrie.Remove('Hello World'), 'Remove should return True');
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(FStrHashTrie.Remove('Hello World'), 'Remove should return True');
  Check(not FStrHashTrie.Find('Hello World', Value), 'Item found');
  Check( not FStrHashTrie.Remove('Hello World'), 'Remove should return False');
end;

procedure TStringHashTrieTest.TestAddDuplicatesFailure;
begin
  FStrHashTrie.AllowDuplicates := False;
  FStrHashTrie.Add('Hello World', Self);
  try
    FStrHashTrie.Add('Hello World', Self);
    Fail('Should fail when adding duplicate');
  except
    on E : ETrieDuplicate do {};
  end;
end;

procedure TStringHashTrieTest.TestAddAndFindHash16;
var
  Value : Pointer;
begin
  FStrHashTrie.Free;
  FStrHashTrie := TStringHashTrie.Create(hs16);
  FStrHashTrie.Add('Hello World', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
end;

procedure TStringHashTrieTest.TestAddAndFindHash64;
var
  Value : Pointer;
begin
  FStrHashTrie.Free;
  FStrHashTrie := TStringHashTrie.Create(hs64);
  FStrHashTrie.Add('Hello World', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
end;

procedure TStringHashTrieTest.TestRemove;
var
  Value : Pointer;
begin
  FStrHashTrie.Add('Hello World', Self);
  Check(FStrHashTrie.Find('Hello World', Value), 'Item not found');
  FStrHashTrie.Remove('Hello World');
  Check(not FStrHashTrie.Find('Hello World', Value), 'Item found');
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

procedure TStringHashTrieTest.TestIteratorDuplicateString;
var
  AIterator : THashTrieIterator;
  AKey : AnsiString;
  AValue : Pointer;
begin
  FStrHashTrie.Add('Hello World', Self);
  FStrHashTrie.Add('Hello World', Self);
  FStrHashTrie.InitIterator(AIterator);
  Check(FStrHashTrie.Next(AIterator, AKey, AValue), 'Value of FStrHashTrie.Next doesn''t match');
  CheckEquals('Hello World', AKey, 'AKey doesn''t match');
  Check(FStrHashTrie.Next(AIterator, AKey, AValue), 'Value of FStrHashTrie.Next doesn''t match');
  CheckEquals('Hello World', AKey, 'AKey doesn''t match');
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
  FStrHashTrie.Free;
end;

{$IFDEF HasGenerics}
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
{$ENDIF}

initialization
  {$IFDEF FPC}
  RegisterTest(TStringHashTrieTest);
  {$ELSE}
  RegisterTest(TStringHashTrieTest.Suite);
  {$ENDIF}
end.

