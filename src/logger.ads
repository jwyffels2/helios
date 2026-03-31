package Logger is

   --  Global flag to enable/disable ANSI color output in logs
   Color_Enabled : Boolean := True;

   --  Enumeration of supported log levels
   type Log_Level is (ERROR, WARN, INFO, DEBUG, TRACE);

   --  Set the active logging level
   procedure Set_Level (Level : Log_Level);

   --  Get the active logging level
   function Get_Level return Log_Level;

   --  Procedures to print messages at each log level
   procedure Error (Message : String);
   procedure Warn (Message : String);
   procedure Info (Message : String);
   procedure Debug (Message : String);
   procedure Trace (Message : String);

private

   --  Current logging level state
   Current_Level : Log_Level := INFO;

   --  Core logging procedure that prints a formatted message
   procedure Log (Level : Log_Level; Message : String);

end Logger;
