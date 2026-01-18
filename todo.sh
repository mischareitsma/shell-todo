#!/usr/bin/env bash
# Simple todo CLI app main script. Check usage text for usage.

# TODO: (Mischa Reitsma, 2026-01-18) There is a mix of err and usage. Need to
# determine when err applies and when usage applied. The difference should be
# easy: missing input is usage, enough input but invalid input is err.

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
declare -r TODO_LINE="$(printf "%0.1s" "-"{0..80})"

# Valid states
declare -r TODO_STATES="todo doing done"


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
		state: todo
		description: ${text:0:50}
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
	debug "list(): ${*}"
	project="${1}"

	if [[ -z "${project}" ]]; then
		details_all_projects
	else
		details_project "${project}" "${2}"
	fi
}

details_all_projects()
{
	# Use sequence files to figure out which are valid todo projects. Cannot
	# guarantee that there will not be more .info files later.
	echo "${TODO_LINE}"
	for project in $(project_all_names); do
		details_project "${project}"
		echo "${TODO_LINE}"
	done
}

details_project()
{
	declare -r project="${1}"
	declare -ri todo_number="${2:--1}"
	declare -r project_path="$(todo_path "${project}")"

	# TODO: (Mischa Reitsma, 2026-01-15) Complain (validate project) or just ignore? For now ignore.
	if [[ ! -d "${project_path}" ]]; then
		return
	fi

	if [[ ${todo_number} -ne -1 ]]; then
		declare -r todo_file="${project_path}/${todo_number}.todo"
		if [[ ! -f "${project_path}/${todo_number}.todo" ]]; then
			err "todo ${todo_number} for project ${project} does not exist" 1
		fi
		echo "Project ${project} todo ${todo_number}:"
		grep "description:" "${todo_file}"
		grep "state:" "${todo_file}"
	else
		echo "Project ${project}:"
		grep -v -e '^$' "$(todo_path "${project}.info")"
		for todo_file in "${project_path}/"*.todo; do
			debug "Printing todo file ${todo_file}"
			n="${todo_file##*/}"
			n="${n%%.*}"
			if [[ "${n}" == "*" ]]; then
				continue
			fi
			echo ""
			echo "Project ${project} todo ${n}:"
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

	if [[ -z "${project}" ]]; then
		projects=$(project_all_names)
	fi

	for project in ${projects}; do
		# TODO: (Mischa Reitsma, 2026-01-17) Sould be able to fetch all
		# the TODOs in a list using a function
		while read -r todo_path; do
			state=$(grep "state:" "${todo_path}" | cut -d":" -f2 | awk '{$1=$1};1')
			if [[ -n "${filter_state}" && "${state}" != "${filter_state}" ]]; then
				continue
			fi
			description=$(grep "description:" "${todo_path}" | cut -d":" -f2 | awk '{$1=$1};1')
			n="$(basename "${todo_path}")"
			n=${n%%.*}
			printf "| %-8s | %3d | %-5s | %-50s |\n" "${project}" "${n}" "${state}" "${description}"
		done < <(find "$(todo_path "${project}")" -name "*.todo" -exec echo {} \;)
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

	echo "description: " > "${TODO_DIR}/${project}.info"
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

project_all_names()
{
	find "${TODO_DIR}" -name "*.seq" -exec basename {} \; | cut -d'.' -f1 | tr "\n" " "
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

	# Do not declare as number, as it could default to 0 unintentionally
	declare n="${cli}"

	todo_path="$(todo_path "${project}")/${n}.todo"

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
		if [[ -z "${project}" || ! -d "$(todo_path "${project}")" ]]; then
			err "Cannot delete: invalid project passed with the -p flag" 1
		fi

		shift 2
	fi

	project_path="$(todo_path "${project}")"

	# Do not declare as integer, as it could default to 0 for non-numeric
	# input and by accident delete todo number 0.
	declare -r todo_number="${1}"

	if [[ ! -f "${project_path}/${todo_number}.todo" ]]; then
		err "Cannot delete: todo ${todo_number} does not exist" 2
	fi

	rm "${project_path?}/${todo_number}.todo"
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

	validate_project "${from_project}"
	validate_project "${to_project}"

	from_project_path="$(todo_path "${from_project}")"
	if [[ ! -f "${from_project_path}/${todo_number}.todo" ]]; then
		err "Cannot move todo, todo ${todo_number} does not exist" 1
	fi

	to_project_path="$(todo_path "${to_project}")"
	seq_file="$(todo_path "${to_project}.seq")"
	declare -i seq
	seq="$(cat "${seq_file}")"

	mv "${from_project_path?}/${todo_number}.todo" "${to_project_path?}/${seq}.todo"
	((++seq)) && echo "${seq}" > "${seq_file}"
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
