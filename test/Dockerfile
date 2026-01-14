FROM fedora:latest

RUN dnf update -y && dnf install -y bash vim
RUN useradd -ms/bin/bash todo
USER todo
ADD --chown=todo:todo setup.sh /home/todo
ADD --chown=todo:todo todo_docker_add.sh /home/todo/todo.sh
ADD --chown=todo:todo .bashrc /home/todo
RUN /home/todo/setup.sh
WORKDIR /home/todo
