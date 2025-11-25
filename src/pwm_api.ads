with neorv32; use neorv32;
with neorv32.PWM; use neorv32.PWM;
with neorv32.SYSINFO; use neorv32.SYSINFO;

package PWM_API is

   type PWM_T is tagged private;

   subtype Hz_T is Float range 1.5 .. Float'Last;
   subtype Percentage_T is Float range 0.0 .. 1.0;

   -- Create a new PWM object for a specific channel
   function Create (Channel : Natural) return PWM_T;

   -- Set target frequency in Hz
   procedure Set_Hz (PWM : in out PWM_T; Target_Hz : Hz_T);

   -- Set duty cycle (0.0 = 0%, 1.0 = 100%)
   procedure Set_Duty_Cycle (PWM : in out PWM_T; Duty : Percentage_T);

   -- Enable the PWM output
   procedure Enable (PWM : in out PWM_T);

   -- Disable the PWM output
   procedure Disable (PWM : in out PWM_T);

private
   type PWM_T is tagged record
      Channel      : Natural := 0;
      TOP          : UInt16  := 0;
      CMP          : UInt16  := 0;
      PSC_Code     : UInt32  := 0;
      Duty         : Float   := 0.5;
      Target_Hz    : Float   := 5.0;
      Enabled      : Boolean := False;
   end record;

end PWM_API;
