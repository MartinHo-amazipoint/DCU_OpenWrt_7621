#!/bin/sh

# --- CONFIGURATION ---
MODEM_PORT="/dev/ttyUSB2"
HOST="8.8.8.8"
PDP_ID=1
APN=${1:-"internet"}  # Default to 'internet' if no arg provided

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cleanup background processes on exit
cleanup() {
    echo -e "\n${YELLOW}Stopping Ping Test...${NC}"
    [ -n "$READER_PID" ] && kill "$READER_PID" 2>/dev/null
    rm -f /tmp/ping_output.txt
    exit 0
}
trap cleanup INT TERM

echo -e "${YELLOW}--- 4G LTE CONTINUOUS PING TEST ---${NC}"
echo -e "Target: $HOST | APN: $APN | PDP ID: $PDP_ID"
echo -e "Press [Ctrl+C] to stop.\n"

if [ ! -e "$MODEM_PORT" ]; then
    echo -e "${RED}[FAILED]${NC} - Modem port not found."
    exit 1
fi

# --- INITIALIZATION ---
echo -n "Initializing Context $PDP_ID... "
# Set APN
echo -e "AT+CGDCONT=$PDP_ID,\"IP\",\"$APN\"\r" > "$MODEM_PORT"
sleep 1
# Activate internal data session
echo -e "AT#SGACT=$PDP_ID,1\r" > "$MODEM_PORT"
sleep 2
echo -e "${GREEN}DONE${NC}\n"

# --- CONTINUOUS LOOP ---
while true; do
    # Start background reader to capture modem output
    rm -f /tmp/ping_output.txt
    cat "$MODEM_PORT" > /tmp/ping_output.txt &
    READER_PID=$!

    # AT#PING=<addr>,<retry>,<len>,<timeout_deciseconds>,<ttl>,<pdpId>
    # timeout=30 means 3.0 seconds
    echo -e "AT#PING=\"$HOST\",1,32,30,64,$PDP_ID\r" > "$MODEM_PORT"

    # Wait for response (must be longer than modem timeout)
    sleep 4

    # Stop reader
    kill "$READER_PID" 2>/dev/null
    wait "$READER_PID" 2>/dev/null
    READER_PID=""

    # Evaluate Result
    if grep -q "#PING:" /tmp/ping_output.txt; then
        RESULT=$(grep "#PING:" /tmp/ping_output.txt | tail -n 1 | tr -d '\r')
        echo -e "${GREEN}$RESULT${NC}"
    else
        echo -e "${RED}Request Timeout or Network Error${NC}"
    fi

    sleep 1
done
