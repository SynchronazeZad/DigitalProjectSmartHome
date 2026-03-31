library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
    generic (
        CLKS_PER_BIT : integer := 10417
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        rx_serial : in  std_logic;
        rx_dv     : out std_logic;
        rx_byte   : out std_logic_vector(7 downto 0)
    );
end uart_rx;

architecture rtl of uart_rx is
    type state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT, CLEANUP);
    signal state      : state_type := IDLE;

    signal clk_count  : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_index  : integer range 0 to 7 := 0;
    signal rx_shift   : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_data_v  : std_logic := '0';

    signal rx_sync_0  : std_logic := '1';
    signal rx_sync_1  : std_logic := '1';
begin

    process(clk)
    begin
        if rising_edge(clk) then
            rx_sync_0 <= rx_serial;
            rx_sync_1 <= rx_sync_0;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= IDLE;
                clk_count <= 0;
                bit_index <= 0;
                rx_shift  <= (others => '0');
                rx_data_v <= '0';
            else
                rx_data_v <= '0';

                case state is
                    when IDLE =>
                        clk_count <= 0;
                        bit_index <= 0;

                        if rx_sync_1 = '0' then
                            state <= START_BIT;
                        end if;

                    when START_BIT =>
                        if clk_count = (CLKS_PER_BIT - 1) / 2 then
                            if rx_sync_1 = '0' then
                                clk_count <= 0;
                                state <= DATA_BITS;
                            else
                                state <= IDLE;
                            end if;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                    when DATA_BITS =>
                        if clk_count < CLKS_PER_BIT - 1 then
                            clk_count <= clk_count + 1;
                        else
                            clk_count <= 0;
                            rx_shift(bit_index) <= rx_sync_1;

                            if bit_index < 7 then
                                bit_index <= bit_index + 1;
                            else
                                bit_index <= 0;
                                state <= STOP_BIT;
                            end if;
                        end if;

                    when STOP_BIT =>
                        if clk_count < CLKS_PER_BIT - 1 then
                            clk_count <= clk_count + 1;
                        else
                            rx_data_v <= '1';
                            clk_count <= 0;
                            state <= CLEANUP;
                        end if;

                    when CLEANUP =>
                        state <= IDLE;

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    rx_dv   <= rx_data_v;
    rx_byte <= rx_shift;

end rtl;