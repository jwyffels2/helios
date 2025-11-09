with Interfaces.C;

procedure Gnat_Exit (Code : Interfaces.C.int);
pragma Export (C, Gnat_Exit, "__gnat_exit");
pragma No_Return (Gnat_Exit);
