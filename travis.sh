#!/bin/bash

# Software License Agreement (BSD License)
#
# Copyright (c) 2015, Isaac I. Y. Saito, Dave Coleman
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#       * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#       * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#       * Neither the name of the Isaac I. Y. Saito, nor the names
#       of its contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
## Greatly inspired by JSK travis https://github.com/jsk-ros-pkg/jsk_travis
## Author: Isaac I. Y. Saito

## This is a "common" script that can be run on travis CI at a downstream github repository.
## See ./README.rst for the detailed usage.
##
## Variables that are not meant to be exposed externally from this script may be lead by underscore.

#set -e
#set -x
set +x

# Define some env vars that need to come earlier than util.sh
export CI_SOURCE_PATH=$(pwd)
export CI_PARENT_DIR=.ci_config  # This is the folder name that is used in downstream repositories in order to point to this repo.
export HIT_ENDOFSCRIPT=false
export DOWNSTREAM_REPO_NAME=${PWD##*/}

# Helper functions
source ${CI_SOURCE_PATH}/$CI_PARENT_DIR/util.sh

trap errorFunction ERR
trap successFunction SIGTERM  # So that this script won't terminate without verifying that all necessary steps are done.

if [[ "$ROS_DISTRO" != "kinetic" ]]; then
    echo "This script only supports kinetic currently. TODO add docker containers for previous ROS versions";
    errorFunction;
fi

# The Dockerfile in this repository defines a Ubuntu 16.04 container with ROS pre-installed
if ! [ "$IN_DOCKER" ]; then

  # Pull first to allow us to hide console output
  docker pull davetcoleman/industrial_ci > /dev/null

  # Start Docker container
  docker run \
      -e ROS_REPOSITORY_PATH \
      -e ROS_DISTRO \
      -e ADDITIONAL_DEBS \
      -e BEFORE_SCRIPT \
      -e BUILD_PKGS \
      -e CI_PARENT_DIR \
      -e NOT_TEST_BUILD \
      -e NOT_TEST_INSTALL \
      -e PRERELEASE \
      -e PRERELEASE_DOWNSTREAM_DEPTH \
      -e PRERELEASE_REPONAME \
      -e USE_DEBROS_DISTRO \
      -e UPSTREAM_WORKSPACE \
      -e ROSINSTALL_FILENAME \
      -v $(pwd):/root/$DOWNSTREAM_REPO_NAME davetcoleman/industrial_ci \
      /bin/bash -c "cd /root/$DOWNSTREAM_REPO_NAME; source .ci_config/travis.sh;"
  retval=$?

  if [ $retval -eq 0 ]; then
      echo "ROS $ROS_DISTRO Docker container finished successfully"
      HIT_ENDOFSCRIPT=true;
      successFunction 0;
  fi
  echo "ROS $ROS_DISTRO Docker container finished with errors"
  exit # error
fi

# Export env variables
if [ ! "$ROS_REPOSITORY_PATH" ]; then # If not specified, use ROS Shadow repository http://wiki.ros.org/ShadowRepository
    export ROS_REPOSITORY_PATH="http://packages.ros.org/ros-shadow-fixed/ubuntu";
fi
if [ ! "$ROSINSTALL_FILENAME" ]; then # .rosintall file name
    export ROSINSTALL_FILENAME=".travis.rosinstall";
fi
if [ ! "$UPSTREAM_WORKSPACE" ]; then
    export UPSTREAM_WORKSPACE="debian";
fi

# Set apt repo - this was already defined in OSRF image but we probably want shadow-fixed
sudo -E sh -c 'echo "deb $ROS_REPOSITORY_PATH `lsb_release -cs` main" > /etc/apt/sources.list.d/ros-latest.list'

# Update the sources
travis_run sudo apt-get -qq update || (echo "ERROR: apt server not responding. This is a rare situation, and usually just waiting for a while clears this. See https://github.com/ros-industrial/industrial_ci/pull/56 for more of the discussion"; errorFunction)

# If more DEBs needed during preparation, define ADDITIONAL_DEBS variable where you list the name of DEB(S, delimitted by whitespace)
if [ "$ADDITIONAL_DEBS" ]; then
    travis_run sudo apt-get -qq install -q -y $ADDITIONAL_DEBS;
fi

# Setup rosdep
#sudo rosdep init # already setup is base ROS Docker image
ret_rosdep=1
travis_run rosdep update || while [ $ret_rosdep != 0 ]; do sleep 1; rosdep update && ret_rosdep=0 || echo "rosdep update failed"; done

# Install any prerequisites or dependencies necessary to run build

# Create workspace
travis_run mkdir -p ~/ros/ws_$DOWNSTREAM_REPO_NAME/src
travis_run cd ~/ros/ws_$DOWNSTREAM_REPO_NAME/src

case "$UPSTREAM_WORKSPACE" in
    debian)
        echo "Obtain deb binary for upstream packages."
        ;;
    file) # When UPSTREAM_WORKSPACE is file, the dependended packages that need to be built from source are downloaded based on $ROSINSTALL_FILENAME file.
        travis_run wstool init .
        # Prioritize $ROSINSTALL_FILENAME.$ROS_DISTRO if it exists over $ROSINSTALL_FILENAME.
        if [ -e $CI_SOURCE_PATH/$ROSINSTALL_FILENAME.$ROS_DISTRO ]; then
            # install (maybe unreleased version) dependencies from source for specific ros version
            travis_run wstool merge file://$CI_SOURCE_PATH/$ROSINSTALL_FILENAME.$ROS_DISTRO
        elif [ -e $CI_SOURCE_PATH/$ROSINSTALL_FILENAME ]; then
            # install (maybe unreleased version) dependencies from source
            travis_run wstool merge file://$CI_SOURCE_PATH/$ROSINSTALL_FILENAME
        fi
        ;;
    http://* | https://*) # When UPSTREAM_WORKSPACE is an http url, use it directly
        travis_run wstool init .
        travis_run wstool merge $UPSTREAM_WORKSPACE
        ;;
esac

# download upstream packages into workspace
if [ -e .rosinstall ]; then
    # ensure that the downstream is not in .rosinstall
    travis_run wstool rm $DOWNSTREAM_REPO_NAME || true
    travis_run cat .rosinstall
    travis_run wstool update
fi

# CI_SOURCE_PATH is the path of the downstream repository that we are testing. Link it to the catkin workspace
travis_run ln -s $CI_SOURCE_PATH .

# Disable metapackage
#echo "Disabling metapackages:"
#find -L . -name package.xml -print -exec ${CI_SOURCE_PATH}/$CI_PARENT_DIR/check_metapackage.py {} \; -a -exec bash -c 'touch `dirname ${1}`/CATKIN_IGNORE' funcname {} \;

# Save .rosinstall file of this tested downstream repo, only during the runtime on travis CI
# if [ ! -e .rosinstall ]; then
#     echo "- git: {local-name: $DOWNSTREAM_REPO_NAME, uri: 'http://github.com/$TRAVIS_REPO_SLUG'}" >> .rosinstall
# fi

# Prepare your build for testing e.g. copy database configurations, environment variables, etc.

travis_run source /opt/ros/$ROS_DISTRO/setup.bash # re-source setup.bash for setting environmet vairable for package installed via rosdep

# Run before script
if [ "${BEFORE_SCRIPT// }" != "" ]; then sh -c "${BEFORE_SCRIPT}"; fi

# Install source-based package dependencies
travis_run sudo rosdep install -r -y -q -n --from-paths . --ignore-src --rosdistro $ROS_DISTRO

# Change to base of workspace
travis_run cd ~/ros/ws_$DOWNSTREAM_REPO_NAME/

# re-source setup.bash for setting environmet vairable for package installed via rosdep
travis_run source /opt/ros/$ROS_DISTRO/setup.bash

# Configure catkin
travis_run catkin config --install

# For a command that doesn’t produce output for more than 10 minutes, prefix it with travis_wait
echo "Running catkin build..."
my_travis_wait 60 catkin build --no-status --summarize $BUILD_PKGS_WHITELIST

if [ "$NOT_TEST_BUILD" != "true" ]; then

    source install/setup.bash;
    # run_tests
    # catkin build --no-status --catkin-make-args run_tests --
    # catkin_test_results build || errorFunction

    TEST_PKGS=$(catkin_topological_order $CI_SOURCE_PATH --only-names)
    if [ -n "$TEST_PKGS" ]; then TEST_PKGS="--no-deps $TEST_PKGS"; fi
    if [ "$ALLOW_TEST_FAILURE" != "true" ]; then ALLOW_TEST_FAILURE=false; fi
    echo "Running tests for packages: '$TEST_PKGS'"

    catkin build --no-status --summarize --make-args tests -- $TEST_PKGS
    catkin run_tests --no-status --summarize $TEST_PKGS
    catkin_test_results

else
    echo "Skipping test build"
fi

# ## BEGIN: travis' after_script
# PATH=/usr/local/bin:$PATH  # for installed catkin_test_results
# PYTHONPATH=/usr/local/lib/python2.7/dist-packages:$PYTHONPATH
# echo "Showing test results?"
# if [ "${ROS_LOG_DIR// }" == "" ]; then export ROS_LOG_DIR=~/.ros/test_results; fi # http://wiki.ros.org/ROS/EnvironmentVariables#ROS_LOG_DIR
# if [ -e $ROS_LOG_DIR ]; then
#     catkin_test_results --verbose --all $ROS_LOG_DIR || errorFunction;
# fi
# if [ -e ~/ros/ws_$DOWNSTREAM_REPO_NAME/build/ ]; then
#     catkin_test_results --verbose --all ~/ros/ws_$DOWNSTREAM_REPO_NAME/build/ || errorFunction;
# fi
# if [ -e ~/.ros/test_results/ ]; then
#     catkin_test_results --verbose --all ~/.ros/test_results/ || errorFunction;
# fi

echo "Travis script has finished successfully"
HIT_ENDOFSCRIPT=true
successFunction 0
