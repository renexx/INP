-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2018 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): René Bolf xbolfr00@stud.fit.vutbr.cz
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;                           -- hodinovy signal
   RESET : in std_logic;                           -- asynchronni reset procesoru
   EN    : in std_logic;                           -- povoleni cinnosti procesoru

   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti

   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni z pameti (DATA_RDWR='1') / zapis do pameti (DATA_RDWR='0')
   DATA_EN    : out std_logic;                    -- povoleni cinnosti

   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA obsahuje stisknuty znak klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna pokud IN_VLD='1'
   IN_REQ    : out std_logic;                     -- pozadavek na vstup dat z klavesnice

   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- pokud OUT_BUSY='1', LCD je zaneprazdnen, nelze zapisovat,  OUT_WE musi byt '0'
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
-- PC
   signal pc_data : std_logic_vector(11 downto 0);
   signal pc_inc : std_logic;
   signal pc_dec : std_logic;
-- PTR
   signal ptr_data : std_logic_vector(9 downto 0);
   signal ptr_inc : std_logic;
   signal ptr_dec : std_logic;
-- CNT
   signal cnt_data : std_logic_vector(11 downto 0); -- citac poctu zatvoriek
   signal cnt_inc : std_logic;
   signal cnt_dec : std_logic;

   signal mx_wdata_sel : std_logic_vector(1 downto 0);
   signal hexa_signal : std_logic_vector(7 downto 0);
   type fsm_state is (
         init,                -- vychodzi stav
         load_instruc,        -- nacitaj instrukciu
         decode_instruc,      -- dekoduj instrukciu
         inc_ptr,             -- inkrementacia hodnoty ukazatela              >
         dec_ptr,             -- decrementacia hodnoty ukazatela              <
         inc_actual1,         -- inkrementacia hodnoty aktualnej bunky        +
         inc_actual2,         -- inkrementacia hodnoty aktualnej bunky        -
         dec_actual1,         -- dekrementacia hodnoty aktualnej bunky        -
         dec_actual2,         -- dekrementacia hodnoty aktualnej bunky        -
         while1,while2,while3,while4,--                                       [
         while_end1,while_end2,while_end3,while_end4,while_end5,--           ]
         putchar_actual1,     -- vytiskni hodnotu aktualnej bunky            .
         putchar_actual2,     -- vytiskni hodnotu aktualnej bunky            .
         getchar_actual,      -- nacitaj hodnotu a uloz do aktual bunky      ,
         block_comment1,      -- blokovy block_comment                       #
         block_comment2,      -- blokovy block_comment                       #
         block_comment3,      -- blokovy block_comment                       #
         hexa_numbers09,      -- prepis hodnoty aktual bunky hexa hodnotou   0-9
         hexa_numbersAF,      -- prepis hodnoty aktual bunky hexa hodnotou   A-F
         null_return,         -- zastav vykonavanie programu                 null
         others_instruc
   );

   signal pstate : fsm_state;
   signal nstate : fsm_state;

--------------------------------------------------------------------------------
--                   Instrukcne typy
--------------------------------------------------------------------------------
   type inst_type is (
         inc_value_decode,
         dec_value_decode,
         increment_ptr_decode,
         decrement_ptr_decode,
         start_while_decode,
         end_while_decode,
         putch_decode,
         getch_decode,
         comment_decode,
         hex_num09_decode,
         hex_numAF_decode,
         ret_decode,
         others_instruc_decode
   );
   signal instruc_dec : inst_type;

begin
 -------------------------------------------------------------------------------
--                                Register PC
--------------------------------------------------------------------------------
register_pc_proc: process (RESET, CLK)
begin
   if (RESET = '1') then
      pc_data <= (others => '0');
   elsif (CLK'event) and (CLK='1') then
      if (pc_inc = '1') then
         pc_data <= pc_data + 1;
      elsif (pc_dec = '1') then
         pc_data <= pc_data - 1;
      end if;
   end if;
end process;
CODE_ADDR <= pc_data;
--------------------------------------------------------------------------------
--                             Register PTR
--------------------------------------------------------------------------------
register_ptr_proc: process (RESET, CLK)
begin
   if (RESET = '1') then
      ptr_data <= (others => '0');
   elsif (CLK'event) and (CLK = '1') then
      if (ptr_inc = '1') then
         ptr_data <= ptr_data + 1;
      elsif (ptr_dec = '1') then
         ptr_data <= ptr_data - 1;
      end if;
   end if;
end process;
DATA_ADDR <= ptr_data;

--------------------------------------------------------------------------------
--                             Register CNT
--------------------------------------------------------------------------------
register_cnt_proc: process (RESET, CLK)
begin
   if (RESET = '1') then
      cnt_data <= (others => '0');
   elsif (CLK'event) and (CLK = '1') then
      if (cnt_inc = '1') then
         cnt_data <= cnt_data + 1;
      elsif (cnt_dec = '1') then
         cnt_data <= cnt_data - 1;
      end if;
   end if;
end process;
--------------------------------------------------------------------------------
--                   Multiplexor with select
--------------------------------------------------------------------------------
with mx_wdata_sel select
      DATA_WDATA <= IN_DATA              when "00",   -- 00 => zapis dat zo vstupu
                    hexa_signal          when "01",   -- 01 => zapis hexa
                    DATA_RDATA + 1       when "10",   -- 10 => zapis hodnoty aktualnej bunky zvacsenej o 1
                    DATA_RDATA - 1       when "11",   -- 11 => zapis hodnoty aktualnej bunky zmensenej o 1
                    (others => '0')      when others;
----------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                   Proces na dekodovanie instrukci
--------------------------------------------------------------------------------
decode_instruc_process : process(CODE_DATA)
begin
   case(CODE_DATA) is
      when X"3E" => instruc_dec <= increment_ptr_decode;              -- >
      when X"3C" => instruc_dec <= decrement_ptr_decode;              -- <
      when X"2B" => instruc_dec <= inc_value_decode;                  -- +
      when X"2D" => instruc_dec <= dec_value_decode;                  -- -
      when X"5B" => instruc_dec <= start_while_decode;                -- [
      when X"5D" => instruc_dec <= end_while_decode;                  -- ]
      when X"2E" => instruc_dec <= putch_decode;                      -- .
      when X"2C" => instruc_dec <= getch_decode;                      -- ,
      when X"23" => instruc_dec <= comment_decode;                    -- #
      when X"30" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"31" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"32" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"33" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"34" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"35" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"36" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"37" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"38" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"39" => instruc_dec <= hex_num09_decode;                  -- 0-9
      when X"41" => instruc_dec <= hex_numAF_decode;                  -- A-F
      when X"42" => instruc_dec <= hex_numAF_decode;                  -- A-F
      when X"43" => instruc_dec <= hex_numAF_decode;                  -- A-F
      when X"44" => instruc_dec <= hex_numAF_decode;                  -- A-F
      when X"45" => instruc_dec <= hex_numAF_decode;                  -- A-F
      when X"46" => instruc_dec <= hex_numAF_decode;                  -- A-F
      when X"00" => instruc_dec <= ret_decode;                        -- null
      when others=> instruc_dec <= others_instruc_decode;             -- other
   end case;
end process;
--------------------------------------------------------------------------------
--                   FSM PRESENT STATE LOGIKA AKTUALNEHO STAVU
--------------------------------------------------------------------------------
fsm_pstate_process: process (RESET, CLK)
   begin
      if (RESET='1') then
         pstate <= init;
      elsif (CLK'event) and (CLK='1') then
         if (EN = '1') then
            pstate <= nstate;
         end if;
      end if;
end process;
----------------------------------------------------------------------------------------
--                    LOGIKA NASLEDUJUCEHO STAVU A VYSTUPNA LOGIKA
----------------------------------------------------------------------------------------
fsm_nstate_proc : process (pstate, IN_VLD, CODE_DATA, DATA_RDATA, cnt_data, instruc_dec, OUT_BUSY)
begin
   OUT_WE  <= '0';
   IN_REQ  <= '0';
   CODE_EN <= '1';
   DATA_EN <= '0';
   pc_inc  <= '0';
   pc_dec  <= '0';
   ptr_inc <= '0';
   ptr_dec <= '0';
   cnt_inc <= '0';
   cnt_dec <= '0';
   mx_wdata_sel <= "00";

   case pstate is
      when init =>
         nstate <= load_instruc;
      when load_instruc =>
         CODE_EN <= '1';
         nstate <= decode_instruc;
      when decode_instruc =>
         case instruc_dec is
            when ret_decode           => nstate <= null_return;      --   null
            when inc_value_decode     => nstate <= inc_actual1;      --   +
            when dec_value_decode     => nstate <= dec_actual1;      --   -
            when increment_ptr_decode => nstate <= inc_ptr;          --   >
            when decrement_ptr_decode => nstate <= dec_ptr;          --   <
            when start_while_decode   => nstate <= while1;           --   [
            when end_while_decode     => nstate <= while_end1;       --   ]
            when putch_decode         => nstate <= putchar_actual1;  --   .
            when getch_decode         => nstate <= getchar_actual;   --   ,
            when comment_decode       => nstate <= block_comment1;   --   #
            when hex_num09_decode     => nstate <= hexa_numbers09;   --   0-9
            when hex_numAF_decode     => nstate <= hexa_numbersAF;   --   A-F
            when others        => nstate <= others_instruc;
         end case;
--    >   inkrementacia hodnoty ukazatela
      when inc_ptr =>
         ptr_inc <= '1'; -- PTR = PTR + 1
         pc_inc <= '1';  -- PC = PC + 1
         nstate <= load_instruc;
--    <  dekrementacia hodnoty ukazatela
      when dec_ptr =>
         ptr_dec <= '1'; -- PTR = PTR - 1
         pc_inc <= '1';  -- PC = PC + 1
         nstate <= load_instruc;
--    +  inkrementacia hodnoty aktualnej bunky
      when inc_actual1 =>
        DATA_EN  <= '1';       --  DATA_RDATA <- ram[DATA_ADDR] pokial DATA_EN='1'
        DATA_RDWR <= '1';      --  citanie z pamati
        nstate <= inc_actual2;
      when inc_actual2 =>
         DATA_EN  <= '1';      -- DATA_RDATA <- ram[DATA_ADDR] pokial DATA_EN='1'
         DATA_RDWR <= '0';     -- zapis do pamati
         mx_wdata_sel <= "10"; -- 10 => zapis hodnoty aktualnej bunky zvacsenej o 1
         pc_inc  <= '1';       -- PC = PC + 1
         nstate <= load_instruc;
--    -  dekrementacia hodnoty aktualnej bunky
      when dec_actual1 =>
         DATA_EN  <= '1';      --  DATA_RDATA <- ram[DATA_ADDR] pokial DATA_EN='1'
         DATA_RDWR <= '1';     --  citanie z pamati
         nstate <= dec_actual2;
      when dec_actual2 =>
         DATA_EN  <= '1';      -- DATA_RDATA <- ram[DATA_ADDR] pokial DATA_EN='1'
         DATA_RDWR <= '0';     -- zapis do pamati
         mx_wdata_sel <= "11"; -- 11 => zapis hodnoty aktualnej bunky zmensenej o 1
         pc_inc  <= '1';       -- PC = PC + 1
         nstate <= load_instruc;
--    .  vytiskni hodnotu aktualnej bunky
       when putchar_actual1 =>
          if (OUT_BUSY = '0') then -- pokial OUT_BUSY='1', LCD je zaneprazdneny, nejde zapisovat,  OUT_WE musi byt '0'
              DATA_EN <= '1';
              DATA_RDWR <= '1';
              nstate <= putchar_actual2;
          else
              nstate <= putchar_actual1;
         end if;
      when putchar_actual2 =>
         OUT_DATA <= DATA_RDATA;
         OUT_WE <= '1';
         pc_inc <= '1';
         nstate <= load_instruc;
      when getchar_actual =>
         IN_REQ <= '1';           -- poziadavka na vstup dat z klavesnice
         mx_wdata_sel <= "00";    -- 00 => zapis dat ze vstupu
         if(IN_VLD = '1') then    -- data platna pokial IN_VLD='1'
            DATA_EN  <= '1';      -- ram[PTR] = IN_DATA[PTR]
            DATA_RDWR <= '0';     -- zapis do pamati
            pc_inc <= '1';        -- PC = PC + 1
            nstate <= load_instruc;
         else
            nstate <= getchar_actual;
         end if;

--        while start [
      when while1 =>
         DATA_EN <= '1';
         DATA_RDWR <= '1';        -- citanie
         pc_inc <= '1';           -- PC = PC + 1
         nstate <= while2;

      when while2 =>
         if(DATA_RDATA = "00000000") then
            CODE_EN <= '1';
            cnt_inc <= '1';
            nstate <= while3;
         else
            nstate <= load_instruc;
         end if;

      when while3 =>
         if (cnt_data = "00000000") then
            nstate <= load_instruc;
         else
            CODE_EN <= '1';
            nstate <= while4;
         end if;

      when while4 =>
         if(instruc_dec = start_while_decode) then    -- CODE_DATA = X"5B"
            cnt_inc <= '1';
         elsif (instruc_dec = end_while_decode) then  -- CODE_DATA = X"5D"
            cnt_dec <= '1';
         end if;
         pc_inc <= '1';
         nstate <= while3;
--        ] koniec whilu
      when while_end1 =>
         DATA_EN <= '1';
         DATA_RDWR <= '1';
         nstate <= while_end2;

      when while_end2 =>
         if(DATA_RDATA = "00000000") then
            pc_inc <= '1';
            nstate <= load_instruc;
         else
            cnt_inc <= '1';
            pc_dec <= '1';
            nstate <= while_end3;
         end if;

      when while_end3 =>
         if (cnt_data = "00000000") then
           nstate <= load_instruc;
        else
           CODE_EN <= '1';
           nstate <= while_end4;
        end if;

      when while_end4 =>
           if(instruc_dec = end_while_decode) then       -- CODE_DATA = X"5D"
              cnt_inc <= '1';
           elsif (instruc_dec = start_while_decode) then -- CODE_DATA = X"5B"
              cnt_dec <= '1';
           end if;
           nstate <= while_end5;

      when while_end5 =>
         if (cnt_data = "00000000") then
           pc_inc <= '1';
        else
            pc_dec <= '1';
         end if;
         nstate <= while_end3;

      when block_comment1 =>
         pc_inc <= '1';                                  -- PC += 1
         nstate <= block_comment2;
      when block_comment2 =>
         CODE_EN <= '1';
         nstate <= block_comment3;
      when block_comment3 =>
         if(instruc_dec /= comment_decode) then          -- CODE_DATA /= X"23"
            nstate <= block_comment1;
         else
            pc_inc <= '1';
            nstate <= load_instruc;
         end if;
-------------------------------------------------------------------------------
--                            HEX CISLA 0-9
--------------------------------------------------------------------------------
      when hexa_numbers09 =>
         DATA_EN <= '1';
         CODE_EN <= '1';
         DATA_RDWR <= '0';
         pc_inc <= '1';
         mx_wdata_sel <= "01";                           -- 01 zapis hexa
         case CODE_DATA is
            when X"30" => hexa_signal <= "00000000";
            when X"31" => hexa_signal <= "00010000";
            when X"32" => hexa_signal <= "00100000";
            when X"33" => hexa_signal <= "00110000";
            when X"34" => hexa_signal <= "01000000";
            when X"35" => hexa_signal <= "01010000";
            when X"36" => hexa_signal <= "01100000";
            when X"37" => hexa_signal <= "01110000";
            when X"38" => hexa_signal <= "10000000";
            when X"39" => hexa_signal <= "10010000";
            when others =>
         end case;
         nstate <= load_instruc;
--------------------------------------------------------------------------------
--                            HEX CISLA A-F
--------------------------------------------------------------------------------
      when hexa_numbersAF =>
         DATA_EN <= '1';
         CODE_EN <= '1';
         DATA_RDWR <= '0';
         pc_inc <= '1';
         mx_wdata_sel <= "01";
         case CODE_DATA is
            when X"41" => hexa_signal <= "10100000";
            when X"42" => hexa_signal <= "10110000";
            when X"43" => hexa_signal <= "11000000";
            when X"44" => hexa_signal <= "11010000";
            when X"45" => hexa_signal <= "11100000";
            when X"46" => hexa_signal <= "11110000";
            when others =>
         end case;
         nstate <= load_instruc;
      when null_return =>
         nstate <= null_return;
      when others_instruc =>
         pc_inc <= '1';
         nstate <= load_instruc;
      when others =>
   end case;
end process;
end behavioral;
