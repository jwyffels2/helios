with Uart0;
with Gnat_Exit;
with PWM_API;  use PWM_API;
with GPIO_API; use GPIO_API;
with neorv32;  use neorv32;
with neorv32.TWI; use neorv32.TWI;
with Ada.Text_IO;

procedure Helios is
   -- Create PWM
   Pwm0: PWM_T := PWM_API.Create (Channel => 0);
begin

   Pwm0.Configure (Target_Hz => 25_000_000.0, Duty => 0.5);
   Pwm0.Enable;



end Helios;

procedure twi_available return Boolean;
procedure twi_setup(preScaler: Natural range 0 .. 7; clockDiv:Natural range 0 .. 15; allowClockStretching : Boolean);
function  twi_get_fifo_depth return Integer;
procedure twi_disable;
procedure twi_enable;

function  twi_sense_scl return Boolean; --Make subtype of boolean for high/low
function  twi_sense_sda return Boolean;

function twi_busy return Boolean;


--   /**********************************************************************//**
--   * Get received data + ACK/NACH from RX FIFO.
--   *
--   * @param[in,out] data Pointer for returned data (uint8_t).
--   * @return RX FIFO access status (-1 = no data available, 0 = ACK received, 1 = NACK received).
--   Should use return enum
--   **************************************************************************/
function twi_get (Data : out Integer);

--   * @return 0: ACK received, 1: NACK received.
--  Replace Ack_Next type and return type with Enum for Ack or subtype boolean
function twi_transfer(Data: in out Integer; Ack_Next: in Boolean) return Integer;
procedure twi_stop;
procedure twi_start;

procedure twi_send_nonblocking(Data: in Integer; Ack_Next: in Boolean);

procedure twi_generate_start_nonblocking;
procedure twi_generate_stop_nonblocking;
