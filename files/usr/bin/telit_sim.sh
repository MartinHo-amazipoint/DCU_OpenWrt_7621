#!/bin/sh

# --- CONFIGURATION ---
MODEM_PORT="/dev/ttyUSB2"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cleanup SIM storage on exit
cleanup() {
    echo -e "\n${YELLOW}Cleaning up SIM SMS test storage...${NC}"
    # Delete all messages in SIM storage (Index 1 to 4 is a safe broad clear)
    echo -e "AT+CMGD=1,4\r" > "$MODEM_PORT"
    [ -n "$READER_PID" ] && kill "$READER_PID" 2>/dev/null
    rm -f /tmp/sim_output.txt
    exit 0
}
trap cleanup INT TERM

echo -e "${YELLOW}--- 4G SIM R/W STABILITY TEST (SMS METHOD) ---${NC}"
echo -e "Press [Ctrl+C] to stop.\n"

if [ ! -e "$MODEM_PORT" ]; then
    echo -e "${RED}[FAILED]${NC} - Modem port not found."
    exit 1
fi

# 1. PRE-CHECK: Is SIM even detected?
echo -n "Checking SIM Detection (AT+CPIN?)... "
exec 3<>$MODEM_PORT
echo -e "AT+CPIN?\r" >&3
read -t 2 line1 <&3
read -t 2 res <&3
exec 3>&-

if echo "$res" | grep -q "READY"; then
    echo -e "${GREEN}READY${NC}"
else
    echo -e "${RED}[FAILED]${NC}"
    echo -e "Error: SIM not detected or PIN locked. Check tray/SIM card."
    exit 1
fi

# 2. INITIALIZATION
echo -n "Setting SIM as primary storage (AT+CPMS=\"SM\")... "
echo -e "AT+CMGF=1\r" > "$MODEM_PORT"  # Set to Text mode
sleep 1
echo -e "AT+CPMS=\"SM\",\"SM\",\"SM\"\r" > "$MODEM_PORT" # Target SIM card memory
sleep 1
echo -e "${GREEN}DONE${NC}\n"

PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}Starting Stability Loop. Testing physical SIM interface...${NC}"

# --- CONTINUOUS LOOP ---
while true; do
    # Create unique data string for this cycle
    TEST_STR="STB$(date +%M%S%N | cut -c 1-6)"
    
    # Start background reader
    rm -f /tmp/sim_output.txt
    cat "$MODEM_PORT" > /tmp/sim_output.txt &
    READER_PID=$!

    # A. WRITE to SIM Memory
    echo -e "AT+CMGW\r" > "$MODEM_PORT"
    usleep 200000
    echo -e "$TEST_STR\x1A" > "$MODEM_PORT" # Send unique text + Ctrl+Z
    
    sleep 2 # Wait for SIM flash write cycle (Hardware intensive)

    # B. Capture the Index returned by the modem (+CMGW: <index>)
    INDEX=$(grep "+CMGW:" /tmp/sim_output.txt | tail -n 1 | awk '{print $2}' | tr -d '\r')

    if [ -n "$INDEX" ]; then
        # C. READ back from SIM
        echo -e "AT+CMGR=$INDEX\r" > "$MODEM_PORT"
        sleep 1

        # D. VERIFY data integrity
        if grep -q "$TEST_STR" /tmp/sim_output.txt; then
            PASS_COUNT=$((PASS_COUNT + 1))
            echo -e "${GREEN}[PASS]${NC} Idx:$INDEX | Val:$TEST_STR | Total Pass:$PASS_COUNT"
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo -e "${RED}[FAIL]${NC} Data mismatch at Index $INDEX! (Total Fail:$FAIL_COUNT)"
        fi

        # E. DELETE message to keep SIM from filling up
        echo -e "AT+CMGD=$INDEX\r" > "$MODEM_PORT"
        usleep 200000
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo -e "${RED}[FAIL]${NC} Write Error (SIM dropped or power unstable?) | Total Fail:$FAIL_COUNT"
    fi

    # Stop reader for this cycle
    kill "$READER_PID" 2>/dev/null
    wait "$READER_PID" 2>/dev/null
    READER_PID=""

    sleep 1
done
