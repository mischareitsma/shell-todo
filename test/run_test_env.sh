#!/usr/bin/env bash

err() {
	echo "${1}" >& 2
	exit "${2:-1}"
}

# Sub-shell for easy going back to original dir
(
	cd "$(dirname "${0}")" || err "Failed to change dir"
	cp ../todo.sh todo_docker_add.sh
	docker build -t shell-todo-test:latest .
	docker run --rm -ti --user todo --name shell-todo-test shell-todo-test:latest bash
	docker rmi shell-todo-test:latest
	rm todo_docker_add.sh
)
