#!/bin/sh

echo "Amazipoint Start Init Script"
echo "uci set wireless.radio0.disabled=0"
uci set wireless.radio0.disabled="0"
echo "set wireless.default_radio0.ifname=ra0"
uci set wireless.default_radio0.ifname='ra0'
echo "uci commit wireless"
uci commit wireless
echo "Amazipoint Ended Init Script"
