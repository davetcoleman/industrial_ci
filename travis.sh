#!/bin/bash

# Software License Agreement (BSD License)
#
# Copyright (c) 2015, Isaac I. Y. Saito
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

source ${CI_SOURCE_PATH}/$CI_PARENT_DIR/util.sh

trap error ERR
trap success SIGTERM  # So that this script won't terminate without verifying that all necessary steps are done.

# Building in 16.04 requires running this script in a docker container
# The Dockerfile in this repository defines a Ubuntu 16.04 container
if [[ "$ROS_DISTRO" == "kinetic" ]] && ! [ "$IN_DOCKER" ]; then

  travis_time_start run_travissh_docker
  export DOWNSTREAM_REPO_NAME=${PWD##*/}
  docker run \
      -e ROS_REPOSITORY_PATH \
      -e ROS_DISTRO \
      -e ADDITIONAL_DEBS \
      -e BEFORE_SCRIPT \
      -e BUILD_PKGS \
      -e CATKIN_PARALLEL_JOBS \
      -e CATKIN_PARALLEL_TEST_JOBS \
      -e CI_PARENT_DIR \
      -e NOT_TEST_BUILD \
      -e NOT_TEST_INSTALL \
      -e PRERELEASE \
      -e PRERELEASE_DOWNSTREAM_DEPTH \
      -e PRERELEASE_REPONAME \
      -e PKGS_DOWNSTREAM \
      -e ROS_PARALLEL_JOBS \
      -e ROS_PARALLEL_TEST_JOBS \
      -e ROS_PARALLEL_JOBS \
      -e ROSWS \
      -e TARGET_PKGS \
      -e USE_DEBROS_DISTRO \
      -e UPSTREAM_WORKSPACE \
      -e ROSINSTALL_FILENAME \
      -v $(pwd):/root/$DOWNSTREAM_REPO_NAME davetcoleman/industrial_ci \
      /bin/bash -c "cd /root/$DOWNSTREAM_REPO_NAME; source .ci_config/travis.sh;" \
  retval=$?
  if [ $retval -eq 0 ]; then HIT_ENDOFSCRIPT=true; success 0; else exit; fi  # Call  travis_time_end  run_travissh_docker
fi

travis_time_start init_travis_environment
# Define more env vars
ROSWS=wstool
export DOWNSTREAM_REPO_NAME=${PWD##*/}
if [ ! "$CATKIN_PARALLEL_JOBS" ]; then
    export CATKIN_PARALLEL_JOBS="-p4";
fi
if [ ! "$CATKIN_PARALLEL_TEST_JOBS" ]; then
    export CATKIN_PARALLEL_TEST_JOBS="$CATKIN_PARALLEL_JOBS";
fi
if [ ! "$ROS_PARALLEL_JOBS" ]; then
    export ROS_PARALLEL_JOBS="-j8";
fi
if [ ! "$ROS_PARALLEL_TEST_JOBS" ]; then
    export ROS_PARALLEL_TEST_JOBS="$ROS_PARALLEL_JOBS";
fi
# If not specified, use ROS Shadow repository http://wiki.ros.org/ShadowRepository
if [ ! "$ROS_REPOSITORY_PATH" ]; then
    export ROS_REPOSITORY_PATH="http://packages.ros.org/ros-shadow-fixed/ubuntu";
fi
# .rosintall file name
if [ ! "$ROSINSTALL_FILENAME" ]; then
    export ROSINSTALL_FILENAME=".travis.rosinstall";
fi
# For apt key stores
if [ ! "$APTKEY_STORE_HTTPS" ]; then
    export APTKEY_STORE_HTTPS="https://raw.githubusercontent.com/ros/rosdistro/master/ros.key";
fi
if [ ! "$APTKEY_STORE_SKS" ]; then
    export APTKEY_STORE_SKS="hkp://ha.pool.sks-keyservers.net";
fi  # Export a variable for SKS URL for break-testing purpose.
if [ ! "$HASHKEY_SKS" ]; then
    export HASHKEY_SKS="0xB01FA116";
fi
if [ "$USE_DEB" ]; then  # USE_DEB is deprecated. See https://github.com/ros-industrial/industrial_ci/pull/47#discussion_r64882878 for the discussion.
    if [ "$USE_DEB" != "true" ]; then
        export UPSTREAM_WORKSPACE="file";
    else
        export UPSTREAM_WORKSPACE="debian";
    fi
fi
if [ ! "$UPSTREAM_WORKSPACE" ]; then
    export UPSTREAM_WORKSPACE="debian";
fi

travis_time_end  # init_travis_environment

travis_time_start setup_ros

echo "Testing branch $TRAVIS_BRANCH of $DOWNSTREAM_REPO_NAME"

sudo apt-get update -qq || (echo "ERROR: apt server not responding. This is a rare situation, and usually just waiting for a while clears this. See https://github.com/ros-industrial/industrial_ci/pull/56 for more of the discussion"; error)

# If more DEBs needed during preparation, define ADDITIONAL_DEBS variable where you list the name of DEB(S, delimitted by whitespace)
if [ "$ADDITIONAL_DEBS" ]; then
    sudo apt-get install -q -qq -y $ADDITIONAL_DEBS;
fi

# Setup rosdep
sudo rosdep init
ret_rosdep=1
rosdep update || while [ $ret_rosdep != 0 ]; do sleep 1; rosdep update && ret_rosdep=0 || echo "rosdep update failed"; done

travis_time_end  # setup_ros

travis_time_start check_version_ros

travis_time_start setup_rosws

## BEGIN: travis' install: # Use this to install any prerequisites or dependencies necessary to run your build ##
# Create workspace
mkdir -p ~/ros/ws_$DOWNSTREAM_REPO_NAME/src
cd ~/ros/ws_$DOWNSTREAM_REPO_NAME/src
case "$UPSTREAM_WORKSPACE" in
debian)
    echo "Obtain deb binary for upstream packages."
    ;;
file) # When UPSTREAM_WORKSPACE is file, the dependended packages that need to be built from source are downloaded based on $ROSINSTALL_FILENAME file.
    $ROSWS init .
    # Prioritize $ROSINSTALL_FILENAME.$ROS_DISTRO if it exists over $ROSINSTALL_FILENAME.
    if [ -e $CI_SOURCE_PATH/$ROSINSTALL_FILENAME.$ROS_DISTRO ]; then
        # install (maybe unreleased version) dependencies from source for specific ros version
        $ROSWS merge file://$CI_SOURCE_PATH/$ROSINSTALL_FILENAME.$ROS_DISTRO
    elif [ -e $CI_SOURCE_PATH/$ROSINSTALL_FILENAME ]; then
        # install (maybe unreleased version) dependencies from source
        $ROSWS merge file://$CI_SOURCE_PATH/$ROSINSTALL_FILENAME
    fi
    ;;
http://* | https://*) # When UPSTREAM_WORKSPACE is an http url, use it directly
    $ROSWS init .
    $ROSWS merge $UPSTREAM_WORKSPACE
    ;;
esac

# download upstream packages into workspace
if [ -e .rosinstall ]; then
    # ensure that the downstream is not in .rosinstall
    $ROSWS rm $DOWNSTREAM_REPO_NAME || true
    $ROSWS update
fi

# CI_SOURCE_PATH is the path of the downstream repository that we are testing. Link it to the catkin workspace
ln -s $CI_SOURCE_PATH .

# Disable metapackage
find -L . -name package.xml -print -exec ${CI_SOURCE_PATH}/$CI_PARENT_DIR/check_metapackage.py {} \; -a -exec bash -c 'touch `dirname ${1}`/CATKIN_IGNORE' funcname {} \;

# Save .rosinstall file of this tested downstream repo, only during the runtime on travis CI
if [ ! -e .rosinstall ]; then
    echo "- git: {local-name: $DOWNSTREAM_REPO_NAME, uri: 'http://github.com/$TRAVIS_REPO_SLUG'}" >> .rosinstall
fi

travis_time_end  # setup_rosws

travis_time_start before_script

## BEGIN: travis' before_script:
# Use this to prepare your build for testing e.g. copy database configurations, environment variables, etc.
source /opt/ros/$ROS_DISTRO/setup.bash # re-source setup.bash for setting environmet vairable for package installed via rosdep
if [ "${BEFORE_SCRIPT// }" != "" ]; then sh -c "${BEFORE_SCRIPT}"; fi

travis_time_end  # before_script

travis_time_start rosdep_install

# Run "rosdep install" command. Avoid manifest.xml files if any.
if [ -e ${CI_SOURCE_PATH}/$CI_PARENT_DIR/rosdep-install.sh ]; then
    ${CI_SOURCE_PATH}/$CI_PARENT_DIR/rosdep-install.sh
fi

travis_time_end  # rosdep_install

# Start prerelease, and once it finishes then finish this script too.
# This block needs to be here (i.e. After rosdep is done) because catkin_test_results isn't available until up to this point.
travis_time_start prerelease_from_travis_sh
if [ "$PRERELEASE" == true ] && [ -e ${CI_SOURCE_PATH}/$CI_PARENT_DIR/ros_pre-release.sh ]; then
  source ${CI_SOURCE_PATH}/${CI_PARENT_DIR}/ros_pre-release.sh && run_ros_prerelease
  retval_prerelease=$?
  if [ $retval_prerelease -eq 0 ]; then HIT_ENDOFSCRIPT=true; success 0; else error; fi  # Internally called travis_time_end for prerelease_from_travis_sh
  # With Prerelease option, we want to stop here without running the rest of the code.
fi

travis_time_start catkin_build

## BEGIN: travis' script: # All commands must exit with code 0 on success. Anything else is considered failure.
source /opt/ros/$ROS_DISTRO/setup.bash # re-source setup.bash for setting environmet vairable for package installed via rosdep

# for catkin
if [ "${_TARGET_PKGS// }" == "" ]; then export _TARGET_PKGS=`catkin_topological_order ${CI_SOURCE_PATH} --only-names`; fi  # `_TARGET_PKGS` (default: not set): If not set, the packages in the output of `catkin_topological_order` from the source space of your repo are to be set. This is also used to fill `PKGS_DOWNSTREAM` if it is not set.
if [ "${_PKGS_DOWNSTREAM// }" == "" ]; then export _PKGS_DOWNSTREAM=$( [ "${BUILD_PKGS_WHITELIST// }" == "" ] && echo "$_TARGET_PKGS" || echo "$BUILD_PKGS_WHITELIST"); fi
catkin config --install
catkin build --interleave-ouput --limit-status-rate 0.01 $BUILD_PKGS_WHITELIST $CATKIN_PARALLEL_JOBS --make-args $ROS_PARALLEL_JOBS

travis_time_end  # catkin_build

if [ "$NOT_TEST_BUILD" != "true" ]; then
    travis_time_start catkin_run_tests

    source devel/setup.bash ;
    rospack profile # force to update ROS_PACKAGE_PATH for rostest
    catkin run_tests --no-deps --no-status $_PKGS_DOWNSTREAM $CATKIN_PARALLEL_TEST_JOBS --make-args $ROS_PARALLEL_TEST_JOBS --
    catkin_test_results build || error

    travis_time_end  # catkin_run_tests
fi

travis_time_start after_script

## BEGIN: travis' after_script
PATH=/usr/local/bin:$PATH  # for installed catkin_test_results
PYTHONPATH=/usr/local/lib/python2.7/dist-packages:$PYTHONPATH
if [ "${ROS_LOG_DIR// }" == "" ]; then export ROS_LOG_DIR=~/.ros/test_results; fi # http://wiki.ros.org/ROS/EnvironmentVariables#ROS_LOG_DIR
if [ -e $ROS_LOG_DIR ]; then
    catkin_test_results --verbose --all $ROS_LOG_DIR || error;
fi
if [ -e ~/ros/ws_$DOWNSTREAM_REPO_NAME/build/ ]; then
    catkin_test_results --verbose --all ~/ros/ws_$DOWNSTREAM_REPO_NAME/build/ || error;
fi
if [ -e ~/.ros/test_results/ ]; then
    catkin_test_results --verbose --all ~/.ros/test_results/ || error;
fi

travis_time_end  # after_script

cd $TRAVIS_BUILD_DIR  # cd back to the repository's home directory with travis
pwd

HIT_ENDOFSCRIPT=true
success 0
