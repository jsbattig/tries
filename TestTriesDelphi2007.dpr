program TestTriesDelphi2007;
{

  Delphi DUnit Test Project
  -------------------------
  This project contains the DUnit test framework and the GUI/Console test runners.
  Add "CONSOLE_TESTRUNNER" to the conditional defines entry in the project options 
  to use the console test runner.  Otherwise the GUI test runner will be used by 
  default.

}

{$IFDEF CONSOLE_TESTRUNNER}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  Forms,
  TestFramework,
  GUITestRunner,
  TextTestRunner,
  hash_trie in 'hash_trie.pas',
  integerhashtrie in 'integerhashtrie.pas',
  pointertrie in 'pointertrie.pas',
  stringhashtrie in 'stringhashtrie.pas',
  test_integerhashtrie in 'test_integerhashtrie.pas',
  test_stringhashtrie in 'test_stringhashtrie.pas',
  trie in 'trie.pas',
  test_pointertrie in 'test_pointertrie.pas',
  test_old_stringhashtrie in 'test_old_stringhashtrie.pas',
  uAllocators in 'uAllocators.pas',
  hashedcontainer in 'hashedcontainer.pas';

{$R *.RES}

begin
  Application.Initialize;
  if IsConsole then
    TextTestRunner.RunRegisteredTests
  else
    GUITestRunner.RunRegisteredTests;
end.

