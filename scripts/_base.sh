#!/bin/bash
# this should besourced!
#
# Color definitions (using tput for better compatibility)
if [ -t 1 ]; then
  # Only define colors if output is a terminal
  b=$(tput bold); d=$(tput dim); i=$(tput sitm); rst=$(tput sgr0); u=$(tput smul); nu=$(tput rmul)
  red=$(tput setaf 1); green=$(tput setaf 2); yellow=$(tput setaf 3); blue=$(tput setaf 4); 
  cyan=$(tput setaf 6); magenta=$(tput setaf 5); white=$(tput setaf 7)
else
  # No colors if not a terminal
  b=""; rst=""; d=""; u=""; nu=""
  red=""; green=""; yellow=""; blue=""; cyan=""; magenta=""; white=""
fi

# Helper function for easier color usage
s() {
  local color=$1
  shift
  echo -n "${!color}$*${rst}"
}
style() {
  local color=$1
  shift
  echo -n "${!color}$*${rst}"
}
debug() {
    echo "${d}$1${rst}"
}
title() {
    echo "${b}${blue}==>${rst} ${b}${green}$1${rst}"
}
section() {
    echo " ${blue}=>${rst} ${green}$1${rst}"
}
info() {
    echo "$1"
}
warn() {
    echo "${yellow}$1${rst}"
}
error() {
    echo "${red}$1${rst}"
}
success() {
    echo "${b}${green}$1${rst}"
}
