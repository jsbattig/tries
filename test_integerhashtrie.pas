unit Test_IntegerHashTrie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  Classes,
  IntegerHashTrie,
  {$IFDEF FPC}
  fpcunit, testregistry,
  {$ELSE}
  TestFramework,
  {$ENDIF} SysUtils;

type
  TIntegerHashTrieTest= class(TTestCase)
  private
    FIntHashTrie : TIntegerHashTrie;
  protected
    procedure TearDown; override;
    procedure TraverseMeth({%H-}UserData: Pointer; Value: integer; Data: TObject; var
        {%H-}Done: Boolean);
  published
    procedure TestAddAndTraverse32;
    procedure TestAddFindAndRemove32;
    procedure TestAddFindAndRemove16;
    procedure TestAddFindAndRemove64;
    procedure TestAddReplaceAndFind;
    procedure TestAddSomeElements;
    procedure TestAddZeroKey;
    procedure TestCreateIntegerHashTrie;
    procedure TestIterate32;
    procedure TestIterate16;
    procedure TestIterate64;
    procedure TestIntegerHashTrieCodePaths;
  end;

implementation

uses
  hashedcontainer, Hash_Trie;

type
  TIntegerHashTrie_FunctionalTest = class(TIntegerHashTrie)
  protected
    procedure CalcHash(out Hash: THashRecord; key: Pointer; KeySize: Cardinal; ASeed: _Int64; AHashSize: Byte); override;
  end;

procedure TIntegerHashTrieTest.TestCreateIntegerHashTrie;
begin
  FIntHashTrie := TIntegerHashTrie.Create;
  Check(FIntHashTrie <> nil, 'FIntHashTrie should be <> nil');
end;

procedure TIntegerHashTrieTest.TearDown;
begin
  if FIntHashTrie <> nil then
    FIntHashTrie.Free;
end;

procedure TIntegerHashTrieTest.TestAddAndTraverse32;
var
  Key : Cardinal;
begin
  FIntHashTrie := TIntegerHashTrie.Create(32);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  FIntHashTrie.Traverse(nil, {$IFDEF FPC}@{$ENDIF}TraverseMeth);
end;

procedure TIntegerHashTrieTest.TestAddFindAndRemove32;
var
  Key : Cardinal;
  Value : Pointer;
begin
  FIntHashTrie := TIntegerHashTrie.Create(32);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  Check(FIntHashTrie.Find(Key, Value), 'Find should return True');
  Check(Value = Pointer(Self), 'Value should be equals to Self');
  Check(FIntHashTrie.Remove(Key), 'Key was not found?');
  Check(not FIntHashTrie.Find(Key, Value), 'Find should return False');
end;

procedure TIntegerHashTrieTest.TestAddFindAndRemove16;
var
  Key : word;
  Value : Pointer;
begin
  FIntHashTrie := TIntegerHashTrie.Create(16);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  Check(FIntHashTrie.Find(Key, Value), 'Find should return True');
  Check(Value = Pointer(Self), 'Value should be equals to Self');
  Check(FIntHashTrie.Remove(Key), 'Key was not found?');
  Check(not FIntHashTrie.Find(Key, Value), 'Find should return False');
end;

procedure TIntegerHashTrieTest.TestAddFindAndRemove64;
var
  Key : Int64;
  Value : Pointer;
begin
  FIntHashTrie := TIntegerHashTrie.Create(64);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  Check(FIntHashTrie.Find(Key, Value), 'Find should return True');
  Check(Value = Pointer(Self), 'Value should be equals to Self');
  Check(FIntHashTrie.Remove(Key), 'Key was not found?');
  Check(not FIntHashTrie.Find(Key, Value), 'Find should return False');
end;

procedure TIntegerHashTrieTest.TestAddReplaceAndFind;
var
  Value : Pointer;
begin
  FIntHashTrie := TIntegerHashTrie.Create(32);
  FIntHashTrie.Add(Cardinal(1), Self);
  Check(FIntHashTrie.Find(Cardinal(1), Value), 'Item not found');
  Check(Value = Pointer(Self), 'Item found doesn''t match expected value');
  FIntHashTrie.Add(Cardinal(1), FIntHashTrie);
  Check(FIntHashTrie.Find(Cardinal(1), Value), 'Item not found');
  Check(Value = Pointer(FIntHashTrie), 'Item found doesn''t match expected value');
  CheckEquals(1, FIntHashTrie.Count, 'There should be only one item in the hashtrie');
  Check(FIntHashTrie.Remove(Cardinal(1)), 'Remove should return true');
  Check(not FIntHashTrie.Find(Cardinal(1), Value), 'Item found');
end;

procedure TIntegerHashTrieTest.TestAddSomeElements;
var
  i : Cardinal;
  Value : Pointer;
begin
  FIntHashTrie := TIntegerHashTrie.Create(32);
  for i := 1 to 1024 do
    FIntHashTrie.Add(i, {%H-}Pointer(i));
  for i := 1 to 1024 do
  begin
    Check(FIntHashTrie.Find(i, Value), 'Should find element');
    CheckEquals(i, {%H-}Cardinal(Value), 'Value should match');
  end;
end;

procedure TIntegerHashTrieTest.TestAddZeroKey;
var
  Value : Pointer;
begin
  FIntHashTrie := TIntegerHashTrie.Create(32);
  FIntHashTrie.Add(Cardinal(0), nil);
  Check(FIntHashTrie.Find(Cardinal(0), Value), 'Zero should be allowed');
end;

procedure TIntegerHashTrieTest.TestIntegerHashTrieCodePaths;
var
  h : TIntegerHashTrie_FunctionalTest;
  i, j : Cardinal;
  Iter : THashTrieIterator;
  k : Cardinal;
  v : Pointer;
begin
  h := TIntegerHashTrie_FunctionalTest.Create(32);
  try
    for i := 1000 to 20000 do
      h.Add(i);
    for j := 0 to 10 do
      for i := 105 to 200 do
      begin
        h.Remove(i * j * 10 + i - 100);
        h.Pack;
        h.InitIterator(Iter);
        while h.Next(Iter, k, v) do;
      end;
  finally
    h.Free;
  end;
end;

procedure TIntegerHashTrieTest.TestIterate32;
var
  Key : Cardinal;
  Value : pointer;
  It : THashTrieIterator;
begin
  FIntHashTrie := TIntegerHashTrie.Create(32);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  FIntHashTrie.InitIterator(It);
  Check(FIntHashTrie.Next(It, Key, Value), 'First call to Next should return True');
  CheckEquals(1, Key, 'Key returned from Next should be  = 1');
  Check(Value = Pointer(Self), 'Value returned from Next should be Self');
  Check(not FIntHashTrie.Next(It, Key, Value), 'Second call to Next should return False');
 end;

procedure TIntegerHashTrieTest.TestIterate16;
var
  Key : Word;
  Value : pointer;
  It : THashTrieIterator;
begin
  FIntHashTrie := TIntegerHashTrie.Create(16);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  FIntHashTrie.InitIterator(It);
  Check(FIntHashTrie.Next(It, Key, Value), 'First call to Next should return True');
  CheckEquals(1, Key, 'Key returned from Next should be  = 1');
  Check(Value = Pointer(Self), 'Value returned from Next should be Self');
  Check(not FIntHashTrie.Next(It, Key, Value), 'Second call to Next should return False');
end;

procedure TIntegerHashTrieTest.TestIterate64;
var
  Key : Int64;
  Value : pointer;
  It : THashTrieIterator;
begin
  FIntHashTrie := TIntegerHashTrie.Create(64);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  FIntHashTrie.InitIterator(It);
  Check(FIntHashTrie.Next(It, Key, Value), 'First call to Next should return True');
  CheckEquals(1, Key, 'Key returned from Next should be  = 1');
  Check(Value = Pointer(Self), 'Value returned from Next should be Self');
  Check(not FIntHashTrie.Next(It, Key, Value), 'Second call to Next should return False');
end;

procedure TIntegerHashTrieTest.TraverseMeth(UserData: Pointer; Value: integer;
    Data: TObject; var Done: Boolean);
begin
  CheckEquals(1, Value, 'Key should be equals to 1');
  Check(Data = TObject(Self), 'Value should be equals to Self');
end;

procedure TIntegerHashTrie_FunctionalTest.CalcHash(out Hash: THashRecord; key: Pointer; KeySize: Cardinal; ASeed: _Int64; AHashSize: Byte);
var
  minus : Integer;
begin
  if (Integer(Key) mod 7 = 0) or (Integer(Key) mod 9 = 0) then
    minus := 1
  else minus := 0;
  Hash.Hash64 := Integer(key) div 10;
  Hash.Hash16_3 := Integer(key) div 2 - minus;
end;

initialization
  {$IFDEF FPC}
  RegisterTest(TIntegerHashTrieTest);
  {$ELSE}
  RegisterTest(TIntegerHashTrieTest.Suite);
  {$ENDIF}
end.


