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
  published
    procedure TestAddFindAndRemove32;
    procedure TestAddFindAndRemove16;
    procedure TestAddFindAndRemove64;
    procedure TestAddSomeElements;
    procedure TestAddZeroKey;
    procedure TestCreateIntegerHashTrie;
    procedure TestIterate32;
    procedure TestIterate16;
    procedure TestIterate64;
  end;

implementation

uses
  Hash_Trie;

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

procedure TIntegerHashTrieTest.TestAddFindAndRemove32;
var
  Key : Cardinal;
  Value : Pointer;
begin
  FIntHashTrie := TIntegerHashTrie.Create(hs32);
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
  FIntHashTrie := TIntegerHashTrie.Create(hs16);
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
  FIntHashTrie := TIntegerHashTrie.Create(hs64);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  Check(FIntHashTrie.Find(Key, Value), 'Find should return True');
  Check(Value = Pointer(Self), 'Value should be equals to Self');
  Check(FIntHashTrie.Remove(Key), 'Key was not found?');
  Check(not FIntHashTrie.Find(Key, Value), 'Find should return False');
end;

procedure TIntegerHashTrieTest.TestAddSomeElements;
var
  i : Cardinal;
  Value : Pointer;
begin
  FIntHashTrie := TIntegerHashTrie.Create(hs32);
  for i := 1 to 1024 do
    FIntHashTrie.Add(i, {%H-}Pointer(i));
  for i := 1 to 1024 do
  begin
    Check(FIntHashTrie.Find(i, Value), 'Should find element');
    CheckEquals(i, {%H-}Cardinal(Value), 'Value should match');
  end;
end;

procedure TIntegerHashTrieTest.TestAddZeroKey;
begin
  FIntHashTrie := TIntegerHashTrie.Create(hs32);
  {$IFNDEF FPC}
  ExpectedException := EIntegerHashTrie;
  {$ELSE}
  try
  {$ENDIF}
    FIntHashTrie.Add(Cardinal(0), nil);
  {$IFDEF FPC}
    Fail('Expecting exception EIntegerHashTrie');
  except
    on E : EIntegerHashTrie do {};
  end;
  {$ENDIF}
end;

procedure TIntegerHashTrieTest.TestIterate32;
var
  Key : Cardinal;
  Key16 : Word;
  Value : pointer;
  It : THashTrieIterator;
begin
  FIntHashTrie := TIntegerHashTrie.Create(hs32);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  FIntHashTrie.InitIterator(It);
  Check(FIntHashTrie.Next(It, Key, Value), 'First call to Next should return True');
  CheckEquals(1, Key, 'Key returned from Next should be  = 1');
  Check(Value = Pointer(Self), 'Value returned from Next should be Self');
  Check(not FIntHashTrie.Next(It, Key, Value), 'Second call to Next should return False');
  FIntHashTrie.InitIterator(It);
  {$IFNDEF FPC}
  ExpectedException := EIntegerHashTrie;
  FIntHashTrie.Next(It, Key16, Value);
  {$ELSE}
  try
    FIntHashTrie.Next(It, Key16, Value);
    Fail('Expected exception');
  except
    on EIntegerHashTrie do {};
  end;
  {$ENDIF}
end;

procedure TIntegerHashTrieTest.TestIterate16;
var
  Key : Word;
  Key32 : Cardinal;
  Value : pointer;
  It : THashTrieIterator;
begin
  FIntHashTrie := TIntegerHashTrie.Create(hs16);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  FIntHashTrie.InitIterator(It);
  Check(FIntHashTrie.Next(It, Key, Value), 'First call to Next should return True');
  CheckEquals(1, Key, 'Key returned from Next should be  = 1');
  Check(Value = Pointer(Self), 'Value returned from Next should be Self');
  Check(not FIntHashTrie.Next(It, Key, Value), 'Second call to Next should return False');
  FIntHashTrie.InitIterator(It);
  {$IFNDEF FPC}
  ExpectedException := EIntegerHashTrie;
  FIntHashTrie.Next(It, Key32, Value);
  {$ELSE}
  try
    FIntHashTrie.Next(It, Key32, Value);
    Fail('Expected exception');
  except
    on EIntegerHashTrie do {};
  end;
  {$ENDIF}
end;

procedure TIntegerHashTrieTest.TestIterate64;
var
  Key : Int64;
  Key32 : Cardinal;
  Value : pointer;
  It : THashTrieIterator;
begin
  FIntHashTrie := TIntegerHashTrie.Create(hs64);
  Key := 1;
  FIntHashTrie.Add(Key, Self);
  FIntHashTrie.InitIterator(It);
  Check(FIntHashTrie.Next(It, Key, Value), 'First call to Next should return True');
  CheckEquals(1, Key, 'Key returned from Next should be  = 1');
  Check(Value = Pointer(Self), 'Value returned from Next should be Self');
  Check(not FIntHashTrie.Next(It, Key, Value), 'Second call to Next should return False');
  FIntHashTrie.InitIterator(It);
  {$IFNDEF FPC}
  ExpectedException := EIntegerHashTrie;
  FIntHashTrie.Next(It, Key32, Value);
  {$ELSE}
  try
    FIntHashTrie.Next(It, Key32, Value);
    Fail('Expected exception');
  except
    on EIntegerHashTrie do {};
  end;
  {$ENDIF}
end;

initialization
  {$IFDEF FPC}
  RegisterTest(TIntegerHashTrieTest);
  {$ELSE}
  RegisterTest(TIntegerHashTrieTest.Suite);
  {$ENDIF}
end.

