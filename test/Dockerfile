FROM fedora:latest

RUN dnf update -y && dnf install -y bash vim
RUN useradd -ms/bin/bash todo
USER todo
ADD --chown=todo:todo *.sh /home/todo
ADD --chown=todo:todo .bashrc /home/todo
RUN /home/todo/setup.sh
WORKDIR /home/todo
