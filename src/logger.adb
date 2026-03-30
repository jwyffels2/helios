with Uart0;
with Ada.Text_IO; use Ada.Text_IO;

package body Logger is

   --  ANSI escape sequence to reset terminal formatting
   Reset : constant String := ASCII.ESC & "[0m";

   ----------------------------------------------------------------------------
   --  Helper function declarations
   ----------------------------------------------------------------------------

   --  Builds the final formatted log message including:
   --    - Optional color prefix
   --    - [LEVEL] tag
   --    - Message text
   --    - Optional reset sequence
   function Format_Message (Level : Log_Level; Message : String) return String;

   --  Returns the ANSI color escape sequence corresponding to a log level
   --  If color is disabled, returns an empty string
   function Level_Color (Level : Log_Level) return String;

   ----------------------------------------------------------------------------
   --  Public API implementation
   ----------------------------------------------------------------------------

   procedure Set_Level (Level : Log_Level)
   is
   begin
      Current_Level := Level;
   end Set_Level;

   function Get_Level return Log_Level
   is
   begin
      return Current_Level;
   end Get_Level;

   procedure Error (Message : String)
   is
   begin
      Log (ERROR, Message);
   end Error;

   procedure Warn (Message : String)
   is
   begin
      Log (WARN, Message);
   end Warn;

   procedure Info (Message : String)
   is
   begin
      Log (INFO, Message);
   end Info;

   procedure Debug (Message : String)
   is
   begin
      Log (DEBUG, Message);
   end Debug;

   procedure Trace (Message : String)
   is
   begin
      Log (TRACE, Message);
   end Trace;

   ----------------------------------------------------------------------------
   --  Private API implementation
   ----------------------------------------------------------------------------

   procedure Log (Level : Log_Level; Message : String)
   is
   begin
      if Level <= Current_Level then
         Put_Line (Format_Message (Level, Message));
      end if;
   end Log;

   ----------------------------------------------------------------------------
   --  Helper function implementations
   ----------------------------------------------------------------------------

   function Level_Color (Level : Log_Level) return String
   is
   begin
      if not Color_Enabled then
         return "";
      end if;

      case Level is
         when ERROR => return ASCII.ESC & "[38;2;255;48;64m";
         when WARN  => return ASCII.ESC & "[38;2;255;192;0m";
         when INFO  => return ASCII.ESC & "[38;2;32;160;64m";
         when DEBUG => return ASCII.ESC & "[38;2;0;128;255m";
         when TRACE => return ASCII.ESC & "[38;2;160;0;160m";
      end case;
   end Level_Color;

   function Format_Message (Level : Log_Level; Message : String) return String
   is
      ANSI_Color   : constant String := Level_Color (Level);
      Level_Image  : constant String := Log_Level'Image (Level);
      Level_String : constant String :=
        Level_Image (Level_Image'First .. Level_Image'Last);
      ANSI_Reset   : constant String := (if Color_Enabled then Reset else "");
   begin
      return
        (ANSI_Color &
         "[" & Level_String & "] " &
         Message &
         ANSI_Reset);
   end Format_Message;

end Logger;
