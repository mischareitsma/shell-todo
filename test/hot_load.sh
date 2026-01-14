#!/usr/bin/env bash

declare -r CONTAINER_NAME="shell-todo-test"
TEST_PATH="$(realpath "$(dirname ${0})")"
declare -r TEST_PATH

docker cp "${TEST_PATH}/../todo.sh" "${CONTAINER_NAME}:/home/todo"
docker exec --user root --tty "${CONTAINER_NAME}" bash -c "chown todo:todo /home/todo/todo.sh"
