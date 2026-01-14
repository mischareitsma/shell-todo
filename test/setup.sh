#!/bin/bash
declare -r TODO_DIR="${HOME}/.todo"
mkdir "${TODO_DIR}"
mkdir "${TODO_DIR}/inbox"
echo "0" > "${TODO_DIR}/inbox.seq"
echo "description: generic todo inbox" > "${TODO_DIR}/inbox.info"

