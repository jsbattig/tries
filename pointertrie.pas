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


  
  TPointerTrie

 Example representation of trie with two
 16 bit values: $348C and $45B5

 Notice that our PointerTrie depth is 4 levels because the Pointer size is 16 bits.
 We can store up to 4 bits per level with our structure.

 The top path stores value $348C and the bottom path $45B5

                               +---------------------+
                               |                     |
+----------------+             | +----------------+  |            +----------------+            +----------------+
|ChildrenCount| 2|             |0|ChildrenCount| 1|  |            |ChildrenCount| 1|            |ChildrenCount| 0|
+----------------+             | +----------------+  |            +----------------+            +----------------+
|Busy         | D|             | |Busy         | 8|  |            |Busy         | 4|            |Busy         | 3|
+----------------+             | +-------------+--+  |            +-------------+--+            +-------------+--+
|ChildIndex      |             | |ChildIndex      |  |            |ChildIndex      |
|  +  +  +  +    |             | |  +  +  +  +    |  |            |  +  +  +  +    |               ^
|  | 1|  |  |    |             | |  |  |  |  |    |  |            | 0|  |  |  |    |               |
|  |  |  |  |    |             | | 0|  |  |  |    |  |            |  |  |  |  |    |               |
| 0|  |  |  |    |             | |  |  |  |  |    |  |            |  |  |  |  |    |               |
+-----+--+--+----+             | +--+--+--+--+----+  |            +--+--+--+--+----+               |
|Children      |-------------> | |Children      |---------------> |Children      |-----------------+
+----------------+             | +----------------+  |            +----------------+
                               |1|ChildrenCount| 1|  |
                               | +----------------+  |
                               | |Busy         | B|  |            +----------------+            +----------------+
                               | +----------------+  |            |ChildrenCount| 1|            |ChildrenCount| 0|
                               | |ChildIndex      |  |            +----------------+            +----------------+
                               | |  +  +  +  +    |  |            |Busy         | 5|            |Busy         | 4|
                               | |  |  |  |  |    |  |            +-------------+--+            +-------------+--+
                               | |  |  |  | 0|    |  |            |ChildIndex      |
                               | |  |  |  |  |    |  |            |  +  +  +  +    |                ^
                               | +--+--+--+--+----+  |            | 0|  |  |  |    |                |
                               | |Children      |---------------> |  |  |  |  |    |                |
                               | +----------------+  |            |  |  |  |  |    |                |
                               |                     |            +--+--+--+--+----+                |
                               +---------------------+            |Children      |------------------+
                                                                  +----------------+

*)

unit PointerTrie;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  Trie;

type
  { TPointerTrie }

  TPointerTrie = class(TTrie)
  private
    function GetItem(Index: Integer): Pointer;
  public
    constructor Create;
    procedure Add(p : Pointer); reintroduce;
    function Find(p : Pointer) : Boolean; reintroduce;
    procedure Remove(p : Pointer); reintroduce;
    function Next(var AIterator : TTrieIterator) : Pointer; reintroduce;
    property Items[Index: Integer]: Pointer read GetItem; default;
    property RandomAccessMode;
  end;

implementation

uses
  hashedcontainer;

{ TPointerTrie }

function TPointerTrie.GetItem(Index: Integer): Pointer;
begin
  Result := PPointer(inherited Items[Index])^;
end;

constructor TPointerTrie.Create;
begin
  inherited Create(TrieDepthPointerSize);
end;

procedure TPointerTrie.Add(p: Pointer);
var
  Dummy : PTrieLeafNode;
  DummyWasBusy : Boolean;
begin
  inherited Add(p, Dummy, DummyWasBusy);
end;

function TPointerTrie.Find(p: Pointer): Boolean;
begin
  Result := inherited _Find(p);
end;

procedure TPointerTrie.Remove(p: Pointer);
begin
  inherited Remove(p);
end;

function TPointerTrie.Next(var AIterator: TTrieIterator): Pointer;
begin
  if inherited Next(AIterator) then
    Result := AIterator.Base.LastResultPtr
  else Result := nil;
end;

end.

