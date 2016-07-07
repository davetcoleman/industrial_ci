#!/bin/bash

# Originally developed in JSK travis package https://github.com/jsk-ros-pkg/jsk_travis

# Software License Agreement (BSD License)
#
# Copyright (c) 2016, Isaac I. Y. Saito
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

## util.sh
## This is a script where the functions commonly used within the industrial_ci repo are defined.

function travis_time_start {
    TRAVIS_START_TIME=$(date +%s%N)
    TRAVIS_TIME_ID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
    TRAVIS_FOLD_NAME=$1
    #echo -e "\e[0Ktravis_fold:start:$TRAVIS_FOLD_NAME \e[34m>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\e[0m"
    echo -e "\e[0K$TRAVIS_FOLD_NAME \e[34m>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\e[0m"
}

#######################################
# Wraps up the timer section on Travis CI (that's started mostly by travis_time_start function).
#
# Globals:
#   (None)
# Arguments:
#   color_wrap (default: 32): Color code for the section delimitter text.
# Returns:
#   (None)
#######################################
function travis_time_end {
    color_wrap=${2:-32}

    if [ -z $TRAVIS_START_TIME ]; then echo '[travis_time_end] var TRAVIS_START_TIME is not set. You need to call `travis_time_start` in advance. Returning.'; return; fi
    TRAVIS_END_TIME=$(date +%s%N)
    TIME_ELAPSED_SECONDS=$(( ($TRAVIS_END_TIME - $TRAVIS_START_TIME)/1000000000 ))
    echo -e "travis_time:end:$TRAVIS_TIME_ID:start=$TRAVIS_START_TIME,finish=$TRAVIS_END_TIME,duration=$(($TRAVIS_END_TIME - $TRAVIS_START_TIME))\e[0K"
    #echo -e "travis_fold:end:$TRAVIS_FOLD_NAME\e[${color_wrap}m<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\e[0m"
    echo -e "$TRAVIS_FOLD_NAME\e[${color_wrap}m<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\e[0m"
    echo -e "\e[0K\e[${color_wrap}mFunction $TRAVIS_FOLD_NAME took $(( $TIME_ELAPSED_SECONDS / 60 )) min $(( $TIME_ELAPSED_SECONDS % 60 )) sec\e[0m"

    unset $TRAVIS_FOLD_NAME
}

#######################################
# This private function can exit the shell process, as well as wrapping up the timer section on Travis CI. Internally this does:
#
# * wraps the section that is started by travis_time_start function.
# * resets signal handler for ERR to the bash default one, when `exit_code` is any error code that exits the shell. This allows subsequent signal handlers for ERR if any to be unaffected by any handlers defined beforehand.
# * exits the process if non -1 value is passed to `exit_code`.
#######################################
function _end_fold_script {
    exit_code=${1:--1}  # If 1st arg is not passed, set -1.
    color_wrap=${2:-32}

    if [ $exit_code -eq "1" ]; then color_wrap=31; fi  # Red color
    if [ -z $TRAVIS_FOLD_NAME ]; then
        travis_time_end $color_wrap
    #else
	#echo "Previous Travis fold name not found. It might be either successful termination of the script, or wrong call. Skipping 'travis_time_end' anyway."
    fi

    if [ $exit_code -eq "1" ]; then trap - ERR; fi  # Reset signal handler since the shell is about to exit.
    if [ $exit_code -ne "-1" ]; then exit $exit_code; fi
}

#######################################
# This calls "exit 1", along with the following. When your script on Travis CI already uses other functions from this file (util.sh), using this is recommended over calling directly "exit 1".
#
# * wraps the section that is started by travis_time_start function with the echo color red (31).
# * reset signal handler for ERR to the bash default one. Subsequent signal handlers for ERR if any are unaffected by any handlers defined prior.
#
# Globals:
#   (None)
# Arguments:
#   (None)
# Returns:
#   (None)
#######################################
function errorFunction {
    _end_fold_script 1 31
}

#######################################
# Similar to `error` function, this lets you "exit 0" and take care of other things as following, when your script on Travis CI already uses other functions from this file (util.sh).
#
# * wraps the section that is started by travis_time_start function with the echo color green.
# * reset signal handler for ERR to the bash default one. Subsequent signal handlers for ERR if any are unaffected by any handlers defined prior.
#
# Globals:
#   (None)
# Arguments:
#   _exit_code (default: 0): Unix signal. If -1 passed then the process continues.
# Returns:
#   (None)
#######################################
function successFunction {
    _FUNC_MSG_PREFIX="[fuction success]"
    _exit_code=${1:-0}  # If 1st arg is not passed, set 0.
    HIT_ENDOFSCRIPT=${HIT_ENDOFSCRIPT:-false}
    if [ $HIT_ENDOFSCRIPT = false ]; then
	if [ $_exit_code -eq 0 ]; then
	    echo "${_FUNC_MSG_PREFIX} Arg HIT_ENDOFSCRIPT must be true when this function exit with 0. Turn _exit_code to 1."; _exit_code=1;
	else
	    echo "${_FUNC_MSG_PREFIX} _exit_code cannot be 0 for this func. Make sure you are calling this in a right context."; _exit_code=1;
	fi
    fi
    if [ $_exit_code -ne "-1" ] && [ $_exit_code -ne "0" ]; then echo "${_FUNC_MSG_PREFIX} error: arg _exit_code must be either empty, -1 or 0. Returning."; return; fi
    _end_fold_script $_exit_code
}

#######################################
export TRAVIS_FOLD_COUNTER=1
function travis_run() {
  local command=$@

  echo -e "\e[0Ktravis_fold:start:command$TRAVIS_FOLD_COUNTER \e[34m$command\e[0m"
  $command # actually run command
  #echo -e "travis_fold:end:travis_run"
  echo -e "\e[0Ktravis_fold:end:command$TRAVIS_FOLD_COUNTER \e[34m------\e[0m"

  let "TRAVIS_FOLD_COUNTER += 1"
}

#######################################
function my_travis_wait() {
  local timeout=$1

  if [[ $timeout =~ ^[0-9]+$ ]]; then
    # looks like an integer, so we assume it's a timeout
    shift
  else
    # default value
    timeout=20
  fi

  my_travis_wait_impl $timeout "$@"
}

#######################################
function my_travis_wait_impl() {
  local timeout=$1
  shift

  local cmd="$@"
  local log_file=my_travis_wait_$$.log

  $cmd 2>&1 >$log_file &
  local cmd_pid=$!

  my_travis_jigger $! $timeout $cmd &
  local jigger_pid=$!
  local result

  {
    wait $cmd_pid 2>/dev/null
    result=$?
    ps -p$jigger_pid 2>&1>/dev/null && kill $jigger_pid
  } || return 1

  echo -e "\nThe command \"$cmd\" exited with $result."
  echo -e "\n\033[32;1mLog:\033[0m\n"
  cat $log_file

  return $result
}

#######################################
function my_travis_jigger() {
  # helper method for travis_wait()
  local cmd_pid=$1
  shift
  local timeout=$1 # in minutes
  shift
  local count=0


  # clear the line
  echo -e "\n"

  while [ $count -lt $timeout ]; do
    count=$(($count + 1))
    echo -ne "Still running ($count of $timeout min): $@\r"
    sleep 60
  done

  echo -e "\n\033[31;1mTimeout (${timeout} minutes) reached. Terminating \"$@\"\033[0m\n"
  kill -9 $cmd_pid
}
