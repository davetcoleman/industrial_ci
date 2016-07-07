FROM osrf/ros:kinetic-desktop
MAINTAINER Dave Coleman dave@dav.ee

# Install packages
RUN apt-get update -qq &&\
    #    apt-get install -qq -y \
    apt-get install -y \
        git \
        sudo \
        wget \
        lsb-release \
        python-pip \
        python-catkin-tools \
        python-rosdep \
        python-wstool \
        ros-$ROS_DISTRO-rosbash \
        ros-$ROS_DISTRO-rospack && \
    rm -rf /var/lib/apt/lists/*
ENV IN_DOCKER 1
ENV TERM xterm
