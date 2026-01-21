#!/usr/bin/env bash
# Simple todo CLI app main script. Check usage text for usage.

# TODO: (Mischa Reitsma, 2026-01-18) Implement project_xyz vars that are
# global and can be loaded with a function. These can then be used in
# functions. Be careful not to do validations in case we are in create project
# mode.

# TODO: (Mischa Reitsma, 2026-01-18) Enhance delete to archive first, delete
# later. This also comes with a restructure of the todo files and dir. Idea is
# that the project is a dir, inside is the info and seq file and a todo dir and
# a archive dir. The todo dir has the todos (with extension still, clearer when
# running find commands etc.), the archive dir the delete todos. The archive
# number system is different from the normal todo number system, just

# TODO: (Mischa Reitsma, 2026-01-18) There is a mix of err and usage. Need to
# determine when err applies and when usage applied. The difference should be
# easy: missing input is usage, enough input but invalid input is err.

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

# Used for printing, 80 dashes
TODO_LINE="$(printf "%0.1s" "-"{0..80})"
declare -r TODO_LINE

# Valid states
declare -r TODO_STATES="todo doing done"

# --------------------------------------------
# project variables: set project variables ---
# --------------------------------------------

# The name of the project, a simple string
declare project_name=""

# The path where all files and directories of a project are stored
declare project_path=""

# Path where the todo files of a project are stored
declare project_todo_path=""

# Path where the deleted todos are stored for final deletion
declare project_archive_path=""

# Path of the sequence file of a project
declare project_seq_file=""

# Path of the information file of a project
declare project_info_file=""

load_project_vars() {
	project_name="${1}"
	declare -i skip_validate="${2:-0}" # Default to not skip validations.

	project_path="$(todo_path "${project_name}")"
	project_todo_path="${project_path?}/todo"
	project_archive_path="${project_path?}/archive"
	project_seq_file="${project_path?}/${project_name}.seq"
	project_info_file="${project_path?}/${project_name}.info"

	[[ "${skip_validate}" -eq 0 ]] && validate_project

	debug "project_name: ${project_name}"
	debug "project_path: ${project_path}"
	debug "project_todo_path: ${project_todo_path}"
	debug "project_archive_path: ${project_archive_path}"
	debug "project_seq_file: ${project_seq_file}"
	debug "project_info_file: ${project_info_file}"
}

validate_project()
{
	# Files with data and sequence should exist
	if [[ ! -f ${project_info_file} ]]; then
		err "Project info file ${project_info_file} does not exist" 1
	fi

	if [[ ! -f "${project_seq_file}" ]]; then
		err "Project sequence file ${project_seq_file} does not exist" 2
	fi

	if [[ ! -d "${project_todo_path}" ]]; then
		err "Project todo directory ${project_todo_path} does not exist" 3
	fi

	if [[ ! -d "${project_archive_path}" ]]; then
		err "Project archive directory ${project_archive_path} does not exist" 4
	fi
}


# ----------------------------------
# --- utility: Utility functions ---
# ----------------------------------

# Append $1 to TODO_DIR and echo.
todo_path()
{
	debug "todo_path() ${1}"
	echo "${TODO_DIR}/${1}"
}

# -------------------------
# --- add: Adding todos ---
# -------------------------
TODO_USAGE_TEXT_ADD="Usage: ${TODO_PROG_NAME} add [-p project] [-eh] text

Text should be 50 chars. If more, it is cut off and the text will also be the
start of the main text.

Options:
  -p: The project in which to add the todo.
  -e: Edit the todo to add more info.
  -h: Display this help message
"

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
			"-h")
				usage "add"
				;;
		esac
		cli="${1}"
	done

	load_project_vars "${project}"
	_add_todo "${edit_mode}" "${*}"
}

_add_todo()
{
	debug "_add_todo() ${*}"
	
	seq=$(cat "${project_seq_file}")

	edit_mode="${1}"
	shift 1

	declare -r todo_file=$(todo_path "${project_todo_path}/${seq}.todo")

	text="${*}"

	cat <<-EOF > "${todo_file}"
		version: ${TODO_FORMAT_VERSION}
		date: $(date -I)
		time: $(date +%R:%S)
		state: todo
		description: ${text:0:50}
	EOF

	# Increment and saving of sequence number is done as soon as the
	# previous here-document command is done. In theory one can add a todo
	# in edit mode in one terminal, and not close the editor and add another
	# todo in a second terminal. If the increment and saving of the new
	# number is done at the end of this function the second todo would
	# override the first one.
	((++seq)) && echo "${seq}" > "${project_seq_file}"

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
		debug "_add_todo(): edit mode line: ${line}"
		if [[ "${line}" -eq 5 ]]; then
			printf "\n\n" >> "${todo_file}"
			((line+=2))
		fi

		"${TODO_EDITOR}" "${todo_file}" "+${line}"
	fi
}

# ---------------------------------------
# --- details: Print details of todos ---
# ---------------------------------------
TODO_USAGE_TEXT_DETAILS="Usage: ${TODO_PROG_NAME} details [project [todo]]

List the details of todos. There are two optional positional parameters:

  - project: The project to print.
  - todo: Single todo in a project to print.
"

details()
{
	debug "details(): ${*}"

	if [[ -z "${1}" ]]; then
		_details_all_projects
	else
		_details_project "${1}" "${2}"
	fi
}

_details_all_projects()
{
	# Use sequence files to figure out which are valid todo projects. Cannot
	# guarantee that there will not be more .info files later.
	echo "${TODO_LINE}"
	for project in $(project_all_names); do
		_details_project "${project}"
		echo "${TODO_LINE}"
	done
}

_details_project()
{
	debug "_details_project() ${*}"
	load_project_vars "${1}"
	declare -ri todo_number="${2:--1}"

	if [[ ${todo_number} -ne -1 ]]; then
		declare -r todo_file="${project_todo_path}/${todo_number}.todo"
		if [[ ! -f "${project_todo_path}/${todo_number}.todo" ]]; then
			err "todo ${todo_number} for project ${project_name} does not exist" 1
		fi
		echo "Project ${project_name} todo ${todo_number}:"
		grep "description:" "${todo_file}"
		grep "state:" "${todo_file}"
	else
		echo "Project ${project_name}:"
		grep -v -e '^$' "${project_info_file}"
		for todo_file in "${project_todo_path}/"*.todo; do
			debug "Printing todo file ${todo_file}"
			n="${todo_file##*/}"
			n="${n%%.*}"
			if [[ "${n}" == "*" ]]; then
				continue
			fi
			echo ""
			echo "Project ${project_name} todo ${n}:"
			grep "description:" "${todo_file}"
			grep "state:" "${todo_file}"
		done
	fi
}


# -----------------------
# ---list: List todos ---
# -----------------------
TODO_USAGE_TEXT_LIST="Usage: ${TODO_PROG_NAME} list [-p project] [-s state] [-h]

List all todos. Filter todos using the following options:
  -h: Display this help
  -p: Filter on project. By default displays all options.
  -s: Filter on state. By default displays all states.
"

list()
{
	declare projects=""
	declare filter_state=""

	# Could do getopts, but doing this while case shift thing now everywhere
	# anyway.
	cli="${1}"

	while [[ "${cli}" =~ -.* ]]; do
		shift
		case "${cli}" in
			"-p")
				project="${1}"
				[[ -z "${projects}"  || "${projects}" =~ -.* ]] && usage "add" "Project flag -p requires valid project name" 1
				shift
				;;
			"-s")
				filter_state="${1}"
				if ! echo "${TODO_STATES}" | grep -qw "${filter_state}"; then
					err "Invalid state ${filter_state}, valid states: ${TODO_STATES}"
				fi
				shift
				;;
			"-h")
				usage "list"
		esac
		cli="${1}"
	done

	if [[ -z "${projects}" ]]; then
		projects=$(project_all_names)
	fi

	for project in ${projects}; do
		# TODO: (Mischa Reitsma, 2026-01-17) Should be able to fetch all
		# the TODOs in a list using a function
		load_project_vars "${project}"
		while read -r todo_path; do
			state=$(grep "state:" "${todo_path}" | cut -d":" -f2 | awk '{$1=$1};1')
			if [[ -n "${filter_state}" && "${state}" != "${filter_state}" ]]; then
				continue
			fi
			description=$(grep "description:" "${todo_path}" | cut -d":" -f2 | awk '{$1=$1};1')
			n="$(basename "${todo_path}")"
			n=${n%%.*}
			printf "| %-8s | %3d | %-5s | %-50s |\n" "${project_name}" "${n}" "${state}" "${description}"
		done < <(find "${project_todo_path}" -name "*.todo" -exec echo {} \;)
	done
}

# ------------------------------------------
# --- project: Project related functions ---
# ------------------------------------------

TODO_USAGE_TEXT_PROJECT="Usage: ${TODO_PROG_NAME} project subcommand [project_name]

The project command is used to maintain todo projects. The command requires a
sub command with additional options.

The following subcommands are available:
  - h/help: Displays this help menu
  - a/add: Create a new project
  - e/edit: Edit a project
  - d/delete: Delete a project
"

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
	load_project_vars "${1}" 1

	if [[ -f "${project_info_file}" ]]; then
		err "Project info file already exists" 1
	fi

	if [[ -f "${project_seq_file}" ]]; then
		err "Project sequence file already exists" 2
	fi

	if [[ -d "${project_todo_path}" ]]; then
		err "Project todo directory already exists" 3
	fi

	if [[ -d "${project_archive_path}" ]]; then
		err "Project todo directory already exists" 3
	fi

	mkdir -p "${project_path}"
	mkdir "${project_todo_path}"
	mkdir "${project_archive_path}"

	echo "0" > "${project_seq_file}"

	echo "description: " > "${project_info_file}"
	"${TODO_EDITOR}" "${project_info_file}"
}

project_edit()
{
	load_project_vars "${1}"

	"${TODO_EDITOR}" "${project_info_file}"
}

project_delete()
{
	load_project_vars "${1}"

	tar -cz -f "${TODO_ARCHIVE_DIR}/${project}.tar.gz" -C "${TODO_DIR}" "${project_path}"
	rm -r "${project_path}"
}

project_all_names()
{
	find "${TODO_DIR}" -name "**/*.seq" -exec basename {} \; | cut -d'.' -f1 | tr "\n" " "
}

# --- edit: Edit todos
declare -r TODO_USAGE_TEXT_EDIT="${TODO_PROG_DIR} edit [-p project] [-s state] number

Edit a todo. The positional parameter is the todo number to edit, and has to
be the last argument in the list. The following optional arguments affect how
the todo is edited:

  -p: Edit todo in a particular project. Use default project if not passed.
  -s: Update state only to the state passed to this option.
"

edit()
{
	# TODO: (Mischa Reitsma, 2026-01-18) Again arg parsing like this, some
	# are same. Really need to see how to generalize this.
	cli="${1}"
	shift

	declare project="${TODO_DEFAULT_PROJECT}"
	declare state=""

	while [[ "${cli}" =~ -.* ]]; do
		case "${cli}" in
			"-p")
				project="${1}"
				[[ -z "${projects}"  || "${projects}" =~ -.* ]] && usage "edit" "Project flag -p requires valid project name" 1
				shift
				;;
			"-s")
				state="${1}"
				[[ -z "${state}" || "${state}" =~ -.* ]] && usage "edit" "State flag -s requires a value"
				if ! echo "${TODO_STATES}" | grep -qw "${state}"; then
					usage "edit" "Invalid state ${state}, valid states: ${TODO_STATES}" 2
				fi
		esac
		shift
		cli="${1}"
	done

	# TODO: (Mischa Reitsma, 2026-01-18) This style or if [[ ]]; then ...; fi?
	[[ -z "${cli}" ]] && usage "edit" "missing todo number to edit" 3

	load_project_vars "${project}"

	# Do not declare as number, as it could default to 0 unintentionally
	declare n="${cli}"

	todo_path="${project_todo_path}/${n}.todo"

	[[ ! -f "${todo_path}" ]] && usage "edit" "Invalid todo ${n}" 4

	if [[ -n "${state}" ]]; then
		declare -r curr_state="$(grep "^state:" "${todo_path}")"
		sed -i -e "s/${curr_state}/state: ${state}/" "${todo_path}"
	else
		"${TODO_EDITOR}" "${todo_path}"
	fi
}

# --------------------------------------------
# --- delete: Delete a todo from a project ---
# --------------------------------------------
declare -r TODO_USAGE_TEXT_DELETE="Usage: ${TODO_PROG_NAME} delete [-p project] todo_number

Delete a todo from a project. The last parameter is the todo number to delete.
An optional -p flag can be used to determine from which project to delete the
todo:
  -p: Project to delete the todo from. If not passed delete from the default
      project.
"

delete()
{
	declare project="${TODO_DEFAULT_PROJECT}"
	if [[ "${1}" == "-p" ]]; then
		project="${2}"
		if [[ -z "${project}" ]]; then
			err "Cannot delete: invalid project passed with the -p flag" 1
		fi

		shift 2
	fi

	load_project_vars

	# Do not declare as integer, as it could default to 0 for non-numeric
	# input and by accident delete todo number 0.
	declare -r todo_number="${1}"

	if [[ ! -f "${project_todo_path?}/${todo_number}.todo" ]]; then
		err "Cannot delete: todo ${todo_number} does not exist" 2
	fi

	rm "${project_todo_path?}/${todo_number}.todo"
}

# -------------------------------------------------------------
# --- move: Move a todo from one project to another project ---
# -------------------------------------------------------------
declare -r TODO_USAGE_TEXT_MOVE="Usage: ${TODO_PROG_NAME} move [from_project] to_project todo_number

Move a todo from one project to another. If three arguments are passed then
the arguments are interpreted as:

  - Project from which to move the todo.
  - Project to which to move the todo.
  - The todo number in the project.

When two arguments are passed, the from_project is set to the default project.
"

move()
{
	declare from_project="${TODO_DEFAULT_PROJECT}"
	declare to_project=""
	declare todo_number=""
	
	if [[ "${#}" -eq 3 ]]; then
		from_project="${1}"
		to_project="${2}"
		todo_number="${3}"
	elif [[ "${#}" -eq 2 ]]; then
		to_project="${1}"
		todo_number="${2}"
	else
		usage "move" "Invalid number of arguments"
	fi

	load_project_vars "${from_project}"

	declare -r todo_to_move="${project_todo_path}/${todo_number}.todo"

	if [[ ! -f "${todo_to_move}" ]]; then
		err "Cannot move todo, todo ${todo_number} does not exist" 1
	fi

	load_project_vars "${to_project}"
	seq="$(cat "${project_seq_file}")"

	mv "${todo_to_move}" "${project_todo_path?}/${seq}.todo"
	((++seq)) && echo "${seq}" > "${project_seq_file}"
}

# --- usage: Main usage test and usage functions
declare -r TODO_USAGE_TEXT_MAIN="Usage: ${TODO_PROG_NAME} <command>

Simple command line todo tool.

The commands that are supported:
  - a/add: Add a new todo item.
  - p/project: Project maintenance.
  - l/list: List todos.
  - details: Print details of todos.
  - e/delete: Delete a todo.
  - e/edit: Edit a todo.
  - h/help: Display this help text.
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
		"list")
			echo "${TODO_USAGE_TEXT_LIST}"
			;;
		"details")
			echo "${TODO_USAGE_TEXT_DETAILS}"
			;;
		"edit")
			echo "${TODO_USAGE_TEXT_EDIT}"
			;;
		"delete")
			echo "${TODO_USAGE_TEXT_DELETE}"
			;;
		"move")
			echo "${TODO_USAGE_TEXT_MOVE}"
			;;
		"clean")
			echo "${TODO_USAGE_TEXT_CLEAN}"
			;;
		*)
			err "Invalid usage name: ${usage_text_name}" 1
			;;
	esac

	exit "${3:-0}"
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

	# TODO: (Mischa Reitsma, 2026-01-17) Some of these subcommand names are terrible or should be merged!
	case "${command}" in
		"a"|"add")
			add "${@}"
			;;
		"p"|"project")
			project "${@}"
			;;
		"l"|"list")
			list "${@}"
			;;
		"details")
			details "${@}"
			;;
		"d"|"delete")
			delete "${@}"
			;;
		"e"|"edit")
			edit "${@}"
			;;
		"m"|"move")
			move "${@}"
			;;
		"h"|"help")
			usage
			;;
		*)
			usage "main" "Unsupported command ${command}" 1
			;;
	esac
}

main "${@}"
