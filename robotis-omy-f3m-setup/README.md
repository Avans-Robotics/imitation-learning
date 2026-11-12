# ROBOTIS-OMY-F3M setup

### For Teleop AI Training

This readme is created to help users of the ROBOTIS-OMY-F3M hardware from Avans Lectorate Robotisation and Sensoring to start training with the robot.

**Scripts, notes and the update runbook live in [Avans-Robotics/robotis-omy-f3m](https://github.com/Avans-Robotics/robotis-omy-f3m)**, the repo of `~/Code/robotis-omy` on the Jetson: the start/stop scripts, `UPDATE_PROCESS.md`, `CONTENT.md` (directory and network map), the process log and the policy results. This folder only keeps this setup guide.

Prerequisites:

* ROBOTIS OMY-F3M with cables
* 2 USB-A tot USB-C ***data*** cables no longer than 2 meters for connection to the camera
* A host PC or laptop with linux with docker installed and persmissions to use host hardware

Resources
https://ai.robotis.com/omy/dataset_preparation_prerequisites_omy.html


**TLDR;**

- Give power to Robot and leader arm
- Turn on Robot base computer
***Automatic***:
To start the system, run the start_omy_teleop script from [robotis-omy-f3m](https://github.com/Avans-Robotics/robotis-omy-f3m) (start_omy_inference to run a trained policy) and point the browser of the PC to `http://localhost`:
`./start_omy_teleop.sh`
To stop the system, run the stop_omy script
`./stop_omy.sh'

***Manual***:
- Run the docker on the robot base
  - SSH into robot base and run the open_manipulator docker (usually `ssh root@192.168.0.145`)
  - `ros2 launch open_manipulator_bringup unpack.launch.py`
  - `ros2 launch open_manipulator_bringup omy_ai.launch.py`
- Run the zenoh router process
- Run the camera stream from the open manipulator dir (`ros2 launch realsense2_camera rs_multi_camera_launch.py [camera parameters]`
- Run the AI server from the physical ai tools dir (`ai_server`)
- Use a huggingface account to create link for policy training
- Start data collection for a policy
- Train the policy
- Do inference

***Turn OFF the System***


## Detailed setup

#### **Hardware setup**

- Give power to the following devices
  
  - the Linksys switch and the Follower Robot and your laptop are connected
  - Follower arm adapter
  - Leader arm adapter and make sure the jack barrel is connecter to the board underneith and turn on the button
- Make sure the leader arm is connected to the follower robot (USB-A) and to the leader robot (USB-C)
- Turn on the robot by pushing in the button for 2 second until the bright white led light turns on
- Wait for 20 secs
- Connect the 2 camera's to the training laptop (use the "camera_only" port on the robot for the gripper cam)

#### **Prepare Robot Computer**

- Use SSH to log into the Follower robot (usually `ssh root@192.168.1.145`)
- go to the following dir: `cd /data/docker/open_manipulator`
- Start the container
  `./docker/container.sh start`
- The last line of the result should be " ✔ Container open_manipulator  Running/Started"
- Enter the container
  `./docker/container.sh enter`
- DEACTIVATE THE EMERGENCY BUTTON (E-button)
- Always be mindful of dangerous situations and keep the E-button close to you and use if needed!
- in the docker run:
  `ros2 launch open_manipulator_bringup omy_3m_unpack.launch.py`
- The robot should now unpack into standing position, if not check if you have plugged all needed cables in and released the E-button
- Run the AI manipulation bringup:
  `ros2 launch open_manipulator_bringup omy_ai.launch.py`
- You should now be able to do teleoperation on the robot
- Leave the terminal running

#### **Prepare Training PC/Laptop**

**Open Manipulator - Camera stream publishing**

- Download open manipulator tools:
  `git clone --recurse-submodules https://github.com/ROBOTIS-GIT/open_manipulator.git`
- Navigate into the open manipulator tools dir
- Start the container
- ```
  cd open_manipulator/docker &&
  ./container.sh start &&
  ./container.sh enter
  ```
- In the container, run the zenoh router process
- ```
    source /opt/ros/jazzy/setup.bash && \
    ros2 run rmw_zenoh_cpp rmw_zenohd &
    ```
- In the container, check the serial numbers of the 1 or multiple realsense devices you want to use
  `realsense-viewer`
- Write down the serial numbers and run the command to expose the camera's to the ros2 middleware
- In the container run the following command (adjust serial numbers and camera types from the example):
  
  ```
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
	    
	ros2 launch realsense2_camera rs_launch.py \
	ros2 launch realsense2_camera rs_launch.py \
		camera_name:=cam_side \
		camera_namespace:=camera3 \
		serial_no:=\"'_826212070339'\" \
		depth_module.color_profile:=640,480,30 \
		rgb_camera.color_profile:=640,480,30 \
		depth_module.depth_profile:=640,480,30 \
		device_type:=d4\
  ```
- Keep the terminal running



**Physical AI tools - AI Server data acquisition, training and testing**

- Download physical AI tools:

  `git clone --recurse-submodules https://github.com/ROBOTIS-GIT/physical_ai_tools.git`

- Navigate into the physical ai tools dir and start the container
  
  ```
  cd open_manipulator/docker &&
  ./container.sh start
  ```
- Enter the container
  `./container.sh enter`
- In the container run the following command:
  `ros2 launch physical_ai_server physical_ai_server_bringup.launch.py`
- or use the symbolic link:
  `ai_server`
- If you change camera setup, adjust the configuration in the physical_ai_server docker to match the steam coming from the open manipulator:
- In the physical_ai_server docker change this file to match your config: `/root/ros2_ws/src/physical_ai_tools/physical_ai_server/config/omy_f3m_config.yaml`
- Run a web browser on your local host and use `http://localhost` as url
- Use the Webpage as explained on the Robotis site

---


omy_f3m_config.yaml example config snippet:

[...]
      observation_list:
        - cam_wrist
        - cam_top
        - cam_side
        - state

      camera_topic_list:
        - cam_wrist:/camera1/cam_wrist/color/image_rect_raw/compressed
        - cam_top:/camera2/cam_top/color/image_raw/compressed
        - cam_side:/camera3/cam_side/color/image_raw/compressed

[...]

---



Realsense D405 (Omy)
230322274265

Realsense D435 known camera serialnumbers:
826212070339
837212070319


Example launch command (multi camera only has max 2 camera's):

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
	    depth_module.color_profile1:=640,480,30 \
	    depth_module.depth_profile1:=640,480,30 \
	    device_type2:=d4\
	
	ros2 launch realsense2_camera rs_launch.py \
		camera_name:=cam_side \
		camera_namespace:=camera3 \
		serial_no:=\"'_826212070339'\" \
		depth_module.color_profile:=640,480,30 \
		depth_module.depth_profile:=640,480,30 \
		device_type:=d4\


