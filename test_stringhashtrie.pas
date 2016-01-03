unit Test_StringHashTrie;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, StringHashTrie;

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
    procedure TestAddDuplicateAndFind;
    procedure TestAddDuplicatesFailure;
    procedure TestAddAndFindHash16;
    procedure TestAddAndFindHash64;
    procedure TestRemove;
    procedure TestIterator;
    procedure TestIteratorDuplicateString;
    procedure TestAutoFreeValue;
    procedure TestAddTwoValuesAndIterate;
  end;

implementation

uses
  Hash_Trie, Trie;

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
  AKey : String;
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
  AKey : String;
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
  AKey : String;
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

initialization

  RegisterTest(TStringHashTrieTest);
end.

