#!/bin/sh

# --- CONFIGURATION ---
MODEM_PORT="/dev/ttyUSB2"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cleanup() {
    echo -e "\n${YELLOW}Turning off GPS hardware to save power...${NC}"
    echo -e "AT\$GPSP=0\r" > "$MODEM_PORT"
    [ -n "$READER_PID" ] && kill "$READER_PID" 2>/dev/null
    rm -f /tmp/gps_output.txt
    exit 0
}
trap cleanup INT TERM

echo -e "${YELLOW}--- 4G MODEM GPS TEST ---${NC}"

if [ ! -e "$MODEM_PORT" ]; then
    echo -e "${RED}[FAILED]${NC} - Modem port not found."
    exit 1
fi

# 1. Enable GPS Power and VERIFY response
echo -n "Powering on GPS Hardware (AT\$GPSP=1)... "

# Start a quick background reader to check for "OK"
rm -f /tmp/gps_init.txt
cat "$MODEM_PORT" > /tmp/gps_init.txt &
INIT_PID=$!
echo -e "AT\$GPSP=1\r" > "$MODEM_PORT"
sleep 2
kill $INIT_PID 2>/dev/null

if grep -q "OK" /tmp/gps_init.txt; then
    echo -e "${GREEN}SUCCESS${NC}"
    echo -e "${BLUE}The GPS engine is now searching for satellites (Cold Start).${NC}"
    echo -e "${BLUE}Note: This usually takes 1-3 minutes and requires outdoor sky view.${NC}"
    echo -e "Press [Ctrl+C] to stop testing.\n"
else
    echo -e "${RED}FAILED${NC}"
    echo -e "The modem did not respond with OK. Is the module initialized?"
    exit 1
fi

# 2. Continuous Polling Loop for Satellite Fix
while true; do
    rm -f /tmp/gps_output.txt
    cat "$MODEM_PORT" > /tmp/gps_output.txt &
    READER_PID=$!

    # AT$GPSACP: Get Acquired Position
    echo -e "AT\$GPSACP\r" > "$MODEM_PORT"
    sleep 2

    kill "$READER_PID" 2>/dev/null
    wait "$READER_PID" 2>/dev/null
    READER_PID=""

    if grep -q "\$GPSACP:" /tmp/gps_output.txt; then
        RAW_DATA=$(grep "\$GPSACP:" /tmp/gps_output.txt | tail -n 1 | tr -d '\r')
        
        # Check the 6th field for Fix Type (0=No Fix, 2=2D, 3=3D)
        FIX_TYPE=$(echo "$RAW_DATA" | cut -d',' -f6)
        
        if [ "$FIX_TYPE" = "0" ] || [ -z "$FIX_TYPE" ]; then
            # No fix yet, show status
            echo -e "${YELLOW}Searching...${NC} No fix yet. (Satellites in view: $(echo "$RAW_DATA" | cut -d',' -f11))"
        else
            # We have a location!
            echo -e "${GREEN}FIX ACQUIRED!${NC} (Type: ${FIX_TYPE}D | Data: $RAW_DATA)"
        fi
    else
        echo -e "${RED}Error: Modem not responding to poll command.${NC}"
    fi

    sleep 1
done
