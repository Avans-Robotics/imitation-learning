#!/bin/bash

set -e

ROBOT_HOST="root@omy-SNPR44B1011.local"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}=== Shutting down the the OMY_f3m robot${NC}"

echo -e "\n${GREEN}=== Robot: Shutting down the base pc${NC}\n"
ssh "$ROBOT_HOST"  "shutdown now"

echo -e "${GREEN}=== Robot shutdown complete - you can now turn off the Robot power and PC${NC}"
