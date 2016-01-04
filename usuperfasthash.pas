unit uSuperFastHash;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

function SuperFastHash(data: PAnsiChar; Len: Cardinal): Cardinal;

implementation

function SuperFastHash(data: PAnsiChar; Len: Cardinal): Cardinal;
var
  tmp : Cardinal;
  rem : integer;
  i : integer;
  CurCardinal : Cardinal;
begin
  Result := len;
  if (len <= 0) or (data = nil)
    then
    begin
      Result := 0;
      exit;
    end;
  rem := len and 3;
  len := len shr 2;
  { Main loop }
  for i := len downto 1 do
    begin
      CurCardinal := PCardinal (data)^;
      inc (Result, PWord (@CurCardinal)^);
      tmp  := (PWord (@PAnsiChar(@CurCardinal) [2])^ shl 11) xor Result;
      Result := (Result shl 16) xor tmp;
      inc (Data, sizeof (Cardinal));
      inc (Result, Result shr 11);
    end;
  { Handle end cases }
  case rem of
    3 :
      begin
        CurCardinal := PWord (data)^ shl 8 + byte (data [sizeof (Word)]);
        inc (Result, PWord (@CurCardinal)^);
        Result := Result xor (Result shl 16);
        Result := Result xor (byte (PAnsiChar (@CurCardinal) [sizeof (Word)]) shl 18);
        inc (Result, Result shr 11);
      end;
    2 :
      begin
        CurCardinal := PWord (data)^;
        inc (Result, PWord (@CurCardinal)^);
        Result := Result xor (Result shl 11);
        inc (Result, Result shr 17);
      end;
    1 :
      begin
        inc (Result, byte (data^));
        Result := Result xor (Result shl 10);
        inc (Result, Result shr 1);
      end;
  end;

  { Force "avalanching" of final 127 bits }
  Result := Result xor (Result shl 3);
  inc (Result, Result shr 5);
  Result := Result xor (Result shl 4);
  inc (Result, Result shr 17);
  Result := Result xor (Result shl 25);
  inc (Result, Result shr 6);
end;

{ Original C code for SuperFastHash by Paul Hsie}

end.

