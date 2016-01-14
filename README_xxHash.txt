1.License
=========

 This is a README file for FreePascal port of xxHash

  Copyright (C) 2014 Vojtěch Čihák, Czech Republic

  http://sourceforge.net/projects/xxhashfpc/files/

  xxHash.pas library is free software. See the files
  COPYING.modifiedLGPL.txt and COPYING.LGPL.txt,
  included in this distribution,
  for details about the license.

2.Note
======

 Original verion of xxHash is written in C
  by Yann Collet and distributed under
  the BSD license.
  https://code.google.com/p/xxhash/

3.How to use unit xxHash
========================

For the fastest calculation call one of these functions:

function xxHash32Calc(ABuffer: Pointer; ALength: LongInt; ASeed: LongWord = 0): LongWord; overload;
function xxHash32Calc(const ABuffer: array of Byte; ASeed: LongWord = 0): LongWord; overload;
function xxHash32Calc(const AString: string; ASeed: LongWord = 0): LongWord; overload;

function xxHash64Calc(ABuffer: Pointer; ALength: LongInt; ASeed: QWord = 0): QWord; overload;
function xxHash64Calc(const ABuffer: array of Byte; ASeed: QWord = 0): QWord; overload;
function xxHash64Calc(const AString: string; ASeed: QWord = 0): QWord; overload;

In this case, all data are passed at once and return values of the functions is the hash.
Limit is 2.1 GB for both 32 and 64 bits verions.

If you cannot/don't want pass all data at once or you want to hash more data streams simultaneously,
you can create as many instances of classes TxxHash32 and TxxHash64 as you need and pass the data
as needed. Limit is 2.1 GB for TxxHash32 and 4.2 GB for TxxHash64 in one Update. Total limit is
2^64-1 bytes of data for both classes.

Lifetime of objects is:
Create -> Update -> ... -> Update -> Digest -> Free
for one calculation, or
Create -> Update -> ... -> Update -> Digest -> Reset -> Update -> ... -> Update -> Digest -> Free
for more calculations with the same object.
Eventually, you can change property Seed before or after Reset but not during Updating and not before
Digest!

Here are code snippets, 8 examples how to get hash:

Strings:
--------
var aHash32: LongWord;
    aHash64: QWord;
...
aHash32:=xxHash32Calc('String to hash');  //Returns 32-bit hash of the string
aHash64:=xxHash64Calc('String to hash');  //Returns 64-bit hash of the string

Arrays:
-------
var aBytes: array of Byte;
    i: Integer;
    aHash32: LongWord;
    aHash64: QWord;
...
SetLength(aBytes, 50);
for i:=0 to 49 do
  aBytes[i]:=i;
aHash32:=xxHash32Calc(aBytes);  //Returns 32-bit hash of the aBytes array
aHash64:=xxHash64Calc(aBytes);  //Returns 64-bit hash of the aBytes array

Piece of memory:
----------------
var p: Pointer;
    i: Integer;
    aHash32: LongWord;
    aHash64: QWord;
...
GetMem(p, 50);
for i:=0 to 49 do
  PByte(p+i)^:=i;
aHash32:=xxHash32Calc(p);  //Returns 32-bit hash of the allocated memory
aHash64:=xxHash64Calc(p);  //Returns 64-bit hash of the allocated memory
FreeMem(p, 50);

Files* (at once):
----------------
a) old procedural approach:

var aBuffer: Pointer;
    aFile: file;
    aLength: LongInt;
    aHash32: LongWord;
    aHash64: QWord;
...
AssignFile(aFile, '/path/to/file');
Reset(aFile, 1);
aLength:=FileSize(aFile));
aBuffer:=GetMem(aLength);
BlockRead(aFile, aBuffer^, aLength);
CloseFile(aFile);
aHash32:=xxHash32Calc(aBuffer, aLength, 0);  //Returns 32-bit hash of the file
aHash64:=xxHash64Calc(aBuffer, aLength, 0);  //Returns 64-bit hash of the file
FreeMem(aBuffer, aLength);

b) using TMemoryStream:

var aStream: TMemoryStream;
    aLength: LongInt;
    aHash32: LongWord;
    aHash64: QWord;
    aPath: string;
...
aPath:='/path/to/file';
aLength:=FileSize(aPath));
aStream:=TMemoryStream.Create;
aStream.Size:=aLength;
aStream.LoadFromFile(aPath);
aHash32:=xxHash32Calc(aStream.Memory, aStream.Size{or aLength}, 0);  //Returns 32-bit hash of the file
aHash64:=xxHash64Calc(aStream.Memory, aStream.Size{or aLength}, 0);  //Returns 64-bit hash of the file
aStream.Free;

c) using TFileStream:

var aBuffer: Pointer;
    aStream: TFileStream;
    aHash32: LongWord;
    aHash64: QWord;
    aPath: string;
...
aPath:='/path/to/file';
aStream:=TFileStream.Create(FPath, fmOpenRead);
aBuffer:=GetMem(aStream.Size);
aStream.ReadBuffer(aBuffer^, aStream.Size);
aHash32:=xxHash32Calc(aStream.Memory, aStream.Size, 0);  //Returns 32-bit hash of the file
aHash64:=xxHash64Calc(aStream.Memory, aStream.Size, 0);  //Returns 64-bit hash of the file
FreeMem(aBuffer, aStream.Size);
aStream.Free;

Files (by blocks, using class TxxHash32 or TxxHash64):
------------------------------------------------------
a) old procedural approach (32-bit only):

const cBlockSize = 4096;
var aBuffer: Pointer;
    aFile: file;
    aHash32: LongWord;
    aHasher: TxxHash32;
    aRemain: LongInt;
...
AssignFile(aFile, /path/to/file);
Reset(aFile, 1);
aBuffer:=GetMem(cBlockSize);
aHasher:=TxxHash32.Create(0);
aRemain:=FileSize(aFile));
repeat
  BlockRead(aFile, aBuffer^, cBlockSize);
  aHasher.Update(aBuffer, cBlockSize);
  dec(aRemain, cBlockSize);
until (aRemain<cBlockSize);
if aRemain>0 then
  begin
    BlockRead(aFile, aBuffer^, aRemain);
    aHasher.Update(aBuffer, aRemain);
  end;
CloseFile(aFile);
aHash32:=aHasher.Digest;  //Returns 32-bit hash of the file
FreeMem(aBuffer, cBlockSize);
aHasher.Free;

b) using TFileStream  (64-bit only):

const cBlockSize = 8192;
var aBuffer: Pointer;
    aHash64: QWord;
    aHasher: TxxHash64;
    aPath: string;
    aRemain: LongInt;
    aStream: TFileStream;
...
aPath:='/path/to/file';
aStream:=TFileStream.Create(aPath, fmOpenRead);
aBuffer:=GetMem(cBlockSize);
aHasher:=TxxHash64.Create(0);
aRemain:=aStream.Size;
repeat
  aStream.ReadBuffer(aBuffer^, cBlockSize);
  aHasher.Update(aBuffer, cBlockSize);
  dec(aRemain, cBlockSize);
until (aRemain<cBlockSize);
if aRemain>0 then
  begin
    aStream.ReadBuffer(aBuffer^, aRemain);
    aHasher.Update(aBuffer, aRemain);
  end;
aHash64:=aHasher.Digest;  //Returns 64-bit hash of the file
aHasher.Free;
FreeMem(aBuffer, cBlockSize);
aStream.Free;

*) note I omitted try..finally constructions because of simplicity




