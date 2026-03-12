#!/bin/bash
# Wrapper script to run opencode with unbuffered output

exec stdbuf -oL -eL "$@"