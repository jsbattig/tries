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
    procedure TestCreateIntegerHashTrie;
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

initialization
  {$IFDEF FPC}
  RegisterTest(TIntegerHashTrieTest);
  {$ELSE}
  RegisterTest(TIntegerHashTrieTest.Suite);
  {$ENDIF}
end.

