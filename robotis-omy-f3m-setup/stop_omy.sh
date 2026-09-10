#!/bin/bash

set -e

ROBOT_HOST="root@omy-SNPR44B1011.local"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}=== Stopping the the OMY_f3m robot application${NC}"

echo -e "\n${GREEN}=1= Robot: Stopping robot docker${NC}\n"
ssh "$ROBOT_HOST"  "docker container stop open_manipulator"

echo -e "\n${GREEN}=2= PC: Stopping open manipulator and physical AI dockers${NC}\n"
docker container stop open_manipulator physical_ai_server physical_ai_manager

echo -e "${GREEN}=== Robot application stopped${NC}"
