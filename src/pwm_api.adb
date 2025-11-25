package body PWM_API is

   type Prescaler_Entry is record
      Code  : UInt32;
      Value : UInt32;
   end record;

   Prescalers : constant array (Natural range <>) of Prescaler_Entry :=
     [ (Code => 0, Value => 2),
       (Code => 1, Value => 4),
       (Code => 2, Value => 8),
       (Code => 3, Value => 64),
       (Code => 4, Value => 128),
       (Code => 5, Value => 1024) ];

   --------------------------------------------------------------------
   -- Compute best prescaler + TOP for requested frequency
   --------------------------------------------------------------------
   procedure Compute_Prescaler_And_Top
     (Target_Hz : Float;
      PSC       : out UInt32;
      TOP       : out UInt16)
   is
      Clk_Hz : constant Float := Float (SYSINFO_Periph.CLK);
      Best_Top : Float := 65535.0;
   begin
      for P of Prescalers loop
         declare
            T : constant Float :=
              Clk_Hz / (Float (P.Value) * Target_Hz) - 1.0;
         begin
            if T >= 1.0 and T <= 65535.0 and T < Best_Top then
               Best_Top := T;
               PSC      := P.Code;
               TOP      := UInt16 (Integer (T));
            end if;
         end;
      end loop;
   end Compute_Prescaler_And_Top;

   --------------------------------------------------------------------
   -- Create a new PWM object for a specific channel
   --------------------------------------------------------------------
   function Create (Channel : Natural) return PWM_T is
      PWM : PWM_T;
   begin
      PWM.Channel := Channel;
      return PWM;
   end Create;

   --------------------------------------------------------------------
   -- Set target frequency in Hz
   --------------------------------------------------------------------
   procedure Set_Hz (PWM : in out PWM_T; Target_Hz : Hz_T) is
   begin
      PWM.Target_Hz := Target_Hz;
      Compute_Prescaler_And_Top (Target_Hz, PWM.PSC_Code, PWM.TOP);
   end Set_Hz;

   --------------------------------------------------------------------
   -- Set duty cycle (0.0 = 0%, 1.0 = 100%)
   --------------------------------------------------------------------
   procedure Set_Duty_Cycle (PWM : in out PWM_T; Duty : Percentage_T) is
   begin
      PWM.Duty := Duty;
      PWM.CMP  := UInt16 (Integer (Float (PWM.TOP) * PWM.Duty));
   end Set_Duty_Cycle;

   --------------------------------------------------------------------
   -- Enable the PWM output
   --------------------------------------------------------------------
   procedure Enable (PWM : in out PWM_T) is
   begin
      -- Disable channel before updating
      PWM_Periph.ENABLE := PWM_Periph.ENABLE and not Shift_Left(1, PWM.Channel);

      -- Update prescaler, TOP, CMP
      PWM_Periph.CLKPRSC := PWM.PSC_Code;
      PWM_Periph.CHANNEL (PWM.Channel).TOPCMP.TOP := PWM.TOP;
      PWM_Periph.CHANNEL (PWM.Channel).TOPCMP.CMP := PWM.CMP;

      -- Normal polarity
      PWM_Periph.POLARITY := PWM_Periph.POLARITY and not Shift_Left(1, PWM.Channel);

      -- Enable channel
      PWM_Periph.ENABLE := PWM_Periph.ENABLE or Shift_Left(1, PWM.Channel);

      PWM.Enabled := True;
   end Enable;

   --------------------------------------------------------------------
   -- Disable the PWM output
   --------------------------------------------------------------------
   procedure Disable (PWM : in out PWM_T) is
   begin
      PWM_Periph.ENABLE := PWM_Periph.ENABLE and not Shift_Left(1, PWM.Channel);

      PWM.Enabled := False;
   end Disable;

end PWM_API;
