library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    generic (
        CLKS_PER_BIT : integer := 10417
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        tx_dv     : in  std_logic;
        tx_byte   : in  std_logic_vector(7 downto 0);
        tx_active : out std_logic;
        tx_serial : out std_logic;
        tx_done   : out std_logic
    );
end uart_tx;

architecture rtl of uart_tx is
    type state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT, CLEANUP);
    signal state      : state_type := IDLE;

    signal clk_count  : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_index  : integer range 0 to 7 := 0;
    signal tx_data    : std_logic_vector(7 downto 0) := (others => '0');

    signal tx_reg     : std_logic := '1';
    signal tx_busy    : std_logic := '0';
    signal tx_done_i  : std_logic := '0';
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= IDLE;
                clk_count <= 0;
                bit_index <= 0;
                tx_data   <= (others => '0');
                tx_reg    <= '1';
                tx_busy   <= '0';
                tx_done_i <= '0';
            else
                tx_done_i <= '0';

                case state is
                    when IDLE =>
                        tx_reg    <= '1';
                        tx_busy   <= '0';
                        clk_count <= 0;
                        bit_index <= 0;

                        if tx_dv = '1' then
                            tx_data <= tx_byte;
                            tx_busy <= '1';
                            state <= START_BIT;
                        end if;

                    when START_BIT =>
                        tx_reg <= '0';
                        if clk_count < CLKS_PER_BIT - 1 then
                            clk_count <= clk_count + 1;
                        else
                            clk_count <= 0;
                            state <= DATA_BITS;
                        end if;

                    when DATA_BITS =>
                        tx_reg <= tx_data(bit_index);
                        if clk_count < CLKS_PER_BIT - 1 then
                            clk_count <= clk_count + 1;
                        else
                            clk_count <= 0;
                            if bit_index < 7 then
                                bit_index <= bit_index + 1;
                            else
                                bit_index <= 0;
                                state <= STOP_BIT;
                            end if;
                        end if;

                    when STOP_BIT =>
                        tx_reg <= '1';
                        if clk_count < CLKS_PER_BIT - 1 then
                            clk_count <= clk_count + 1;
                        else
                            clk_count <= 0;
                            tx_done_i <= '1';
                            state <= CLEANUP;
                        end if;

                    when CLEANUP =>
                        tx_busy <= '0';
                        state <= IDLE;

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    tx_serial <= tx_reg;
    tx_active <= tx_busy;
    tx_done   <= tx_done_i;

end rtl;