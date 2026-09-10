#!/bin/bash

set -e

ROBOT_HOST="root@omy-SNPR44B1011.local"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}=== Starting the OMY_f3m Robot${NC}"

echo -e "\n${GREEN}=1= PC: Launching camera nodes in the Open Manipulator docker${NC}\n"
cd ~/Code/robotis-omy/open_manipulator/docker
echo "Wrist camera should be a Realsense D405 with serialnr 230322274265"
echo "Top camera should be a Realsense D435 with serialnr 837212070319"
./container.sh start
docker exec -d open_manipulator /bin/bash -ic "\
source /opt/ros/jazzy/setup.bash && \
ros2 run rmw_zenoh_cpp rmw_zenohd & sleep 2 && \
ros2 launch realsense2_camera rs_multi_camera_launch.py \
	camera_name1:=cam_wrist \
	camera_namespace1:=camera1 \
	serial_no1:=\"'_230322274265'\" \
	depth_module.color_profile1:=640,480,30 \
	depth_module.depth_profile1:=640,480,30 \
	device_type1:=d4 \
	camera_name2:=cam_top \
	camera_namespace2:=camera2 \
	serial_no2:=\"'_837212070319'\" \
	depth_module.color_profile2:=640,480,30 \
	depth_module.depth_profile2:=640,480,30 \
	device_type2:=d4\
";

sleep 5

echo -e "\n${GREEN}=2= PC: Starting Physical AI docker ${NC}\n"
cd ~/Code/robotis-omy/physical_ai_tools/docker

./container.sh start


echo -e "\n${GREEN}=3= PC: Starting AI Server in the Physical AI docker${NC}\n"
docker exec -d physical_ai_server /bin/bash -ic "\
  source /opt/ros/jazzy/setup.bash && \
  source ~/ros2_ws/install/setup.bash && \
  ros2 launch physical_ai_server physical_ai_server_bringup.launch.py
";

sleep 5
echo -e "\n${GREEN}=4= Robot: Starting Open Manipulator docker ${NC}\n"
ssh "$ROBOT_HOST" "cd /data/docker/open_manipulator && ./docker/container.sh start"

echo -e "\n${GREEN}=5= Robot: Starting Teleop application${NC}\n"
ssh "$ROBOT_HOST" "docker exec -d open_manipulator /bin/bash -ic 'source /opt/ros/jazzy/setup.bash && ros2 launch open_manipulator_bringup omy_ai.launch.py'"

echo -e "${GREEN}=== Robotcel Startup complete ${NC}"
echo -e "${GREEN}=== WebUI available: http://localhost/${NC}"
echo -e "${GREEN}=== Debugging:       http://localhost:8080${NC}"
