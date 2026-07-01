#!/bin/sh

# --- CONFIGURATION ---
MODEM_PORT="/dev/ttyACM2"
HOST="8.8.8.8"
PDP_ID=1
APN=${1:-"internet"}

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    echo -e "\n${YELLOW}Stopping Ping Test...${NC}"
    [ -n "$READER_PID" ] && kill "$READER_PID" 2>/dev/null
    exit 0
}
trap cleanup INT TERM

# Initialize Serial Port (Force raw mode to prevent screen scrambling)
stty -F $MODEM_PORT 115200 raw -echo

echo -e "${YELLOW}--- 4G LTE STABLE PING TEST (RELIABLE MODE) ---${NC}"

init_context() {
    echo -e "${YELLOW}Initializing Network Session...${NC}"
    printf "AT+CGDCONT=$PDP_ID,\"IP\",\"$APN\"\r\n" > "$MODEM_PORT"
    sleep 1
    printf "AT#SGACT=$PDP_ID,1\r\n" > "$MODEM_PORT"
    sleep 3
    
    # Check IP
    rm -f /tmp/ip_check.txt
    cat "$MODEM_PORT" > /tmp/ip_check.txt &
    CPID=$!
    printf "AT+CGPADDR=$PDP_ID\r\n" > "$MODEM_PORT"
    sleep 1
    kill $CPID 2>/dev/null
    IP_VAL=$(grep "+CGPADDR:" /tmp/ip_check.txt | awk '{print $2}' | tr -d '\r\n"')
    
    if [ -n "$IP_VAL" ] && [ "$IP_VAL" != "0.0.0.0" ]; then
        echo -e "Context $PDP_ID Active. IP: ${GREEN}$IP_VAL${NC}"
        return 0
    else
        echo -e "${RED}Context Active but NO IP assigned.${NC}"
        return 1
    fi
}

init_context
echo -e "Starting Loop. Press [Ctrl+C] to stop.\n"

while true; do
    for i in 1 2 3 4; do
        rm -f /tmp/ping_output.txt
        cat "$MODEM_PORT" > /tmp/ping_output.txt &
        READER_PID=$!

        # AT#PING=<addr>,<retry>,<len>,<timeout_deciseconds>,<ttl>,<pdpId>
        # timeout=100 (10 seconds)
        printf "AT#PING=\"$HOST\",1,32,100,64,$PDP_ID\r\n" > "$MODEM_PORT"
        
        # Match your verified stable timing
        sleep 10

        kill "$READER_PID" 2>/dev/null
        wait "$READER_PID" 2>/dev/null
        READER_PID=""

        # Clean the output (Remove Carriage Returns \r)
        RESULT=$(grep "#PING:" /tmp/ping_output.txt | tail -n 1 | tr -d '\r\n')

        # Logic: Status 1 is the ONLY success code
        if echo "$RESULT" | grep -q ",1,"; then
             echo -e "[#$i] ${GREEN}$RESULT${NC}"
        elif echo "$RESULT" | grep -q ",0,"; then
             echo -e "[#$i] ${RED}TIMEOUT: $RESULT${NC}"
        elif echo "$RESULT" | grep -q ",2,"; then
             echo -e "[#$i] ${RED}ERROR (Unreachable): $RESULT${NC}"
        else
             echo -e "[#$i] ${RED}MODEM ERROR or NO RESPONSE${NC}"
        fi
        
        # Use usleep for sub-second delay between pings
        usleep 500000
    done

    echo "----------------------------------------"
    sleep 2
done
