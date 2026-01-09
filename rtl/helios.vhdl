library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity helios is
  port (
    clk_i  : in  std_ulogic;  -- 100 MHz on Basys3
    rst_i  : in  std_ulogic;  -- ACTIVE-HIGH reset

    vga_hsync_o : out std_ulogic;
    vga_vsync_o : out std_ulogic;
    vga_r_o     : out std_ulogic_vector(3 downto 0);
    vga_g_o     : out std_ulogic_vector(3 downto 0);
    vga_b_o     : out std_ulogic_vector(3 downto 0)
  );
end entity;

architecture rtl of helios is

  -- ============================================================
  -- Pixel clock: 100 MHz / 4 = 25 MHz
  -- ============================================================
  signal div_cnt : unsigned(1 downto 0) := (others => '0');
  signal pixclk  : std_ulogic := '0';

  -- ============================================================
  -- VGA timing (timing-only module)
  -- ============================================================
  signal hsync_s  : std_ulogic;
  signal vsync_s  : std_ulogic;
  signal active_s : std_ulogic;
  signal x_s      : unsigned(9 downto 0);
  signal y_s      : unsigned(9 downto 0);

  -- Delay to match BRAM registered read latency (1 cycle)
  signal hsync_d  : std_ulogic := '1';
  signal vsync_d  : std_ulogic := '1';
  signal active_d : std_ulogic := '0';

  -- ============================================================
  -- Framebuffer: 160x120 RGB332 (8-bit)
  -- ============================================================
  signal fb_we_a   : std_ulogic := '0';
  signal fb_addr_a : unsigned(14 downto 0) := (others => '0');
  signal fb_din_a  : std_ulogic_vector(7 downto 0) := (others => '0');

  signal fb_addr_b : unsigned(14 downto 0) := (others => '0');
  signal fb_dout_b : std_ulogic_vector(7 downto 0);

  -- Scaled coordinates (map 640x480 -> 160x120 by /4)
  signal fb_x : unsigned(7 downto 0);  -- 0..159
  signal fb_y : unsigned(6 downto 0);  -- 0..119

  -- Expanded RGB444 output (from RGB332)
  signal r4 : std_ulogic_vector(3 downto 0) := (others => '0');
  signal g4 : std_ulogic_vector(3 downto 0) := (others => '0');
  signal b4 : std_ulogic_vector(3 downto 0) := (others => '0');

  -- ============================================================
  -- Test writer state (fills framebuffer once after reset)
  -- ============================================================
  signal wr_addr : unsigned(14 downto 0) := (others => '0');
  signal wr_done : std_ulogic := '0';

begin

  -- /4 clock divider -> 25 MHz
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        div_cnt <= (others => '0');
        pixclk  <= '0';
      else
        div_cnt <= div_cnt + 1;
        pixclk  <= div_cnt(1);
      end if;
    end if;
  end process;

  -- VGA timing generator (must provide x/y/active)
  u_timing : entity work.vga_640x480_timing
    port map (
      pixclk_i => pixclk,
      rst_i    => rst_i,
      hsync_o  => hsync_s,
      vsync_o  => vsync_s,
      active_o => active_s,
      x_o      => x_s,
      y_o      => y_s
    );

  -- Framebuffer BRAM (single clock for both ports)
  u_fb : entity work.fb_bram_rgb332_160x120
    port map (
      clk_i    => pixclk,

      we_a_i   => fb_we_a,
      addr_a_i => fb_addr_a,
      din_a_i  => fb_din_a,

      addr_b_i => fb_addr_b,
      dout_b_o => fb_dout_b
    );

  -- Scale VGA coords down by 4:
  -- x: 0..639 -> /4 => 0..159 (8 bits)  => x_s(9 downto 2) is 8 bits OK
  -- y: 0..479 -> /4 => 0..119 (7 bits)  => y_s(8 downto 2) is 7 bits OK
  fb_x <= x_s(9 downto 2);
  fb_y <= y_s(8 downto 2);  -- <-- THIS fixes the 7-bit vs 8-bit mismatch

  -- Compute framebuffer read address: addr = fb_y*160 + fb_x
  -- 160 = 128 + 32 => (y<<7) + (y<<5)
  fb_addr_b <= resize( (resize(fb_y, 15) sll 7) + (resize(fb_y, 15) sll 5) + resize(fb_x, 15), 15);

  -- Delay sync/active 1 cycle to align with fb_dout_b (registered)
  process(pixclk)
    variable px : std_ulogic_vector(7 downto 0);
  begin
    if rising_edge(pixclk) then
      if rst_i = '1' then
        hsync_d  <= '1';
        vsync_d  <= '1';
        active_d <= '0';
        r4 <= (others => '0');
        g4 <= (others => '0');
        b4 <= (others => '0');
      else
        hsync_d  <= hsync_s;
        vsync_d  <= vsync_s;
        active_d <= active_s;

        px := fb_dout_b;  -- pixel from previous cycle’s address

        -- RGB332 -> RGB444 expansion
        -- R: [7:5] -> 4 bits by repeating MSB
        r4 <= px(7 downto 5) & px(7);
        -- G: [4:2] -> 4 bits by repeating MSB
        g4 <= px(4 downto 2) & px(4);
        -- B: [1:0] -> 4 bits by repeating pattern
        b4 <= px(1 downto 0) & px(1 downto 0);
      end if;
    end if;
  end process;

  vga_hsync_o <= hsync_d;
  vga_vsync_o <= vsync_d;

  -- Blank outside active region
  vga_r_o <= r4 when active_d = '1' else (others => '0');
  vga_g_o <= g4 when active_d = '1' else (others => '0');
  vga_b_o <= b4 when active_d = '1' else (others => '0');

  -- ============================================================
  -- Test writer: fill framebuffer once after reset
  -- Produces simple vertical color bars in RGB332
  -- ============================================================
  process(pixclk)
    variable a   : integer;
    variable x   : integer;
    variable bar : integer;

    variable r3  : unsigned(2 downto 0);
    variable g3  : unsigned(2 downto 0);
    variable b2  : unsigned(1 downto 0);
  begin
    if rising_edge(pixclk) then
      if rst_i = '1' then
        wr_addr <= (others => '0');
        wr_done <= '0';
        fb_we_a <= '0';
        fb_addr_a <= (others => '0');
        fb_din_a  <= (others => '0');
      else
        if wr_done = '0' then
          fb_we_a   <= '1';
          fb_addr_a <= wr_addr;

          a := to_integer(wr_addr);
          x := a mod 160;
          bar := x / 20;  -- 0..7

          -- 8 bars in RGB332
          case bar is
            when 0 => r3 := "111"; g3 := "000"; b2 := "00"; -- red
            when 1 => r3 := "111"; g3 := "111"; b2 := "00"; -- yellow
            when 2 => r3 := "000"; g3 := "111"; b2 := "00"; -- green
            when 3 => r3 := "000"; g3 := "111"; b2 := "11"; -- cyan
            when 4 => r3 := "000"; g3 := "000"; b2 := "11"; -- blue
            when 5 => r3 := "111"; g3 := "000"; b2 := "11"; -- magenta
            when 6 => r3 := "111"; g3 := "111"; b2 := "11"; -- white
            when others => r3 := "001"; g3 := "001"; b2 := "01"; -- dim gray
          end case;

          fb_din_a <= std_ulogic_vector(r3) & std_ulogic_vector(g3) & std_ulogic_vector(b2);

          if wr_addr = to_unsigned(19199, wr_addr'length) then
            wr_done <= '1';
            fb_we_a <= '0';
          else
            wr_addr <= wr_addr + 1;
          end if;

        else
          fb_we_a <= '0';
        end if;
      end if;
    end if;
  end process;

end architecture;
