pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__tests.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__tests.adb");
pragma Suppress (Overflow_Check);

package body ada_main is

   E04 : Short_Integer; pragma Import (Ada, E04, "gnat_exit_E");


   procedure adainit is
   begin
      null;

      E04 := E04 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_tests");

   procedure main is
      Ensure_Reference : aliased System.Address := Ada_Main_Program_Name'Address;
      pragma Volatile (Ensure_Reference);

   begin
      adainit;
      Ada_Main_Program;
   end;

--  BEGIN Object file/option list
   --   /workspace/tests/obj/development/gnat_exit.o
   --   /workspace/tests/obj/development/tests.o
   --   -L/workspace/tests/obj/development/
   --   -L/workspace/tests/obj/development/
   --   -L/workspace/third_party/helios-neorv32-setups/neorv32-hal/lib/
   --   -L/root/.local/share/alire/builds/bare_runtime_14.0.0_095db6f0/282b01b920f0d5bb2bac604ac6d9e811f26d175144bc99af963e0381e797ee94/adalib/
   --   -static
   --   -lgnat
--  END Object file/option list   

end ada_main;
