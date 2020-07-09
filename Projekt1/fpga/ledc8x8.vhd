-- vypracoval René Bolf (xbolfr00@stud.fit.vutbr.cz) ----

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;

entity ledc8x8 is
port ( -- Sem doplnte popis rozhrani obvodu.
      SMCLK: in std_logic;
      RESET: in std_logic;
      ROW: out std_logic_vector (0 to 7);
      LED: out std_logic_vector (0 to 7)
    );
end ledc8x8;

architecture main of ledc8x8 is

   signal led_sig : std_logic_vector(7 downto 0) := (others => '0'); --signal pre ledky
   signal row_sig : std_logic_vector(7 downto 0) := (others => '0'); --signal pre riadky
   signal clock_enable_counter: std_logic_vector(11 downto 0) := (others => '0'); --7372800/256/8=3600
   signal clock_enable: std_logic;
   signal state : std_logic_vector(1 downto 0) := (others => '0');
   signal switch_state :std_logic_vector(20 downto 0):= (others => '0');--7372800/4=1843200
begin

   clock_enable_generator: process(SMCLK, RESET)
   begin
      if RESET = '1' then 
         clock_enable_counter <= (others => '0') ;
      elsif SMCLK'event and SMCLK = '1' then 
          clock_enable_counter <= clock_enable_counter + 1;
      end if;
  end process clock_enable_generator;
   clock_enable <= '1' when clock_enable_counter = "111000010000" else '0';  -- nastavi clock enable na 1 ked counter bude 3600

--zmena stavov chceme 4 stavy R nic B nic teda 00 01 10 11 7372800/4
   zmen: process(SMCLK, RESET)
   begin
      if RESET = '1' then 
         switch_state <= (others => '0'); 
      elsif SMCLK'event and SMCLK = '1' then 
	      switch_state <= switch_state + 1;
      if switch_state= "111000010000000000000" then
        state <= state + 1;
        switch_state <= (others => '0');   
      end if;
   end if;
   end process zmen;
-- rotacia riadkov
   rotation: process(RESET, clock_enable, SMCLK)
   begin
      if RESET = '1' then 
         row_sig <= "10000000";
      elsif SMCLK'event and SMCLK = '1' and clock_enable = '1' then
         row_sig <= row_sig(0) & row_sig(7 downto 1); --konkatenacia na posunutie jednotky
      end if;
   end process rotation;

   initial1 : process (row_sig, state)
   begin
      if state = "00" then
         case row_sig is
            when "10000000" => led_sig <= "00001111";     --R
            when "01000000" => led_sig <= "01110111";
            when "00100000" => led_sig <= "01110111";
            when "00010000" => led_sig <= "00001111";
            when "00001000" => led_sig <= "01011111";
            when "00000100" => led_sig <= "01101111";
            when "00000010" => led_sig <= "01110111";
            when "00000001" => led_sig <= "01111011";
            when others     => led_sig <= "11111111";
        end case;
    end if;
    if state = "01" then
        case row_sig is
          when "10000000" => led_sig <= "11111111"; --nic
          when "01000000" => led_sig <= "11111111";
          when "00100000" => led_sig <= "11111111";
          when "00010000" => led_sig <= "11111111";
          when "00001000" => led_sig <= "11111111";
          when "00000100" => led_sig <= "11111111";
          when "00000010" => led_sig <= "11111111";
          when "00000001" => led_sig <= "11111111";
          when others     => led_sig <= "11111111";
      end case;
   end if;
   if state = "10" then
      case row_sig is
        when "10000000" => led_sig <= "00001111"; --B
        when "01000000" => led_sig <= "01110111";
        when "00100000" => led_sig <= "01110111";
        when "00010000" => led_sig <= "00001111";
        when "00001000" => led_sig <= "01110111";
        when "00000100" => led_sig <= "01110111";
        when "00000010" => led_sig <= "01110111";
        when "00000001" => led_sig <= "00001111";
        when others     => led_sig <= "11111111";
      end case;
   end if;
   if state = "11" then
      case row_sig is
        when "10000000" => led_sig <= "11111111"; --nic
        when "01000000" => led_sig <= "11111111";
        when "00100000" => led_sig <= "11111111";
        when "00010000" => led_sig <= "11111111";
        when "00001000" => led_sig <= "11111111";
        when "00000100" => led_sig <= "11111111";
        when "00000010" => led_sig <= "11111111";
        when "00000001" => led_sig <= "11111111";
        when others     => led_sig <= "11111111";
    end case;
    end if;
  end process;
  blinking : process (row_sig)
  begin	  
   if state = "00" then
         LED <= led_sig;
   elsif state = "01" then
         LED <= led_sig;
   elsif state = "10" then
         LED <= led_sig;
   elsif state = "11" then
         LED <= led_sig;
   else
         LED <= "11111111";
   end if;
   ROW <= row_sig;
end process;   

end architecture main;
