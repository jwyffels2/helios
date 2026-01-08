library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package vga_fb_pkg is
  -- Step 1 contract: pick a fixed address window for framebuffer writes.
  -- Keep it simple + small at first.
  constant VGA_FB_BASE : std_logic_vector(31 downto 0) := x"F000_0000";
  constant VGA_FB_SIZE : natural := 64 * 1024; -- 64 KiB window (placeholder)

  -- Initial assumptions (can change later, but lock for now):
  constant VGA_FB_W    : natural := 160;
  constant VGA_FB_H    : natural := 120;
  -- Pixel format placeholder: 8-bit packed color (e.g., RGB332)
end package;
