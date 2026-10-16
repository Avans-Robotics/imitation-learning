#!/bin/bash

set -e

ROBOT_HOST="root@omy-SNPR44B1011.local"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# The PC images (physical-ai-server 1.0.0, open-manipulator latest) default to rmw_zenoh in ~/.bashrc,
# the robot SBC image only has FastRTPS. Force FastRTPS so all three can see each other.
FORCE_FASTRTPS='sed -i "s/^#\?export RMW_IMPLEMENTATION=.*/export RMW_IMPLEMENTATION=rmw_fastrtps_cpp/" /root/.bashrc'

echo -e "${GREEN}=== Starting the OMY_f3m Robot (inference)${NC}"

echo -e "\n${GREEN}=1= PC: Launching camera nodes in the Open Manipulator docker${NC}\n"
cd ~/Code/robotis-omy/open_manipulator/docker
echo "Wrist camera should be a Realsense D405 with serialnr 230322274265"
echo "Top camera should be a Realsense D435 with serialnr 837212070319"
echo "Side camera should be a Realsense D435 with serialnr 826212070339"
./container.sh start
docker exec open_manipulator bash -c "$FORCE_FASTRTPS"

if docker exec open_manipulator pgrep -f "realsense2_camera_node" > /dev/null; then
	echo -e "${YELLOW}Camera nodes already running, not starting them again${NC}"
else
	# rs_multi_camera_launch.py only supports 2 cameras, the side camera gets its own rs_launch.py
	# D405 color comes from the depth module (depth_module.color_profile), D435 color from the RGB sensor
	# (rgb_camera.color_profile). Without it a D435 on USB 2.0 falls back to 15 fps.
	docker exec -d open_manipulator /bin/bash -ic "\
	source /opt/ros/jazzy/setup.bash && \
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
		rgb_camera.color_profile2:=640,480,30 \
		depth_module.depth_profile2:=640,480,30 \
		device_type2:=d4\
	";
	sleep 3
	docker exec -d open_manipulator /bin/bash -ic "\
	source /opt/ros/jazzy/setup.bash && \
	ros2 launch realsense2_camera rs_launch.py \
		camera_name:=cam_side \
		camera_namespace:=camera3 \
		serial_no:=\"'_826212070339'\" \
		depth_module.color_profile:=640,480,30 \
		rgb_camera.color_profile:=640,480,30 \
		depth_module.depth_profile:=640,480,30 \
		device_type:=d4\
	";
fi

sleep 5

echo -e "\n${GREEN}=2= PC: Starting Physical AI docker ${NC}\n"
cd ~/Code/robotis-omy/physical_ai_tools/docker

./container.sh start
docker exec physical_ai_server bash -c "$FORCE_FASTRTPS"
# The image puts the bundled CUDA 12.8 compat libcuda first in LD_LIBRARY_PATH, which breaks CUDA on
# this JetPack 7 Orin. Strip it in ~/.bashrc (see fix_physical_ai_cuda.sh, also needed for the torch upgrade)
docker exec physical_ai_server bash -c 'grep -q "cuda/compat fix" /root/.bashrc || echo "export LD_LIBRARY_PATH=\${LD_LIBRARY_PATH//\/usr\/local\/cuda\/compat:/}  # cuda/compat fix: drop bundled CUDA 12.8 compat libcuda, use host Orin driver" >> /root/.bashrc'


echo -e "\n${GREEN}=3= PC: Starting AI Server in the Physical AI docker${NC}\n"
if docker exec physical_ai_server pgrep -f "physical_ai_server_bringup" > /dev/null; then
	echo -e "${YELLOW}AI Server already running, not starting it again${NC}"
else
	docker exec -d physical_ai_server /bin/bash -ic "\
	  source /opt/ros/jazzy/setup.bash && \
	  source ~/ros2_ws/install/setup.bash && \
	  ros2 launch physical_ai_server physical_ai_server_bringup.launch.py
	";
fi

sleep 5
echo -e "\n${GREEN}=4= Robot: Starting Open Manipulator docker ${NC}\n"
# Start the existing container as-is: no compose, no pull (the robot has no internet, see UPDATE_PROCESS.md)
ssh "$ROBOT_HOST" "docker start open_manipulator"

echo -e "\n${GREEN}=5= Robot: Starting follower application${NC}\n"
# The robot container runs with pid=host, so pgrep also sees this ssh command's own command line;
# the [o]/[r] keep the patterns from matching themselves, the ros2_control_node pattern is anchored to the
# executable path because the remote sh -c (incl. its error message) also contains that name.
# omy_ai.launch.py (start_omy.sh) also runs the leader arm, which would fight the policy: stop it
if ssh "$ROBOT_HOST" "docker exec open_manipulator pgrep -f '[o]my_ai.launch.py'" > /dev/null; then
	echo -e "${YELLOW}Teleop application is running, stopping it first (the arm loses torque control)${NC}"
	ssh "$ROBOT_HOST" "docker exec open_manipulator pkill -INT -f '[r]os2 launch open_manipulator_bringup'; \
		for i in \$(seq 15); do docker exec open_manipulator pgrep -f '^/[^ ]*/ros2_control_node' > /dev/null || exit 0; sleep 1; done; \
		echo 'ros2_control_node did not stop within 15 s'; exit 1"
fi

if ssh "$ROBOT_HOST" "docker exec open_manipulator pgrep -f '[r]os2 launch open_manipulator_bringup'" > /dev/null; then
	echo -e "${YELLOW}Inference application already running, not starting it again (run stop_omy.sh first for a clean start)${NC}"
else
	ssh "$ROBOT_HOST" "docker exec -d open_manipulator /bin/bash -ic 'source /opt/ros/jazzy/setup.bash && ros2 launch open_manipulator_bringup omy_f3m_follower_ai.launch.py ros2_control_type:=omy_f3m_smooth'"
fi

echo -e "${GREEN}=== Robotcel Startup complete ${NC}"
echo -e "${GREEN}=== WebUI available: http://localhost/${NC}"
echo -e "${GREEN}=== Debugging:       http://localhost:8080${NC}"
