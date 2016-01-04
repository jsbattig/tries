unit Test_IntegerHashTrie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  Classes,
  {$IFDEF FPC}
  fpcunit, testregistry,
  {$ELSE}
  TestFramework,
  {$ENDIF} SysUtils;

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
  {$IFDEF FPC}
  RegisterTest(TIntegerHashTrieTest);
  {$ELSE}
  RegisterTest(TIntegerHashTrieTest.Suite);
  {$ENDIF}
end.

