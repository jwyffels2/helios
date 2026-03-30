package Logger is

   --  Global flag to enable/disable ANSI color output in logs
   Color_Enabled : Boolean := True;

   --  Enumeration of supported log levels
   type Log_Level is (Error, Warn, Trace, Debug, Info);

   --  Core logging procedure that prints a formatted message
   procedure Log (Level : Log_Level; Message : String);

   --  Convenience wrappers for each log level
   procedure Error (Message : String);
   procedure Warn (Message : String);
   procedure Trace (Message : String);
   procedure Debug (Message : String);
   procedure Info (Message : String);

   --  Enable ANSI color output
   procedure Enable_Color;

   --  Disable ANSI color output
   procedure Disable_Color;

end Logger;
