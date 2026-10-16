#!/bin/bash
# Moves the OMY follower back to the "ready" pose that the robot drives to when the teleop/inference
# application starts (joint_trajectory_executor, config/omy_f3m_follower_ai/initial_positions.yaml).
# Usage: ./reset_omy.sh [duration_s]   (default 10 s, same as at startup)

set -e

ROBOT_HOST="root@omy-SNPR44B1011.local"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

DURATION="${1:-10}"
JOINTS="[joint1, joint2, joint3, joint4, joint5, joint6, rh_r1_joint]"
READY="[0.0, -1.5708, 2.6529, -1.0821, 1.5708, 0.0, 0.0]"

GOAL="{trajectory: {joint_names: $JOINTS, points: [{positions: $READY, time_from_start: {sec: $DURATION}}]}}"

echo -e "${GREEN}=== Moving OMY follower to the ready pose in ${DURATION}s${NC}"

# The follower follows /leader/joint_trajectory in teleop and inference, a running leader or policy
# overrides this goal straight away
# (the physical_ai_server always has a publisher on it, so check for actual messages)
if ssh "$ROBOT_HOST" "docker exec open_manipulator bash -ic 'source /opt/ros/jazzy/setup.bash; timeout 2 ros2 topic echo --once /leader/joint_trajectory' 2>/dev/null" | grep -q joint_names; then
	echo -e "${YELLOW}Warning: commands are streaming on /leader/joint_trajectory (leader arm or running policy), the arm will be pulled back. Stop inference first${NC}"
fi

ssh "$ROBOT_HOST" "docker exec open_manipulator bash -ic \"source /opt/ros/jazzy/setup.bash; ros2 action send_goal /arm_controller/follow_joint_trajectory control_msgs/action/FollowJointTrajectory '$GOAL'\" 2>/dev/null" \
	| grep -E "accepted|rejected|status|error_code" || { echo -e "${RED}Failed to send the goal, is the robot application running?${NC}"; exit 1; }

echo -e "${GREEN}=== Done${NC}"
