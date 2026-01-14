#!/usr/bin/env bash
# Simple todo CLI app main script. Check usage text for usage.

# --- Debug and error stuff ---

if [[ "${TODO_DEBUG_TRACE}" -eq 1 ]]; then
	set -x
fi

debug()
{
	[[ "${TODO_DEBUG}" -eq 1 ]] && echo "debug: ${1}" >& 2
}

err()
{
	echo "error: ${1}" >& 2
	exit "${2:-1}"
}

# global vars
TODO_PROG_NAME=$(basename "${0}")
declare -r TODO_PROG_NAME

TODO_PROG_DIR=$(realpath "$(dirname "${0}")")
declare -r TODO_PROG_DIR

declare -r TODO_DIR="${TODO_DIR:-${HOME}/.todo}"
declare -r TODO_ARCHIVE_DIR="${TODO_DIR}/archive"

declare -r TODO_DEFAULT_PROJECT="inbox"

declare -ri TODO_FORMAT_VERSION=1
declare -r TODO_APP_VERSION="0.0.1"

# TODO: (Mischa Reitsma, 2026-01-13) Support more editors? Right now only vi
# is supported. This is also apparent in the comman line args (like +n to
# start editing on line n)
declare -r TODO_EDITOR="vi"

# --- usage: Usage functions and texts ---

TODO_USAGE_TEXT_MAIN="Usage: ${TODO_PROG_NAME} <command>

Simple command line todo tool.

The commands that are supported:
  - add: Add a new todo item.
  - project: Project maintenance.
"

TODO_USAGE_TEXT_ADD="Usage: ${TODO_PROG_NAME} add [-p project] [-eh] text

Text should be 50 chars. If more, it is cut off and the text will also be the
start of the main text.

Options:
  -p: The project in which to add the todo.
  -e: Edit the todo to add more info.
  -h: Display this help message
"

TODO_USAGE_TEXT_PROJECT="Usage: ${TODO_PROG_NAME} project subcommand [options]

The project command is used to maintain todo projects. The command requires a
sub command with additional options.

The following subcommands are available:
  - h/help: Displays this help menu
  - a/add: Create a new project
  - e/edit: Edit a project
  - d/delete: Delete a project
"

usage()
{
	debug "usage(): ${*}"
		
	usage_text_name="${1:-main}"

	if [[ -n "${2}" ]]; then
	echo "${2}"
	fi

	case "${usage_text_name}" in
		"main")
			echo "${TODO_USAGE_TEXT_MAIN}"
			;;
		"add")
			echo "${TODO_USAGE_TEXT_ADD}"
			;;
		"project")
			echo "${TODO_USAGE_TEXT_PROJECT}"
			;;
		*)
			err "Invalid usage name: ${usage_text_name}" 1
			;;
	esac

	exit "${3:-0}"
}

# --- utility: Utility functions ---

# Append $1 to TODO_DIR and echo.
todo_path()
{
	debug "todo_path() ${1}"
	echo "${TODO_DIR}/${1}"
}

# --- add: Adding todos ---

add()
{
	debug "add() ${*}"
	if [[ $# -eq 0 ]]; then
		usage "add" "Missing required todo information for add command"
	fi

	if [[ "${1}" == "help" || "${1}" == "h" ]]; then
		usage "add"
	fi

	project="${TODO_DEFAULT_PROJECT}"
	declare -i edit_mode=0

	cli="${1}"

	while [[ "${cli}" =~ -.* ]]; do
		shift
			case "${cli}" in
				"-p")
					project="${1}"
					[[ -z "${project}"  || "${project}" =~ -.* ]] && usage "add" "Project flag -p requires valid project name" 1
					shift
					;;
				"-e")
					edit_mode=1
					;;
			esac
		cli="${1}"
	done

	validate_project "${project}"
	add_todo "${project}" "${edit_mode}" "${*}"
}

add_todo()
{
	debug "add_todo() ${*}"
	project="${1}"
	seq_file="$(todo_path "${project}.seq")"
	seq=$(cat "${seq_file}")

	edit_mode="${2}"
	shift 2

	declare -r todo_file=$(todo_path "${project}/${seq}.todo")

	text="${*}"

	cat <<-EOF > "${todo_file}"
		version: ${TODO_FORMAT_VERSION}
		date: $(date -I)
		time: $(date +%R:%S)
		status: todo
		desc: ${text:0:50}
	EOF

	# Increment and saving of sequence number is done as soon as the
	# previous here-document command is done. In theory one can add a todo
	# in edit mode in one terminal, and not close the editor and add another
	# todo in a second terminal. If the increment and saving of the new
	# number is done at the end of this function the second todo would
	# override the first one.
	((++seq)) && echo "${seq}" > "${seq_file}"

	declare -ri text_size="${#text}"
	declare -i line=5

	if [[ "${#text}" -gt 50 ]]; then
		declare -i i=0
		echo "" >> "${todo_file}"
		((line++))
		while [[ $i -lt $text_size ]]; do
			echo "${text:i:80}" >> "${todo_file}"
			((i+=80))
			((line++))
		done
	fi
	if [[ "${edit_mode}" -eq 1 ]]; then
		debug "add_todo(): edit mode line: ${line}"
		if [[ "${line}" -eq 5 ]]; then
			printf "\n\n" >> "${todo_file}"
			((line+=2))
		fi

		"${TODO_EDITOR}" "${todo_file}" "+${line}"
	fi
}

# --- project: Project related functions ---
project()
{
	subcommand="${1}"
	shift

	if [[
		-z "${subcommand}" ||
		"${subcommand}" == "help" ||
		"${subcommand}" == "h"
	]]; then
		usage "project"
	fi

	case "${subcommand}" in
		"a"|"add")
			project_add "${@}"
			;;
		"e"|"edit")
			project_edit "${@}"
			;;
		"d"|"delete")
			project_delete "${@}"
			;;
		*)
			usage "project" "invalid subcommand ${subcommand}" 1
			;;
	esac
}

project_add()
{
	declare -r project="${1}"

	if [[ -f $(todo_path "${project}.info") ]]; then
		err "Project info file ${project}.info already exists" 1
	fi

	if [[ -f $(todo_path "${project}.seq") ]]; then
		err "Project sequence file ${project}.seq already exists" 2
	fi

	if [[ -d $(todo_path "${project}") ]]; then
		err "Project todo directory ${project} already exists" 3
	fi

	echo "0" > "${TODO_DIR}/${project}.seq"
	mkdir "${TODO_DIR}/${project}/"

	touch "${TODO_DIR}/${project}.info"
	"${TODO_EDITOR}" "${TODO_DIR}/${project}.info"
}

project_edit()
{
	declare -r project="${1}"

	validate_project "${project}"

	# TODO: (Mischa Reitsma, 2026-01-13) Support more editors?
	"${TODO_EDITOR}" "${TODO_DIR}/${project}.info"
}

project_delete()
{
	declare -r project="${1}"

	# If not valid project a manual delete is required
	validate_project "${project}"

	tar -cz -f "${TODO_ARCHIVE_DIR}/${project}.tar.gz" -C "${TODO_DIR}" "${project}."{seq,info} "${project}/"
	rm "${TODO_DIR}/${project}".{seq,info}
	rm -r "${TODO_DIR:?}/${project}/"
}

validate_project()
{
	declare -r project="${1}"

	# Files with data and sequence should exist
	if [[ ! -f $(todo_path "${project}.info") ]]; then
		err "Project info file ${project}.info does not exist" 1
	fi

	if [[ ! -f $(todo_path "${project}.seq") ]]; then
		err "Project sequence file ${project}.seq does not exist" 2
	fi

	if [[ ! -d $(todo_path "${project}") ]]; then
		err "Project todo directory ${project} does not exist" 3
	fi
}

# --- main: Main entrypoint of the shell-todo app ---
main()
{
	debug "TODO_PROG_NAME: ${TODO_PROG_NAME}"
	debug "TODO_PROG_DIR: ${TODO_PROG_DIR}"
	debug "TODO_DIR: ${TODO_DIR}"
	debug "TODO_ARCHIVE_DIR: ${TODO_ARCHIVE_DIR}"
	debug "TODO_DEFAULT_PROJECT: ${TODO_DEFAULT_PROJECT}"
	debug "TODO_FORMAT_VERSION: ${TODO_FORMAT_VERSION}"
	debug "TODO_APP_VERSION: ${TODO_APP_VERSION}"
	debug "Command line args: ${*}"

	if [[ $# -eq 0 ]]; then
	usage "main" "Missing required argument: command" 1
	fi

	command="${1}"
	shift

	case "${command}" in
		"a"|"add")
			add "${@}"
			;;
		"p"|"project")
			project "${@}"
			;;
		"-h"|"h"|"help"|"--help")
			usage
			;;
		*)
			usage "main" "Unsupported command ${command}" 1
			;;
	esac
}

main "${@}"
