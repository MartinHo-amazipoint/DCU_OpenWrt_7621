#!/bin/sh

# --- CONFIGURATION ---
TEST_IP="192.168.1.2"
MODEM_PORT="/dev/ttyACM2"
GPIO_BASE="480"

# 4G Modem Pins
G_SHDN=499   
G_W_EN=504   
G_AWAKE=480  
G_PWR_P=448  

# Power Detection Pin
PWR_REAL_GPIO=507

# Board LED Register Addresses
REG_GPIO_MODE=0x1E000060
REG_GPIO_DIR=0x1E000600
REG_GPIO_SET=0x1E000630  
REG_GPIO_CLR=0x1E000640  
LED_MASK=0xB0000000
# ---------------------

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper: Turn on 4G LED
modem_led_on() {
    [ -e "$MODEM_PORT" ] && printf "AT#GPIO=4,1,1\r\n" > "$MODEM_PORT"
}

# 1. RTC Test
test_rtc() {
    echo -n "Testing RTC (BQ32002): "
    [ ! -e /dev/rtc0 ] && echo -e "${RED}[FAILED]${NC}" && return 1
    RTC_VAL=$(hwclock -r 2>/dev/null)
    [ $? -eq 0 ] && echo -e "${GREEN}[PASS]${NC} ($RTC_VAL)" || echo -e "${RED}[FAILED]${NC}"
}

# 2. SD Card Test
test_sd() {
    while true; do
        echo -n "Testing Micro SD Card: "
        KLEVEL=$(cat /proc/sys/kernel/printk | cut -f1); echo 1 > /proc/sys/kernel/printk
        PASSED=1
        if [ -e /dev/mmcblk0 ]; then
            DEV="/dev/mmcblk0"; [ -e "/dev/mmcblk0p1" ] && DEV="/dev/mmcblk0p1"
            MNT="/tmp/sd_test_mnt"; mkdir -p $MNT; umount $MNT >/dev/null 2>&1
            if mount $DEV $MNT >/dev/null 2>&1; then
                echo "test" > "$MNT/test.tmp" 2>/dev/null && rm "$MNT/test.tmp" && umount $MNT && PASSED=0
            fi
        fi
        echo "$KLEVEL" > /proc/sys/kernel/printk
        if [ $PASSED -eq 0 ]; then echo -e "${GREEN}[PASS]${NC}"; return 0; fi
        echo -e "${RED}[FAILED]${NC}"
        echo -e "${YELLOW}>>> PLEASE INSERT MICRO SD CARD AND PRESS [ENTER]...${NC}"
        read p
    done
}

# 3. LAN Test
test_lan() {
    while true; do
        echo -n "Testing LAN Ping ($TEST_IP): "
        if ping -c 2 -W 2 $TEST_IP > /dev/null 2>&1; then
            echo -e "${GREEN}[PASS]${NC}"; return 0
        fi
        echo -e "${RED}[FAILED]${NC}"
        echo -e "${YELLOW}>>> PLEASE PLUG IN RJ45 CABLE AND PRESS [ENTER]...${NC}"
        read p
    done
}

# 4. Board LED Test
test_leds() {
    echo -e "${YELLOW}Watching Board LEDs (Yel/Red/Grn)! Blinking for 3s...${NC}"
    devmem $REG_GPIO_DIR 32 $(printf "0x%x" $(( $(devmem $REG_GPIO_DIR) | $LED_MASK )) )
    count=0
    while [ $count -lt 6 ]; do
        devmem $REG_GPIO_CLR 32 $LED_MASK; usleep 250000
        devmem $REG_GPIO_SET 32 $LED_MASK; usleep 250000
        count=$((count + 1))
    done
    echo -e "Board LEDs: ${GREEN}[DONE]${NC}"
}

# 5. 4G Modem & SIM Test
test_4g() {
    while true; do
        echo -n "Testing 4G Modem & SIM: "
        if [ -e "$MODEM_PORT" ]; then
            rm -f /tmp/at_res.txt
            cat "$MODEM_PORT" > /tmp/at_res.txt &
            CPID=$!
            printf "AT+CPIN?\r\n" > "$MODEM_PORT"
            sleep 1
            kill $CPID 2>/dev/null
            wait $CPID 2>/dev/null
            if grep -q "+CPIN: READY" /tmp/at_res.txt; then
                echo -e "${GREEN}[PASS]${NC}"
                modem_led_on; return 0
            fi
        fi

        echo -e "${RED}[FAILED]${NC}"
        echo -e "${YELLOW}>>> INSERT SIM. PRESS [ENTER] TO REBOOT MODEM & RETRY...${NC}"
        read p

        if [ -e "$MODEM_PORT" ]; then
            printf "AT+CFUN=1,1\r\n" > "$MODEM_PORT"
            sleep 10
        else
            test_4g_hw_reset > /dev/null 2>&1
        fi
    done
}

# 6. 4G Hardware Reset PIN Test (Silent execution to avoid kernel log overlap)
test_4g_hw_reset() {
    # Perform GPIO actions silently
    echo 1 > /sys/class/gpio/gpio$G_SHDN/value
    echo 0 > /sys/class/gpio/gpio$G_PWR_P/value
    sleep 1
    echo 0 > /sys/class/gpio/gpio$G_SHDN/value
    echo 1 > /sys/class/gpio/gpio$G_W_EN/value
    echo 0 > /sys/class/gpio/gpio$G_AWAKE/value
    echo 1 > /sys/class/gpio/gpio$G_PWR_P/value
    sleep 2
    echo 0 > /sys/class/gpio/gpio$G_PWR_P/value

    # Detection Loop
    timeout=30
    FOUND=1
    while [ $timeout -gt 0 ]; do
        if [ -e "$MODEM_PORT" ]; then
            FOUND=0
            break
        fi
        sleep 1
        timeout=$((timeout - 1))
    done

    if [ $FOUND -eq 0 ]; then
        # Extra settle time so PASS string appears after USB logs
        sleep 5 
        modem_led_on
        echo -e "Testing 4G Hardware Reset PIN: ${GREEN}[PASS]${NC}"
        return 0
    else
        echo -e "Testing 4G Hardware Reset PIN: ${RED}[FAILED]${NC}"
        return 1
    fi
}

# 7. Power Detection Test
test_power_detection() {
    while true; do
        echo -e "${BLUE}--- Power Detection Test (GPIO $PWR_REAL_GPIO) ---${NC}"
        echo in > /sys/class/gpio/gpio$PWR_REAL_GPIO/direction 2>/dev/null
        VAL=$(cat /sys/class/gpio/gpio$PWR_REAL_GPIO/value 2>/dev/null)
        if [ "$VAL" != "1" ]; then
            echo -e "Power Detect: ${RED}[FAILED]${NC} - Pin is LOW (0)."
            echo -e "${YELLOW}>>> CHECK POWER SUPPLY AND PRESS [ENTER] TO RETRY...${NC}"
            read p; continue
        fi
        echo -e "Status: ${GREEN}PLUGGED IN (1)${NC}"
        echo -e "${YELLOW}>>> PLEASE UN-PLUG POWER SUPPLY NOW...${NC}"
        T=20; F=0; while [ $T -gt 0 ]; do
            if [ "$(cat /sys/class/gpio/gpio$PWR_REAL_GPIO/value)" = "0" ]; then echo -e "Status: ${GREEN}UN-PLUGGED (0)${NC}"; F=1; break; fi
            sleep 1; T=$((T-1))
        done
        [ $F -eq 0 ] && echo -e "Power Detect: ${RED}[FAILED]${NC}" && return 1
        echo -e "${YELLOW}>>> PLEASE PLUG POWER SUPPLY BACK IN...${NC}"
        T=20; F=0; while [ $T -gt 0 ]; do
            if [ "$(cat /sys/class/gpio/gpio$PWR_REAL_GPIO/value)" = "1" ]; then echo -e "Status: ${GREEN}RE-PLUGGED (1)${NC}"; F=1; break; fi
            sleep 1; T=$((T-1))
        done
        [ $F -eq 0 ] && echo -e "Power Detect: ${RED}[FAILED]${NC}" && return 1
        echo -e "Power Detection: ${GREEN}[PASS]${NC}"; return 0
    done
}

# 9. Read MAC Address
read_mac() {
    echo -n "Ethernet MAC Address: "
    MAC=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/br-lan/address 2>/dev/null)
    if [ -n "$MAC" ]; then echo -e "${GREEN}$(echo "$MAC" | tr 'a-z' 'A-Z')${NC}"; return 0; fi
    echo -e "${RED}[FAILED]${NC}"
}

init_hardware() {
    for p in $G_SHDN $G_W_EN $G_AWAKE $G_PWR_P; do
        [ ! -d /sys/class/gpio/gpio$p ] && echo $p > /sys/class/gpio/export 2>/dev/null
        echo out > /sys/class/gpio/gpio$p/direction 2>/dev/null
    done
    [ ! -d /sys/class/gpio/gpio$PWR_REAL_GPIO ] && echo $PWR_REAL_GPIO > /sys/class/gpio/export 2>/dev/null
    echo in > /sys/class/gpio/gpio$PWR_REAL_GPIO/direction 2>/dev/null
    if which devmem > /dev/null; then
        VAL=$(devmem $REG_GPIO_MODE)
        NEW_VAL=$(printf "0x%x" $(( ($VAL & 0x7FFFFFE7) | 0x00008008 )))
        devmem $REG_GPIO_MODE 32 $NEW_VAL
    fi
}

print_header() {
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}       HARDWARE PRODUCTION TEST         ${NC}"
    echo -e "========================================${NC}"
}

run_all() {
    print_header
    echo -e "${BLUE}--- STARTING AUTOMATIC TEST ---${NC}"
    test_rtc
    test_sd
    test_lan
    test_leds
    test_4g
    #test_power_detection
    test_4g_hw_reset
    read_mac
    echo -e "${BLUE}--- ALL ITEMS COMPLETE ---${NC}"
}

# --- ENTRY ---
init_hardware
[ "$1" != "--skip" ] && run_all

while true; do
    echo -e "\n${YELLOW}----------------------------------------${NC}"
    echo -e " [1] Run All Tests      [6] Test 4G Reset PIN"
    echo -e " [2] Test RTC           [7] Test Power Detect"
    echo -e " [3] Test SD Card       [8] Test Board LEDs"
    echo -e " [4] Test LAN Ping      [9] Read MAC"
    echo -e " [5] Test 4G Modem      [r] SoC Reset  [q] Exit"
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo -n "Selection: "
    read opt
    case $opt in
        1) run_all ;;
        2) test_rtc ;;
        3) test_sd ;;
        4) test_lan ;;
        5) test_4g ;;
        6) test_4g_hw_reset ;;
        7) test_power_detection ;;
        8) test_leds ;;
        9) read_mac ;;
        r|R) echo 1 > /proc/sys/kernel/sysrq; usleep 100000; echo b > /proc/sysrq-trigger ;;
        q|Q) exit 0 ;;
    esac
done
