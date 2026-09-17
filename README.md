# rcllean

A ROS 2 Client Library for the Lean 4 programming language and theorem prover. This project enables users to write ROS 2 nodes and theorems about their properties in Lean 4. This project takes inspiration from the excellent ROS 2 Rust client [rclrs](https://github.com/ros2-rust/ros2_rust).

## Limitations

This project is in its infancy. It has been designed for and tested on ROS 2 Jazzy Jalisco on Ubuntu 24.04 only.

## Installation

Install Lean 4 via [elan](https://github.com/leanprover/elan):

```bash
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
  | sh -s -- -y --default-toolchain none
echo 'source "$HOME/.elan/env"' >> ~/.bashrc
source "$HOME/.elan/env"
```

Next install the colcon plugin for lake packages:

```bash
python3 -m pip install --user --break-system-packages git+https://github.com/SEIL-ISR/colcon-ros-lake.git
```

Make a project directory and clone the dependencies and the library:

```bash
mkdir -p rcllean_ws/src/deps && cd rcllean_ws/src
git clone -b jazzy https://github.com/ros2/common_interfaces.git deps/common_interfaces
git clone -b jazzy https://github.com/ros2/rcl_interfaces.git deps/rcl_interfaces
git clone -b jazzy https://github.com/ros2/rosidl_core.git deps/rosidl_core
git clone -b jazzy https://github.com/ros2/rosidl_defaults.git deps/rosidl_defaults
git clone -b jazzy https://github.com/ros2/test_interface_files.git deps/test_interface_files
git clone -b jazzy https://github.com/ros2/unique_identifier_msgs.git deps/unique_identifier_msgs

git clone https://github.com/SEIL-ISR/rosidl_lean.git
git clone https://github.com/SEIL-ISR/ros2_lean_examples.git
git clone https://github.com/SEIL-ISR/rcllean.git
```

Return to the workspace root and build with colcon then source:

```bash
source /opt/ros/jazzy/setup.bash
colcon build
```

## Running and example Lean node

Source the workspace and run an example node:

```bash
source install/setup.bash
ros2 launch rcllean_examples heartbeat.launch.py
```


## License

Apache-2.0. See [`LICENSE`](LICENSE).
