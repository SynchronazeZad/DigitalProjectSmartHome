library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_basys3_main is
    port (
        clk100mhz : in  std_logic;
        btnC      : in  std_logic;

        uart_rx_i : in  std_logic;
        uart_tx_o : out std_logic;

        led       : out std_logic_vector(15 downto 0);
        seg       : out std_logic_vector(6 downto 0);
        dp        : out std_logic;
        an        : out std_logic_vector(3 downto 0)
    );
end top_basys3_main;

architecture rtl of top_basys3_main is

    constant HOLD_15S_COUNT : unsigned(31 downto 0) := to_unsigned(1500000000, 32);
    constant HOLD_5S_COUNT  : unsigned(31 downto 0) := to_unsigned(500000000, 32);

    signal rx_dv      : std_logic;
    signal rx_byte    : std_logic_vector(7 downto 0);

    signal tx_dv      : std_logic := '0';
    signal tx_byte    : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_active  : std_logic;
    signal tx_done    : std_logic;

    signal motion_raw : std_logic := '0';
    signal near_raw   : std_logic := '0';

    signal system_active      : std_logic := '0';
    signal system_active_prev : std_logic := '0';
    signal servo_open         : std_logic := '0';

    signal motion_cnt : unsigned(31 downto 0) := (others => '0');
    signal near_cnt   : unsigned(31 downto 0) := (others => '0');

    signal led_desired   : std_logic := '0';
    signal relay_desired : std_logic := '0';
    signal servo_desired : std_logic := '0';

    signal led_sent      : std_logic := '0';
    signal relay_sent    : std_logic := '0';
    signal servo_sent    : std_logic := '0';

    signal beep_request  : std_logic := '0';

    signal heartbeat_cnt : unsigned(25 downto 0) := (others => '0');

    type tx_state_type is (TX_IDLE, TX_LED, TX_RELAY, TX_SERVO, TX_BEEP);
    signal tx_state : tx_state_type := TX_IDLE;

    function seven_seg_digit(d : std_logic) return std_logic_vector is
        variable s : std_logic_vector(6 downto 0);
    begin
        if d = '1' then
            s := "1111001"; -- 1
        else
            s := "1000000"; -- 0
        end if;
        return s;
    end function;

begin

    U_RX : entity work.uart_rx
        generic map (
            CLKS_PER_BIT => 10417
        )
        port map (
            clk       => clk100mhz,
            rst       => btnC,
            rx_serial => uart_rx_i,
            rx_dv     => rx_dv,
            rx_byte   => rx_byte
        );

    U_TX : entity work.uart_tx
        generic map (
            CLKS_PER_BIT => 10417
        )
        port map (
            clk       => clk100mhz,
            rst       => btnC,
            tx_dv     => tx_dv,
            tx_byte   => tx_byte,
            tx_active => tx_active,
            tx_serial => uart_tx_o,
            tx_done   => tx_done
        );

    process(clk100mhz)
    begin
        if rising_edge(clk100mhz) then
            if btnC = '1' then
                motion_raw <= '0';
                near_raw   <= '0';
            else
                if rx_dv = '1' then
                    case rx_byte is
                        when x"4D" => motion_raw <= '1'; -- M
                        when x"6D" => motion_raw <= '0'; -- m
                        when x"4E" => near_raw   <= '1'; -- N
                        when x"6E" => near_raw   <= '0'; -- n
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    process(clk100mhz)
    begin
        if rising_edge(clk100mhz) then
            if btnC = '1' then
                system_active      <= '0';
                system_active_prev <= '0';
                servo_open         <= '0';
                motion_cnt         <= (others => '0');
                near_cnt           <= (others => '0');
                heartbeat_cnt      <= (others => '0');
                beep_request       <= '0';
            else
                heartbeat_cnt <= heartbeat_cnt + 1;
                beep_request  <= '0';

                if motion_raw = '1' then
                    system_active <= '1';
                    motion_cnt <= (others => '0');
                else
                    if system_active = '1' then
                        if motion_cnt < HOLD_15S_COUNT then
                            motion_cnt <= motion_cnt + 1;
                        else
                            system_active <= '0';
                            motion_cnt <= (others => '0');
                        end if;
                    else
                        motion_cnt <= (others => '0');
                    end if;
                end if;

                if near_raw = '1' then
                    servo_open <= '1';
                    near_cnt <= (others => '0');
                else
                    if servo_open = '1' then
                        if near_cnt < HOLD_5S_COUNT then
                            near_cnt <= near_cnt + 1;
                        else
                            servo_open <= '0';
                            near_cnt <= (others => '0');
                        end if;
                    else
                        near_cnt <= (others => '0');
                    end if;
                end if;

                if system_active /= system_active_prev then
                    beep_request <= '1';
                end if;

                system_active_prev <= system_active;
            end if;
        end if;
    end process;

    led_desired   <= system_active;
    relay_desired <= system_active;
    servo_desired <= servo_open;

    process(clk100mhz)
    begin
        if rising_edge(clk100mhz) then
            if btnC = '1' then
                tx_dv      <= '0';
                tx_byte    <= (others => '0');
                led_sent   <= '0';
                relay_sent <= '0';
                servo_sent <= '0';
                tx_state   <= TX_IDLE;
            else
                tx_dv <= '0';

                case tx_state is
                    when TX_IDLE =>
                        if tx_active = '0' then
                            if led_sent /= led_desired then
                                if led_desired = '1' then
                                    tx_byte <= x"4C"; -- L
                                else
                                    tx_byte <= x"6C"; -- l
                                end if;
                                tx_dv <= '1';
                                tx_state <= TX_LED;

                            elsif relay_sent /= relay_desired then
                                if relay_desired = '1' then
                                    tx_byte <= x"52"; -- R
                                else
                                    tx_byte <= x"72"; -- r
                                end if;
                                tx_dv <= '1';
                                tx_state <= TX_RELAY;

                            elsif servo_sent /= servo_desired then
                                if servo_desired = '1' then
                                    tx_byte <= x"53"; -- S
                                else
                                    tx_byte <= x"73"; -- s
                                end if;
                                tx_dv <= '1';
                                tx_state <= TX_SERVO;

                            elsif beep_request = '1' then
                                tx_byte <= x"42"; -- B
                                tx_dv <= '1';
                                tx_state <= TX_BEEP;
                            end if;
                        end if;

                    when TX_LED =>
                        if tx_done = '1' then
                            led_sent <= led_desired;
                            tx_state <= TX_IDLE;
                        end if;

                    when TX_RELAY =>
                        if tx_done = '1' then
                            relay_sent <= relay_desired;
                            tx_state <= TX_IDLE;
                        end if;

                    when TX_SERVO =>
                        if tx_done = '1' then
                            servo_sent <= servo_desired;
                            tx_state <= TX_IDLE;
                        end if;

                    when TX_BEEP =>
                        if tx_done = '1' then
                            tx_state <= TX_IDLE;
                        end if;

                    when others =>
                        tx_state <= TX_IDLE;
                end case;
            end if;
        end if;
    end process;

    process(system_active, servo_open, motion_raw, near_raw, heartbeat_cnt)
        variable led_tmp : std_logic_vector(15 downto 0);
    begin
        led_tmp := (others => '0');
        led_tmp(0) := motion_raw;
        led_tmp(1) := near_raw;
        led_tmp(2) := system_active;
        led_tmp(3) := servo_open;
        led_tmp(4) := heartbeat_cnt(25);
        led <= led_tmp;
    end process;

    an  <= "1110";
    dp  <= '1';
    seg <= seven_seg_digit(system_active);

end rtl;