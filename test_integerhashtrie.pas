unit Test_IntegerHashTrie;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TIntegerHashTrieTest= class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHookUp;
  end;

implementation

procedure TIntegerHashTrieTest.TestHookUp;
begin
  Fail('Write your own test');
end;

procedure TIntegerHashTrieTest.SetUp;
begin

end;

procedure TIntegerHashTrieTest.TearDown;
begin

end;

initialization

  RegisterTest(TIntegerHashTrieTest);
end.

