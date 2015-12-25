program Test_PointerContainer;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, GuiTestRunner, PointerContainer_Test, PointerTrie,
  PointerContainer, PointerTrie_Test, Trie;

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TGuiTestRunner, TestRunner);
  Application.Run;
end.

