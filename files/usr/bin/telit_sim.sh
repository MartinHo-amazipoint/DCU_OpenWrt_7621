#!/bin/sh

MODEM_PORT="/dev/ttyACM2"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    echo -e "\n${YELLOW}Cleaning up SIM...${NC}"
    printf "AT+CMGD=1,4\r\n" > "$MODEM_PORT"
    [ -n "$READER_PID" ] && kill "$READER_PID" 2>/dev/null
    exit 0
}
trap cleanup INT TERM

# Initialize Serial Port Hardware State
stty -F $MODEM_PORT 115200 raw -echo

echo -e "${YELLOW}--- 4G SIM R/W STABILITY TEST ---${NC}"

# 1. PRE-CHECK
printf "AT+CPIN?\r\n" > "$MODEM_PORT"
sleep 1

# 2. INITIALIZATION & CLEAR STORAGE
echo -n "Preparing SIM Storage (Clearing old SMS)... "
printf "AT+CMGF=1\r\n" > "$MODEM_PORT"
sleep 1
printf "AT+CPMS=\"SM\",\"SM\",\"SM\"\r\n" > "$MODEM_PORT"
sleep 1
# Delete ALL existing messages on SIM to prevent "Memory Full" errors
printf "AT+CMGD=1,4\r\n" > "$MODEM_PORT"
sleep 2
echo -e "${GREEN}DONE${NC}\n"

PASS_COUNT=0
FAIL_COUNT=0

while true; do
    TEST_STR="TEST$(date +%M%S)"
    rm -f /tmp/sim_output.txt
    cat "$MODEM_PORT" > /tmp/sim_output.txt &
    READER_PID=$!

    # WRITE: Send command, wait for prompt, then send string
    printf "AT+CMGW\r\n" > "$MODEM_PORT"
    usleep 300000
    printf "$TEST_STR\x1A" > "$MODEM_PORT"
    sleep 3 # Increased wait for SIM Flash write

    # Check for Index
    INDEX=$(grep "+CMGW:" /tmp/sim_output.txt | tail -n 1 | awk '{print $2}' | tr -d '\r')

    if [ -n "$INDEX" ]; then
        # READ
        printf "AT+CMGR=$INDEX\r\n" > "$MODEM_PORT"
        sleep 1
        if grep -q "$TEST_STR" /tmp/sim_output.txt; then
            PASS_COUNT=$((PASS_COUNT + 1))
            echo -e "${GREEN}[PASS] Idx:$INDEX Val:$TEST_STR (Total: $PASS_COUNT)${NC}"
        else
            echo -e "${RED}[FAIL] Data Mismatch${NC}"
        fi
        # DELETE
        printf "AT+CMGD=$INDEX\r\n" > "$MODEM_PORT"
        usleep 200000
    else
        echo -e "${RED}[FAIL] Write Error - No Index Received${NC}"
        echo "Modem Output: $(cat /tmp/sim_output.txt | tr '\r\n' ' ')"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        # If multiple fails, try clearing storage again
        if [ $((FAIL_COUNT % 3)) -eq 0 ]; then
             printf "AT+CMGD=1,4\r\n" > "$MODEM_PORT"
             sleep 1
        fi
    fi

    kill "$READER_PID" 2>/dev/null
    wait "$READER_PID" 2>/dev/null
    sleep 1
done
