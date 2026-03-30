with Uart0;
with Ada.Text_IO; use Ada.Text_IO;

package body Logger is

   --  ANSI escape sequence to reset terminal formatting
   Reset : constant String := ASCII.ESC & "[0m";

   ----------------------------------------------------------------------------
   --  Helper function declarations
   ----------------------------------------------------------------------------

   --  Returns the ANSI color escape sequence corresponding to a log level
   --  If color is disabled, returns an empty string
   function Level_Color (Level : Log_Level) return String;

   --  Converts a log level enum into its string representation
   --  (e.g., Error -> "ERROR")
   function Level_To_String (Level : Log_Level) return String;

   --  Builds the final formatted log message including:
   --    - Optional color prefix
   --    - [LEVEL] tag
   --    - Message text
   --    - Optional reset sequence
   function Format_Message (Level : Log_Level; Message : String) return String;

   ----------------------------------------------------------------------------
   --  Public API implementation
   ----------------------------------------------------------------------------

   procedure Log (Level : Log_Level; Message : String)
   is
      Line : constant String := Format_Message (Level, Message);
   begin
      Put_Line (Line);
   end Log;

   procedure Error (Message : String)
   is
   begin
      Log (Error, Message);
   end Error;

   procedure Warn (Message : String)
   is
   begin
      Log (Warn, Message);
   end Warn;

   procedure Trace (Message : String)
   is
   begin
      Log (Trace, Message);
   end Trace;

   procedure Debug (Message : String)
   is
   begin
      Log (Debug, Message);
   end Debug;

   procedure Info (Message : String)
   is
   begin
      Log (Info, Message);
   end Info;

   procedure Enable_Color
   is
   begin
      Color_Enabled := True;
   end Enable_Color;

   procedure Disable_Color
   is
   begin
      Color_Enabled := False;
   end Disable_Color;

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
         when Error => return ASCII.ESC & "[38;2;255;48;64m";
         when Warn  => return ASCII.ESC & "[38;2;255;192;0m";
         when Trace => return ASCII.ESC & "[38;2;160;0;160m";
         when Debug => return ASCII.ESC & "[38;2;0;128;255m";
         when Info  => return ASCII.ESC & "[38;2;32;160;64m";
      end case;
   end Level_Color;

   function Level_To_String (Level : Log_Level) return String
   is
   begin
      case Level is
         when Error => return "ERROR";
         when Warn  => return "WARN";
         when Trace => return "TRACE";
         when Debug => return "DEBUG";
         when Info  => return "INFO";
      end case;
   end Level_To_String;

   function Format_Message (Level : Log_Level; Message : String) return String
   is
      ANSI_Color   : constant String := Level_Color (Level);
      Level_String : constant String := Level_To_String (Level);
      ANSI_Reset   : constant String := (if Color_Enabled then Reset else "");
   begin
      return
        (ANSI_Color &
         "[" & Level_String & "] " &
         Message &
         ANSI_Reset);
   end Format_Message;

end Logger;
