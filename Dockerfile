# --------------------------------------------------------
# 1. Base Image: Ubuntu 20.04
# --------------------------------------------------------
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# --------------------------------------------------------
# 2. System Dependencies
# --------------------------------------------------------
RUN apt-get update && apt-get install -y \
    curl wget git build-essential cmake espeak-ng \
    python3-pip python3-dev \
    net-tools iputils-ping vim sudo \
    locales tzdata \
    gnupg2 lsb-release software-properties-common \
    xvfb libgl1-mesa-dev libgl1-mesa-glx libegl1-mesa-dev \
    libgles2-mesa-dev libglfw3-dev libglew-dev libosmesa6-dev \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# --------------------------------------------------------
# 3. Install ROS 2 Foxy
# --------------------------------------------------------
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null

RUN apt-get update && apt-get install -y \
    ros-foxy-desktop \
    ros-foxy-ros-base \
    ros-foxy-rmw-cyclonedds-cpp \
    ros-foxy-rosidl-generator-dds-idl \
    ros-foxy-rclpy \
    ros-foxy-rclcpp \
    python3-argcomplete \
    python3-colcon-common-extensions \
    python3-rosdep \
    && rm -rf /var/lib/apt/lists/*

RUN rosdep init && rosdep update

# --------------------------------------------------------
# 4. Setup User 'developer'
# --------------------------------------------------------
ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

USER $USERNAME
WORKDIR /home/$USERNAME
RUN mkdir -p /home/$USERNAME/libs

# --------------------------------------------------------
# 5. Build Unitree ROS 2 (System Python)
# --------------------------------------------------------
WORKDIR /home/$USERNAME/libs
RUN git clone https://github.com/unitreerobotics/unitree_ros2.git
WORKDIR /home/$USERNAME/libs/unitree_ros2

RUN rm -rf cyclonedds || true \
    && mkdir -p cyclonedds_ws/src

WORKDIR /home/$USERNAME/libs/unitree_ros2/cyclonedds_ws/src
RUN git clone https://github.com/ros2/rmw_cyclonedds -b foxy \
    && git clone https://github.com/eclipse-cyclonedds/cyclonedds -b releases/0.10.x

WORKDIR /home/$USERNAME/libs/unitree_ros2/cyclonedds_ws
SHELL ["/bin/bash", "-c"]

RUN colcon build --packages-select cyclonedds

RUN source /opt/ros/foxy/setup.bash \
    && source install/setup.bash \
    && colcon build --packages-select rmw_cyclonedds_cpp

WORKDIR /home/$USERNAME/libs/unitree_ros2
RUN source /opt/ros/foxy/setup.bash \
    && source cyclonedds_ws/install/setup.bash \
    && colcon build --packages-ignore cyclonedds rmw_cyclonedds_cpp

# --------------------------------------------------------
# 6. Install Miniforge (Conda)
# --------------------------------------------------------
ENV CONDA_DIR=/home/$USERNAME/miniforge
RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh \
    && bash /tmp/miniforge.sh -b -p $CONDA_DIR \
    && rm /tmp/miniforge.sh

ENV PATH=$CONDA_DIR/bin:$PATH
RUN conda init bash

# --------------------------------------------------------
# 7. Setup Python Environments
# --------------------------------------------------------
WORKDIR /home/$USERNAME/libs

# --- A. Isaac Gym ---
RUN conda create -n twist2 python=3.8 -y

# Download fallback
RUN wget -O IsaacGym_Preview_4_Package.tar.gz https://developer.nvidia.com/isaac-gym-preview-4 \
    && tar -xf IsaacGym_Preview_4_Package.tar.gz \
    && rm IsaacGym_Preview_4_Package.tar.gz

# FIX: Source conda.sh directly instead of .bashrc
RUN source $CONDA_DIR/etc/profile.d/conda.sh && conda activate twist2 \
    && cd isaacgym/python && pip install -e .

# --- B. Unitree SDK2 ---
RUN git clone https://github.com/YanjieZe/unitree_sdk2.git
WORKDIR /home/$USERNAME/libs/unitree_sdk2

RUN sudo apt-get update && sudo apt-get install -y pybind11-dev
# FIX: Source conda.sh directly
RUN source $CONDA_DIR/etc/profile.d/conda.sh && conda activate twist2 \
    && pip install pybind11 pybind11-stubgen

WORKDIR /home/$USERNAME/libs/unitree_sdk2/python_binding
# FIX: Source conda.sh directly
RUN source $CONDA_DIR/etc/profile.d/conda.sh && conda activate twist2 \
    && export UNITREE_SDK2_PATH=/home/$USERNAME/libs/unitree_sdk2 \
    && bash build.sh --sdk-path $UNITREE_SDK2_PATH

# Install to conda site-packages
# FIX: Source conda.sh directly
RUN source $CONDA_DIR/etc/profile.d/conda.sh && conda activate twist2 \
    && SITE_PACKAGES=$(python -c "import site; print(site.getsitepackages()[0])") \
    && cp build/lib/unitree_interface.cpython-*-linux-gnu.so $SITE_PACKAGES/unitree_interface.so

# --- C. GMR & XRoboToolkit ---
RUN conda create -n gmr python=3.10 -y
WORKDIR /home/$USERNAME/libs

# FIX: Source conda.sh directly
RUN source $CONDA_DIR/etc/profile.d/conda.sh && conda activate gmr \
    && git clone https://github.com/YanjieZe/GMR.git \
    && cd GMR && pip install -e . \
    && conda install -c conda-forge libstdcxx-ng -y

# Build XRoboToolkit
# FIX: Source conda.sh directly
RUN source $CONDA_DIR/etc/profile.d/conda.sh && conda activate gmr \
    && git clone https://github.com/YanjieZe/XRoboToolkit-PC-Service-Pybind.git \
    && cd XRoboToolkit-PC-Service-Pybind \
    && mkdir -p tmp \
    && cd tmp \
    && git clone https://github.com/XR-Robotics/XRoboToolkit-PC-Service.git \
    && cd XRoboToolkit-PC-Service/RoboticsService/PXREARobotSDK \
    && bash build.sh

WORKDIR /home/$USERNAME/libs/XRoboToolkit-PC-Service-Pybind
# FIX: Source conda.sh directly
RUN source $CONDA_DIR/etc/profile.d/conda.sh && conda activate gmr \
    && mkdir -p lib include \
    && cp tmp/XRoboToolkit-PC-Service/RoboticsService/PXREARobotSDK/PXREARobotSDK.h include/ \
    && cp -r tmp/XRoboToolkit-PC-Service/RoboticsService/PXREARobotSDK/nlohmann include/nlohmann/ \
    && cp tmp/XRoboToolkit-PC-Service/RoboticsService/PXREARobotSDK/build/libPXREARobotSDK.so lib/ \
    && conda install -c conda-forge pybind11 \
    && python setup.py install

# --------------------------------------------------------
# 8. Install Local Editable Packages in TWIST2
# --------------------------------------------------------
# Set the final working directory
WORKDIR /home/$USERNAME/ws/TWIST2

# Ensure the shell is bash for proper execution of source and chained commands
SHELL ["/bin/bash", "-c"]

# Activate the environment and run the installation commands inside the correct subdirectories
RUN source $CONDA_DIR/etc/profile.d/conda.sh && conda activate twist2 \
    && cd rsl_rl && pip install -e . && cd .. \
    && cd legged_gym && pip install -e . && cd .. \
    && cd pose && pip install -e . && cd ..

CMD ["/bin/bash"]

RUN source $CONDA_DIR/etc/profile.d/conda.sh && conda activate twist2 \
    && pip install "numpy==1.23.0" pydelatin wandb tqdm opencv-python ipdb pyfqmr flask dill gdown hydra-core "imageio[ffmpeg]" mujoco mujoco-python-viewer isaacgym-stubs pytorch-kinematics rich termcolor zmq \
    && pip install redis[hiredis] pyttsx3 onnx onnxruntime-gpu customtkinter

WORKDIR /home/$USERNAME/ws/TWIST2
CMD ["/bin/bash"]
