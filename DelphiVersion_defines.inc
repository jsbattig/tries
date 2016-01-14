{ Delphi version defines.
  The define DELPHI3 denotes Delphi 3.0 or higher, DELPHIXE4 is Delphi XE4 or higher, etc, not only the particular version as the name implies 
}

{$IFDEF VER100}
  {$DEFINE DELPHI3} { Delphi 3.0 or higher }
{$ENDIF}

{$IFDEF VER110} { Borland C++Builder 3.0 }
  {$DEFINE DELPHI3}
  {$DEFINE CBUILDER3}
  {$ObjExportAll On}
{$ENDIF}

{$IFDEF VER120} { Delphi 4.0 }
  {$DEFINE DELPHI3}
  {$DEFINE DELPHI4}
{$ENDIF}

{$IFDEF VER125} { Borland C++Builder 4.0 }
  {$DEFINE DELPHI3}
  {$DEFINE DELPHI4}
  {$DEFINE CBUILDER3}
  {$DEFINE CBUILDER4}
  {$ObjExportAll On}
{$ENDIF}

{$IFDEF VER130} { Delphi 5.0 }
  {$DEFINE DELPHI3}
  {$DEFINE DELPHI4}
  {$DEFINE DELPHI5}
  {$IFDEF BCB} { Borland C++Builder 5.0 }
    {$DEFINE CBUILDER3}
    {$DEFINE CBUILDER4}
    {$DEFINE CBUILDER5}
    {$ObjExportAll On}
  {$ENDIF}
{$ENDIF}

{$IFDEF ConditionalExpressions}
  { Delphi 5 and previous that didn't support conditional IF defines }  
  {$DEFINE KYLIX1}
  {$DEFINE KYLIX2}
  {$DEFINE DELPHI3}
  {$DEFINE DELPHI4}
  {$DEFINE DELPHI5}

  {$IF CompilerVersion >= 14.0} { Delphi 6.0 }
    {$DEFINE DELPHI6}
  {$IFEND}

  {$IF CompilerVersion >= 15.0} { Delphi 7.0 }
    {$DEFINE DELPHI7}
  {$IFEND}

  {$IF CompilerVersion >= 16.0} { Delphi 8.0 }
    {$DEFINE DELPHI8}
  {$IFEND}

  {$IF CompilerVersion >= 17.0} { Delphi 2005 }
    {$DEFINE DELPHI2005}
  {$IFEND}

  {$IF CompilerVersion >= 18.0} { Delphi 2006 }
    {$DEFINE DELPHI2006}
  {$IFEND}

  {$IF CompilerVersion >= 18.5} { Delphi 2007 }
    {$DEFINE DELPHI2007}
  {$IFEND}

  {$IF CompilerVersion >= 20.0} { Delphi 2009 }
    {$DEFINE DELPHI2009}
  {$IFEND}

  {$IF CompilerVersion >= 21.0} { Delphi 2010 }
    {$DEFINE DELPHI2010}
  {$IFEND}

  {$IF CompilerVersion >= 22.0} { Delphi XE }
    {$DEFINE DELPHIXE}
  {$IFEND}

  {$IF CompilerVersion >= 23.0} { Delphi XE2 }
    {$DEFINE DELPHIXE2}
  {$IFEND}

  {$IF CompilerVersion >= 24.0} { Delphi XE3 }
    {$DEFINE DELPHIXE3}
  {$IFEND}
  
  {$IF CompilerVersion >= 25.0} { Delphi XE4 }
    {$DEFINE DELPHIXE4}
  {$IFEND}

  {$IF CompilerVersion >= 26.0} { Delphi XE5 }
    {$DEFINE DELPHIXE5}
  {$IFEND}

  {$IF CompilerVersion >= 27.0} { Delphi XE6 }
    {$DEFINE DELPHIXE6}
  {$IFEND}

  {$IF CompilerVersion >= 28.0} { Delphi XE7 }
    {$DEFINE DELPHIXE7}
  {$IFEND}

  {$IF CompilerVersion >= 29.0} { Delphi XE8 }
    {$DEFINE DELPHIXE8}
  {$IFEND}
  
  {$IF CompilerVersion >= 30.0} { Delphi 10 Seattle }
    {$DEFINE DELPHI10}
  {$IFEND}

{$IFDEF DELPHIXE}
  {$DEFINE HAS_GENERICS}
{$ENDIF}

{$ENDIF !ConditionalExpressions}