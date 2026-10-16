# OMY robot cell – update process

How to move the robot SBC and this PC (Jetson AGX Orin) to the newest ROBOTIS releases, and how to roll back.
Written 2026-10-16. Ask Claude: *"update the OMY setup to the latest release, follow UPDATE_PROCESS.md"*.

---

## 1. Current state (baseline, 2026-10-16)

| Where | Container | Image (pinned in compose) | Digest (Docker Hub) | GitHub release | RMW |
|---|---|---|---|---|---|
| Robot SBC `root@omy-SNPR44B1011.local` (192.168.1.145) | `open_manipulator` | `robotis/open-manipulator:4.1.0` | `sha256:5b88a23f7883b074861793ea2e3f960c74c27eba1386155e7a6c416ab4727973` | open_manipulator 4.1.0 (`87d57b6`) | FastRTPS (image has no zenoh) |
| PC (192.168.1.107) | `open_manipulator` (cameras only) | `robotis/open-manipulator:5.1.1` | `sha256:1b4a5200cba6d870b14c43adf88c8706cee5f11ccf7991c9a91d96613ae676ca` | 5.1.1 image, but the **4.1.4** checkout is mounted over `src/open_manipulator` | forced FastRTPS |
| PC | `physical_ai_server` | `robotis/physical-ai-server:1.0.0` | `sha256:fd1a79000ed34428426183d91cc018c2d38869d4ea4eac4879a3634716e5309d` | physical_ai_tools 1.0.0 (`27192da` checkout mounted) | forced FastRTPS |
| PC | `physical_ai_manager` | `robotis/physical-ai-manager:1.0.0` | – | 1.0.0 | – |

Notes:
- The image tag `latest` is meaningless locally; always use explicit version tags. Image versions = GitHub release tags
  (images are built from the `jazzy` branch merge of each release; verified file-identical to the tag).
- Robot: the image's own code runs (`/data/docker/open_manipulator` is only mounted at `/workspace`). Only the `docker/`
  files of that checkout matter (compose + `container.sh`).
- PC: both checkouts are mounted over the image source (`../ -> /root/ros2_ws/src/...`), launch/config/python come from the checkout.
- Rollback images kept: robot `robotis/open-manipulator:4.1.0`, PC `robotis/physical-ai-server:1.0.0-pre-cu130`
  (snapshot before the torch upgrade), `robotis/physical-ai-server:0.8.3`.

### Environment facts that drive this process
- **The robot SBC has no internet** (no route, no DNS; Yocto "Poky scarthgap", no curl). Images and git updates must be
  copied from the PC over ssh. Docker root on the robot is `/data/docker-data` (≈200 GB free); `/` has only ≈300 MB, never put files there.
- Both machines are **arm64**, so the PC can pull the robot's image.
- Robot clock is wrong (≈6 months behind, shows 2026-04). Harmless offline, but log timestamps there are off.
- PC is a Jetson AGX Orin on **L4T R39 / JetPack 7**, driver 595. The physical-ai-server image ships a CUDA 12.8 *compat*
  libcuda first in `LD_LIBRARY_PATH`, which breaks CUDA here (error 801 / "driver too old"). See section 6.

### Local changes we maintain (re-check after every update)
| File / place | Change | Why |
|---|---|---|
| `start_omy.sh`, `start_omy_inference.sh` | `FORCE_FASTRTPS` sed on `~/.bashrc` of both PC containers | robot image 4.1.0 has no zenoh |
| same | append `cuda/compat fix` `LD_LIBRARY_PATH` line to physical_ai_server `~/.bashrc` | CUDA on JetPack 7 |
| same | camera launch: wrist+top via `rs_multi_camera_launch.py` (max 2 cams), side via `rs_launch.py`; `rgb_camera.color_profile*=640,480,30` for the D435s | 3 cameras, 30 fps on USB 2.0 |
| same | `pgrep` guards so nothing starts twice; step 4 = `docker start open_manipulator` on the robot (no compose, no pull) | duplicate nodes / accidental pulls |
| `fix_physical_ai_cuda.sh` | installs torch 2.9.1+cu130 into the server venv + the LD fix | CUDA on JetPack 7 |
| `open_manipulator/docker/container.sh`, `physical_ai_tools/docker/container.sh` (PC) | `docker compose pull` commented out | no surprise updates |
| `/data/docker/open_manipulator/docker/container.sh` (robot) | pull commented out, no `sudo` (`.bak` kept) | no internet / root user |
| `/data/docker/open_manipulator/docker/docker-compose.yml` (robot) | `image: …:4.1.0`, `pid: host`, mounts `/data/docker/open_manipulator:/workspace` + `./docker:/docker`, src mount disabled (`.bak` kept) | run the image's code |
| `open_manipulator/docker/docker-compose.yml` (PC) | `image: …:5.1.1`, no `pid: host` | pin |
| `physical_ai_tools/docker/docker-compose.yml` (PC) | NVIDIA env vars added | GPU |
| `physical_ai_tools/physical_ai_server/config/omy_f3m_config.yaml` | cameras `cam_wrist`, `cam_top`, `cam_side` with `/cameraN/...` topics | our camera setup |

Container-internal changes (`~/.bashrc`, pip packages) are **lost when a container is recreated**; the start scripts and
`fix_physical_ai_cuda.sh` re-apply them.

---

## 2. Before you start

1. **Pick a quiet moment**: no recording or inference running; arm in a safe resting pose (it loses torque when its container stops).
2. **Back up the scripts** (this folder is not a git repo):
   ```bash
   B=~/Code/robotis-omy/backup/$(date +%F); mkdir -p $B
   cp ~/Code/robotis-omy/*.sh ~/Code/robotis-omy/UPDATE_PROCESS.md $B/
   cp ~/Code/robotis-omy/physical_ai_tools/physical_ai_server/config/omy_f3m_config.yaml $B/
   cp ~/Code/robotis-omy/*/docker/docker-compose.yml --parents $B/ 2>/dev/null || true
   ssh root@omy-SNPR44B1011.local "cd /data/docker/open_manipulator/docker && tar czf /data/backup-docker-$(date +%F).tgz container.sh docker-compose.yml"
   ```
3. **Datasets and policies** live in `physical_ai_tools/docker/huggingface/` and `physical_ai_tools/lerobot/outputs/` on the
   PC (host mounts, survive container recreation). Optionally copy them elsewhere anyway.
4. **Disk space**: each physical-ai-server image is ≈26 GB, open-manipulator ≈7 GB. `df -h /` on the PC; prune old
   images only after the new setup is verified (section 8).

---

## 3. Find the newest versions

```bash
# GitHub release tags (newest last)
git ls-remote --tags https://github.com/ROBOTIS-GIT/open_manipulator.git | awk -F/ '{print $3}' | sort -V | tail -5
git ls-remote --tags https://github.com/ROBOTIS-GIT/physical_ai_tools.git | awk -F/ '{print $3}' | sort -V | tail -5

# Docker Hub tags + digests (index digest and per-arch manifest digests)
for repo in open-manipulator physical-ai-server physical-ai-manager; do
  echo "== $repo"
  curl -s "https://hub.docker.com/v2/repositories/robotis/$repo/tags?page_size=15" | python3 -c "
import json,sys
for t in json.load(sys.stdin)['results']:
    arm=[i['digest'] for i in t.get('images',[]) if i.get('architecture')=='arm64']
    print(f\"{t['name']:16} {t.get('tag_last_pushed','')[:10]} index={t.get('digest')} arm64={arm}\")"
done
```

Choose **one release tag per repo that exists both on GitHub and Docker Hub** (e.g. open_manipulator `5.1.3`,
physical_ai `1.0.0`). Ignore `arm64-x.y.z`/`amd64-x.y.z` tags without a GitHub release (pre-release pushes).
Write the targets down:

```bash
OM=5.1.3      # open_manipulator / robotis/open-manipulator
PAI=1.0.0     # physical_ai_tools / robotis/physical-ai-server + physical-ai-manager
```

Read the changelogs between the current and target versions (look for RMW, Dockerfile, launch-file and config changes):

```bash
cd ~/Code/robotis-omy/open_manipulator && git fetch --tags origin && git log --oneline 4.1.0..$OM -- docker open_manipulator_bringup | cat
git show $OM:open_manipulator/CHANGELOG.rst | head -60
cd ~/Code/robotis-omy/physical_ai_tools && git fetch --tags origin && git show $PAI:physical_ai_server/CHANGELOG.rst | head -40
```

Known breaking change: **open_manipulator ≥ 5.0.0 and physical_ai_tools ≥ 1.0.0 default to `rmw_zenoh_cpp`**
(set via `~/.bashrc` in the images). Moving the robot to 5.x means the whole cell moves to Zenoh (section 7).
Also check that the launch files we use still exist in the target (`omy_ai.launch.py`,
`omy_f3m_follower_ai.launch.py ros2_control_type:=omy_f3m_smooth`):
`git ls-tree --name-only $OM open_manipulator_bringup/launch/ | grep omy`

---

## 4. Update the PC

### 4a. Pull images by explicit tag and verify digests
```bash
docker pull robotis/open-manipulator:$OM
docker pull robotis/physical-ai-server:$PAI
docker pull robotis/physical-ai-manager:$PAI
docker images --digests | grep robotis      # compare DIGEST with the Docker Hub "index" digest from section 3
```
(The PC uses the containerd image store: image ID == index digest.)

### 4b. Update the git checkouts (keep local edits)
```bash
cd ~/Code/robotis-omy/open_manipulator
git stash push -m "local robotcel edits"          # docker/container.sh, docker/docker-compose.yml
git fetch --tags origin && git checkout $OM
git stash pop                                      # resolve conflicts if any; keep: pull commented out, image pin
sed -i "s|^\(\s*image:\) robotis/open-manipulator:.*|\1 robotis/open-manipulator:$OM|" docker/docker-compose.yml

cd ~/Code/robotis-omy/physical_ai_tools
git stash push -m "local robotcel edits"          # container.sh, docker-compose.yml, omy_f3m_config.yaml
git fetch --tags origin && git checkout $PAI
git stash pop
grep -n "image:" docker/docker-compose.yml        # must say :$PAI for server and manager
```
Check after the pop: `container.sh` still has the pull commented out, compose has the NVIDIA env vars,
`omy_f3m_config.yaml` still has our three cameras (new upstream config keys must be merged by hand).
Note open_manipulator ≥ 5.1.1 changed the compose build context to the repo root – keep upstream's version of those lines.

### 4c. Recreate the PC containers
```bash
~/Code/robotis-omy/stop_omy.sh               # stops robot app + PC containers
cd ~/Code/robotis-omy/open_manipulator/docker && docker compose up -d --force-recreate
cd ~/Code/robotis-omy/physical_ai_tools/docker && docker compose up -d --force-recreate
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
```
Then fix CUDA in the new server container (section 6) **before** the first inference.

---

## 5. Update the robot SBC (offline)

### 5a. Copy the image from the PC to the robot
```bash
docker pull --platform linux/arm64 robotis/open-manipulator:$OM
docker save --platform linux/arm64 robotis/open-manipulator:$OM | gzip -1 | \
  ssh root@omy-SNPR44B1011.local "gunzip | docker load"
ssh root@omy-SNPR44B1011.local "docker images robotis/open-manipulator"
```
Verify it is the right image: the robot uses the classic overlay2 store, so its image ID is the **config digest**
of the arm64 manifest (no repo digest after `docker load`):
```bash
ARM=$(docker buildx imagetools inspect robotis/open-manipulator:$OM --raw | python3 -c "import json,sys;print([m['digest'] for m in json.load(sys.stdin)['manifests'] if m['platform']['architecture']=='arm64'][0])")
docker buildx imagetools inspect robotis/open-manipulator@$ARM --raw | python3 -c "import json,sys;print('expected', json.load(sys.stdin)['config']['digest'])"
ssh root@omy-SNPR44B1011.local "docker image inspect robotis/open-manipulator:$OM --format 'robot    {{.Id}}'"
```

### 5b. Update the robot's checkout (only `docker/` matters there)
```bash
cd ~/Code/robotis-omy/open_manipulator && git bundle create /tmp/om.bundle --tags jazzy main
scp /tmp/om.bundle root@omy-SNPR44B1011.local:/data/om.bundle
ssh root@omy-SNPR44B1011.local "cd /data/docker/open_manipulator && git stash push -m robotcel && \
  git fetch /data/om.bundle 'refs/tags/*:refs/tags/*' && git checkout $OM && git stash pop; git status --short; rm /data/om.bundle"
```
Re-check the robot's `docker/docker-compose.yml` and `docker/container.sh` against the table in section 1:
`image: robotis/open-manipulator:$OM`, `pid: host`, `/data/docker/open_manipulator:/workspace`, `./docker:/docker`,
src mount commented out, pull commented out, no `sudo`. Keep upstream additions (e.g. 5.1.0 adds an
`/var/run/robotis/agent_sockets/open_manipulator:/var/run/agent` volume for cyclo-manager; create that host dir if needed).

### 5c. Recreate the robot container
```bash
ssh root@omy-SNPR44B1011.local "cd /data/docker/open_manipulator/docker && docker compose up -d --force-recreate && \
  docker ps --format '{{.Names}} {{.Image}} {{.Status}}'"
```
The start scripts only `docker start` the existing container, so recreation is always this explicit step.

---

## 6. CUDA in physical_ai_server (after every recreation)

First test whether the new image fixed it upstream:
```bash
docker exec physical_ai_server bash -ic '/opt/venv/bin/python3 -c "import torch;print(torch.__version__, torch.version.cuda, torch.cuda.is_available())"'
```
- `True` → nothing to do (then remove the LD/torch parts from the start scripts and `fix_physical_ai_cuda.sh`).
- `False` / error 801 / "driver too old" → `~/Code/robotis-omy/fix_physical_ai_cuda.sh`
  (drops `/usr/local/cuda/compat` from `LD_LIBRARY_PATH` in `~/.bashrc`, installs torch 2.9.1+cu130, restarts the container).
  If the image's torch is already CUDA 13 (`torch.version.cuda` 13.x), only the LD fix is needed.

Also check whether the RAM leak is fixed upstream (multi-task recording keeps all raw frames in
`total_frame_buffer`, ≈5 GB per recorded minute with 3 cameras, never freed):
`grep -n "total_frame_buffer" physical_ai_tools/physical_ai_server/physical_ai_server/data_processing/lerobot_dataset_wrapper.py`
— if it is still never cleared after encoding, keep recording sessions < ~8 min and restart the server between sessions.

---

## 7. Switch the cell from FastRTPS to Zenoh (only once the robot runs open_manipulator ≥ 5.0.0)

All three ROS participants must use the **same RMW**: robot container, PC camera container, physical_ai_server.

1. **Start scripts** (`start_omy.sh`, `start_omy_inference.sh`): delete the `FORCE_FASTRTPS` definition and its two
   `docker exec … "$FORCE_FASTRTPS"` calls (the 5.x / 1.0.0 images already export `RMW_IMPLEMENTATION=rmw_zenoh_cpp`
   in `~/.bashrc`; recreated containers have a fresh `.bashrc`). Keep the LD/CUDA line if section 6 still needs it.
2. **Zenoh routers**: rmw_zenoh nodes only find each other through a router (`rmw_zenohd`, port 7447).
   Run one router on each machine, started before any node:
   - PC: in the camera container, before the camera launches:
     `docker exec -d open_manipulator bash -ic 'ros2 run rmw_zenoh_cpp rmw_zenohd'` then `sleep 2`.
   - Robot: in its container, before the omy launch:
     `ssh $ROBOT_HOST "docker exec -d open_manipulator bash -ic 'ZENOH_CONFIG_OVERRIDE=\"connect/endpoints=[\\\"tcp/192.168.1.107:7447\\\"]\" ros2 run rmw_zenoh_cpp rmw_zenohd'"`
     (the robot router connects to the PC router; use the PC's wired `end0` address, check with `ip -4 addr show end0`).
   - Add `pgrep -f rmw_zenohd` guards like the other steps.
   **Verify** this router setup on the target versions before relying on it (router-to-router discovery and the
   `ZENOH_CONFIG_OVERRIDE` syntax have changed between rmw_zenoh releases):
   `docker exec physical_ai_server bash -ic 'ros2 node list'` must show the robot nodes (`/arm_controller`,
   `/dynamixel_hardware_interface`, …) and the camera nodes.
3. `ROS_DOMAIN_ID=30` stays the same everywhere.

Rollback to FastRTPS = robot back on 4.1.0 (section 9) + restore the backed-up start scripts.

---

## 8. Verification checklist (run all after an update)

```bash
ROBOT=root@omy-SNPR44B1011.local
# versions
docker ps --format '{{.Names}}\t{{.Image}}'; ssh $ROBOT "docker ps --format '{{.Names}} {{.Image}}'"
# RMW + one AI server only
docker exec physical_ai_server bash -c 'for p in $(pgrep -f "lib/physical_ai_server/physical_ai_server --ros-args"); do tr "\0" "\n" </proc/$p/environ | grep -E "^RMW|^LD_LIB"; done'
# robot controllers (one ros2_control_node per arm, all active)
ssh $ROBOT "docker exec open_manipulator bash -ic 'ros2 control list_controllers; ros2 control list_controllers -c /leader/controller_manager'"
# data rates seen by the AI server: cameras ≈30 Hz, /joint_states ≈400 Hz, /leader/joint_trajectory ≈300 Hz (teleop)
docker exec physical_ai_server bash -ic 'for t in /camera1/cam_wrist/color/image_rect_raw/compressed /camera2/cam_top/color/image_raw/compressed /camera3/cam_side/color/image_raw/compressed /joint_states /leader/joint_trajectory; do echo "$t $(timeout 6 ros2 topic hz $t | grep average | tail -1)"; done'
# GPU
docker exec physical_ai_server bash -ic '/opt/venv/bin/python3 -c "import torch;print(torch.cuda.is_available())"'
```
Then functional tests: teleop (leader moves follower), a 1-episode test recording (check RAM with `free -h`),
and inference with a known-good policy (e.g. `lerobot/outputs/train/smolvla_object_placement_bs32_decay20k/checkpoints/last/pretrained_model`;
note it was trained with 2 cameras – remove `cam_side` from `omy_f3m_config.yaml` for it).

When everything works: update section 1 of this file, then prune old images
(`docker image rm robotis/physical-ai-server:0.8.3 …`), keeping the previous version for one rollback.

---

## 9. Rollback

- **Robot**: `ssh $ROBOT "cd /data/docker/open_manipulator/docker && sed -i 's|^\(\s*image:\).*|\1 robotis/open-manipulator:4.1.0|' docker-compose.yml && docker compose up -d --force-recreate"`
  (4.1.0 stays loaded on the robot; don't prune it). Restore `/data/backup-docker-<date>.tgz` if the docker files changed.
- **PC**: set the previous tags in both compose files, `git checkout` the previous release in both checkouts
  (4.1.4 / 1.0.0), `docker compose up -d --force-recreate`, run `fix_physical_ai_cuda.sh`.
- **Scripts**: copy back from `~/Code/robotis-omy/backup/<date>/`.

---

## 10. Known hardware issues (not update related)
- Follower **joint 3 (ID 003) overheats** (>57 °C) under long loads → torque off, follower stops reacting. Restarting the
  robot app reboots the servo; let it cool, keep sessions short.
- Follower **end unit (ID 210)** logs frequent `SYNC_READ_FAIL`; check its cable if the gripper misbehaves.
- `rs_multi_camera_launch.py` supports only 2 cameras; the D435 needs `rgb_camera.color_profile` (D405 uses `depth_module.color_profile`).
