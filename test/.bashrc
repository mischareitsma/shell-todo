#!/bin/bash
alias todo="\${HOME}/todo.sh"

alias vi="fn_vi"

# vi on Alpine has limited functionality. This translates the +line
# command to the alpine compatible one.
fn_vi() {
    echo "Running vi function with '${1}' and '${2}'"
    file="${1}"
    line="${2:1}"
    echo "File: ${file}, line: ${line}"
    if [[ -z "${line}" ]]; then
        \vi "${file}"
    else
        \vi -c ":${line}" "${file}"
    fi
}
