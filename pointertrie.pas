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
*)

unit PointerTrie;

{$mode objfpc}{$H+}

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
    procedure Add(p : Pointer);
    function Find(p : Pointer) : Boolean;
    procedure Remove(p : Pointer);
    function Next(var AIterator : TTrieIterator) : Pointer;
    property Items[Index: Integer]: Pointer read GetItem; default;
    property AllowDuplicates;
    property RandomAccessMode;
  end;

implementation

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
begin
  inherited Add(p, Dummy);
end;

function TPointerTrie.Find(p: Pointer): Boolean;
begin
  Result := inherited Find(p);
end;

procedure TPointerTrie.Remove(p: Pointer);
begin
  inherited Remove(p);
end;

function TPointerTrie.Next(var AIterator: TTrieIterator): Pointer;
begin
  if inherited Next(AIterator) then
    Result := AIterator.LastResultPtr
  else Result := nil;
end;

end.

