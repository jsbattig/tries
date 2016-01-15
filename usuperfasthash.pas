unit uSuperFastHash;

{ Original C code for SuperFastHash by Paul Hsie }

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

function SuperFastHash(data: PAnsiChar; Len: Cardinal; AUpper: Boolean):
    Cardinal;
function CalcStrCRC32(S: Pointer; ASize: Cardinal): Cardinal;
function CalcStrCRC32Upper(S: PAnsiChar): Cardinal;

implementation

uses
  SysUtils;

type
  PCardinal = ^Cardinal;

var
  UpperArray : array [AnsiChar] of AnsiChar;

function UpperCardinal (n : Cardinal) : Cardinal;
var
  tmp, tmp2 : Cardinal;
begin
  tmp := n or $80808080;
  tmp2 := tmp - $7B7B7B7B;
  tmp := tmp xor n;
  Result := ((((tmp2 or $80808080) - $66666666) and tmp) shr 2) xor n;
end;

function SuperFastHash(data: PAnsiChar; Len: Cardinal; AUpper: Boolean):
    Cardinal;
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
      if AUpper
        then CurCardinal := UpperCardinal (CurCardinal);
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
        if AUpper
          then CurCardinal := UpperCardinal (CurCardinal);
        inc (Result, PWord (@CurCardinal)^);
        Result := Result xor (Result shl 16);
        Result := Result xor (byte (PAnsiChar (@CurCardinal) [sizeof (Word)]) shl 18);
        inc (Result, Result shr 11);
      end;
    2 :
      begin
        CurCardinal := PWord (data)^;
        if AUpper
          then CurCardinal := UpperCardinal (CurCardinal);
        inc (Result, PWord (@CurCardinal)^);
        Result := Result xor (Result shl 11);
        inc (Result, Result shr 17);
      end;
    1 :
      begin
        if AUpper
          then inc (Result, byte (UpperArray [data^]))
          else inc (Result, byte (data^));
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

{ dynamic crc32 table }

const
  CRC32_POLYNOMIAL = $EDB88320;
var
  Ccitt32Table: array[0..255] of Cardinal;

function CalcStrCRC32Upper(S: PAnsiChar): Cardinal;
begin
  Result := $FFFFFFFF;
  while s^ <> #0 do
    begin
      Result := (((Result shr 8) and $00FFFFFF) xor (Ccitt32Table[(Result xor byte(UpperArray [S^])) and $FF]));
      inc (S);
    end;
end;

procedure BuildCRCTable;
var
  i, j: longint;
  value: Cardinal;
begin
  for i := 0 to 255 do
    begin
      value := i;
      for j := 8 downto 1 do
        if ((value and 1) <> 0) then
          value := (value shr 1) xor CRC32_POLYNOMIAL
        else
          value := value shr 1;
      Ccitt32Table[i] := value;
    end
end;

function CalcStrCRC32(S: Pointer; ASize: Cardinal): Cardinal;
var
  i : Cardinal;
begin
  Result := $FFFFFFFF;
  i := 0;
  while i < ASize do
    begin
      Result := (((Result shr 8) and $00FFFFFF) xor (Ccitt32Table[(Result xor byte(PAnsiChar(s)[i])) and $FF]));
      inc(i);
    end;
end;

var
  c : AnsiChar;

initialization
  for c := low (UpperArray) to high (UpperArray) do
    UpperArray [c] := UpCase(c);
  BuildCRCTable;
end.

