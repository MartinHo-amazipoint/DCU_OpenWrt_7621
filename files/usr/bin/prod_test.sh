#!/bin/sh

# --- CONFIGURATION ---
TEST_IP="192.168.1.2"
MODEM_PORT="/dev/ttyUSB2"
GPIO_BASE="480"

# Pins based on your hardware check
MODEM_RESET_PIN="19"  # Modem Emergency Reset (Section 6.3.4)
PWR_DET_PIN="5"       # Power Loss Detect (RTS3_N)

MODEM_REAL_GPIO=$((GPIO_BASE + MODEM_RESET_PIN)) # 499
PWR_REAL_GPIO=$((GPIO_BASE + PWR_DET_PIN))      # 485
# ---------------------

# Color Codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to force UART3_MODE [4:3] into GPIO Mode (01)
setup_pinmux() {
    # Based on your mapping: bits 4:3. 01 = GPIO.
    # Current 0x84A8 has bit 4=0, bit 3=1 -> Already 01 (GPIO)
    if which devmem > /dev/null; then
        CURRENT=$(devmem 0x1e000060)
        # Clear bits 4:3 (AND with E7) and set to 01 (OR with 08)
        NEW_VAL=$(printf "0x%x" $(( ($CURRENT & 0xFFFFFFE7) | 0x00000008 )))
        if [ "$CURRENT" != "$NEW_VAL" ]; then
            devmem 0x1e000060 32 $NEW_VAL
        fi
    fi
}

print_header() {
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}       HARDWARE PRODUCTION TEST         ${NC}"
    echo -e "${YELLOW}========================================${NC}"
}

test_rtc() {
    echo -n "Testing RTC (BQ32002): "
    [ ! -e /dev/rtc0 ] && echo -e "${RED}[FAILED]${NC}" && return 1
    RTC_VAL=$(hwclock -r 2>/dev/null)
    [ $? -eq 0 ] && echo -e "${GREEN}[PASS]${NC} ($RTC_VAL)" || echo -e "${RED}[FAILED]${NC}"
}

test_sd() {
    while true; do
        echo -n "Testing Micro SD Card: "
        KLEVEL=$(cat /proc/sys/kernel/printk | cut -f1)
        echo 1 > /proc/sys/kernel/printk 
        PASSED=1
        if [ -e /dev/mmcblk0 ]; then
            DEV="/dev/mmcblk0"; [ -e "/dev/mmcblk0p1" ] && DEV="/dev/mmcblk0p1"
            MNT="/tmp/sd_test_mnt"; mkdir -p $MNT; umount $MNT >/dev/null 2>&1
            if mount $DEV $MNT >/dev/null 2>&1; then
                echo "test" > "$MNT/test.tmp" 2>/dev/null && rm "$MNT/test.tmp" && umount $MNT && PASSED=0
            fi
        fi
        echo "$KLEVEL" > /proc/sys/kernel/printk
        [ $PASSED -eq 0 ] && echo -e "${GREEN}[PASS]${NC}" && return 0
        echo -e "${RED}[FAILED]${NC}"
        echo -e "${YELLOW}>>> INSERT SD CARD AND PRESS [ENTER] TO RETRY...${NC}"
        read pause_key
    done
}

test_lan() {
    echo -n "Testing LAN Ping ($TEST_IP): "
    ping -c 2 -W 2 $TEST_IP > /dev/null 2>&1 && echo -e "${GREEN}[PASS]${NC}" || echo -e "${RED}[FAILED]${NC}"
}

test_4g() {
    while true; do
        echo -n "Testing 4G Modem & SIM: "
        if [ -e "$MODEM_PORT" ]; then
            exec 3<>$MODEM_PORT; echo -e "AT+CPIN?\r" >&3
            read -t 2 l1 <&3; read -t 2 res <&3; exec 3>&-
            if echo "$res" | grep -q "READY"; then
                echo -e "${GREEN}[PASS]${NC}"; return 0
            fi
        fi
        echo -e "${RED}[FAILED]${NC}"
        echo -e "${YELLOW}>>> INSERT SIM AND PRESS [ENTER] TO RESET MODEM...${NC}"
        read pause_key
        if [ -e "$MODEM_PORT" ]; then
            echo -e "AT+CFUN=1,1\r" > "$MODEM_PORT"
            i=0; while [ $i -lt 12 ]; do echo -n "."; sleep 1; i=$((i+1)); done; echo ""
        fi
    done
}

test_4g_hw_reset() {
    echo -n "Testing 4G HW Emergency Reset (GPIO $MODEM_REAL_GPIO): "
    if [ ! -e "$MODEM_PORT" ]; then
        echo -e "${RED}[FAILED]${NC} - No Modem"
        return 1
    fi
    [ ! -d /sys/class/gpio/gpio$MODEM_REAL_GPIO ] && echo $MODEM_REAL_GPIO > /sys/class/gpio/export
    echo out > /sys/class/gpio/gpio$MODEM_REAL_GPIO/direction
    echo 0 > /sys/class/gpio/gpio$MODEM_REAL_GPIO/value 
    usleep 300000
    echo 1 > /sys/class/gpio/gpio$MODEM_REAL_GPIO/value
    sleep 2
    [ -e "$MODEM_PORT" ] && echo -e "${RED}[FAILED]${NC} - Modem did not reset" && return 1
    timeout=30; while [ $timeout -gt 0 ]; do
        [ -e "$MODEM_PORT" ] && echo -e "${GREEN}[PASS]${NC}" && return 0
        sleep 1; timeout=$((timeout - 1))
    done
    echo -e "${RED}[FAILED]${NC} - Timeout" && return 1
}

test_power_detection() {
    echo -e "${BLUE}--- Power Detection Test (GPIO $PWR_REAL_GPIO) ---${NC}"
    setup_pinmux
    if [ ! -d /sys/class/gpio/gpio$PWR_REAL_GPIO ]; then
        echo $PWR_REAL_GPIO > /sys/class/gpio/export 2>/dev/null
    fi
    echo in > /sys/class/gpio/gpio$PWR_REAL_GPIO/direction

    VAL=$(cat /sys/class/gpio/gpio$PWR_REAL_GPIO/value)
    if [ "$VAL" != "1" ]; then
        echo -e "Power Detect: ${RED}[FAILED]${NC} - Start with Plugged in."
        return 1
    fi
    echo -e "Status: ${GREEN}PLUGGED IN (1)${NC}"

    echo -e "${YELLOW}>>> PLEASE UN-PLUG POWER SUPPLY NOW...${NC}"
    T=20; F=0; while [ $T -gt 0 ]; do
        if [ "$(cat /sys/class/gpio/gpio$PWR_REAL_GPIO/value)" = "0" ]; then
            echo -e "Status: ${GREEN}UN-PLUGGED (0)${NC}"; F=1; break
        fi
        sleep 1; T=$((T-1))
    done
    [ $F -eq 0 ] && echo -e "Power Detect: ${RED}[FAILED]${NC}" && return 1

    echo -e "${YELLOW}>>> PLEASE PLUG POWER SUPPLY BACK IN...${NC}"
    T=20; F=0; while [ $T -gt 0 ]; do
        if [ "$(cat /sys/class/gpio/gpio$PWR_REAL_GPIO/value)" = "1" ]; then
            echo -e "Status: ${GREEN}RE-PLUGGED (1)${NC}"; F=1; break
        fi
        sleep 1; T=$((T-1))
    done
    [ $F -eq 0 ] && echo -e "Power Detect: ${RED}[FAILED]${NC}" && return 1

    echo -e "Power Detection: ${GREEN}[PASS]${NC}"
    return 0
}

read_mac() {
    echo -n "Ethernet MAC Address: "
    MAC=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/br-lan/address 2>/dev/null)
    [ -n "$MAC" ] && echo -e "${GREEN}$(echo "$MAC" | tr 'a-z' 'A-Z')${NC}" || echo -e "${RED}[FAILED]${NC}"
}

test_wdt() {
    echo -e "\n${BLUE}!!! TRIGGERING SoC HARDWARE RESET !!!${NC}"
    echo 1 > /proc/sys/kernel/sysrq; usleep 100000; echo b > /proc/sysrq-trigger
}

run_all() {
    print_header
    echo -e "${BLUE}--- STARTING AUTOMATIC TEST ---${NC}"
    test_rtc
    test_lan
    test_sd
    test_power_detection
    read_mac
    echo -e "${BLUE}--- ALL ITEMS COMPLETE ---${NC}"
}

# --- MAIN LOGIC ---
if [ "$1" != "--skip" ]; then
    run_all
fi

while true; do
    echo -e "\n${YELLOW}----------------------------------------${NC}"
    echo -e " [1] Run All Tests      [6] Test 4G Reset PIN"
    echo -e " [2] Test RTC           [7] Test Power Detect"
    echo -e " [3] Test SD Card       [8] Read MAC"
    echo -e " [4] Test LAN Ping      [r] SoC Reset"
    echo -e " [5] Test 4G Modem      [q] Exit"
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
        8) read_mac ;;
        r|R) test_wdt ;;
        q|Q) exit 0 ;;
    esac
done
