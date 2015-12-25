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
  end;

implementation

{ TPointerTrie }

function TPointerTrie.GetItem(Index: Integer): Pointer;
begin
  Result := PPointer(inherited Items[Index])^;
end;

constructor TPointerTrie.Create;
begin
  inherited Create(sizeof(Pointer) * BitsPerByte div BitsForChildIndexPerBucket);
end;

procedure TPointerTrie.Add(p: Pointer);
begin
  inherited Add(p);
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
  Result := inherited Next(AIterator);
  if Result <> nil then
    Result := PPointer(Result)^;
end;

end.

