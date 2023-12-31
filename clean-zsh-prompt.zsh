#!/usr/bin/env zsh

#########################
# clean-zsh-prompt      #
# Author: JTriantafylos #
# Homepage: <TBD>       #
#########################

#######################
# GLOBALS & CONSTANTS #
#######################

# Source zsh-async
source ${0:a:h}/zsh-async/async.zsh

# The list that will hold the names of each module's associative array containing that module's parameters
declare -a CZP_PROMPT_MODULES=()

# An array that will contain the content of each prompt module, to be expanded in $prompt
declare -a CZP_PSVAR=()

# Required to allow for proper expansion of $CZP_PSVAR in $prompt
setopt promptsubst

# The string that will be printed out in front of where the shell input will actually show up
declare CZP_PROMPT_CHARACTER="❯ "

# The color that the prompt character will be displayed with if the last command completed with a return code of 0
declare CZP_PROMPT_CHARACTER_COLOR_SUCCESS="green"

# The color that the prompt character will be displayed with if the last command completed with a return code of anything but 0
declare CZP_PROMPT_CHARACTER_COLOR_FAIL="red"

# The string that will be placed between each prompt module
declare CZP_MODULE_SEPARATOR=" "

# Newline constant
declare -r CZP_NEWLINE=$'\n'

# Async worker name constant
declare -r CZP_WORKER_NAME="CZP_PROMPT_MODULE_WORKER"

# Module name prefix constant
declare -r CZP_MODULE_NAME_PREFIX="CZP_PROMPT_MODULE_"

#############
# FUNCTIONS #
#############

# __czp_print()
#
# Prints a message to stdout
#
# $1 <Message>: The message to be printed to stdout
#
function __czp_print() {
    print -- "${1}"
}

# __czp_print_styled()
#
# Prints a message to stdout, with prompt escape sequences expanded
#
# $1 <Message>: The message to be printed to stdout, optionally containing prompt escape sequences that will be expanded
#
function __czp_print_styled() {
    print -P -- "${1}"
}

# __czp_print_error()
#
# Prints a message to stderr
#
# $1 <Message>: The message to be printed to stderr
#
function __czp_print_error() {
    >&2 print -- "${1}"
}

# __czp_print_module()
#
# Prints a description of the passed module to stdout
#
# $1 <Module>: The name of an associative array representing a module (generally an element of $CZP_PROMPT_MODULES)
function __czp_print_module() {
    # Determine the module name, with the prefix removed
    local MODULE_NAME="${1#${CZP_MODULE_NAME_PREFIX}}"
    # Construct the module's associative array from the passed name
    local -A MODULE=("${(Pkv@)1}")
    # Get module keys in sorted order
    local -a MODULE_KEYS=("${(iPk@)1}")

    # Print the module's name bold and underlined
    __czp_print_styled "%U%B[${MODULE_NAME}]:%b%u"
    # Print each of the module's parameters
    for KEY in "${MODULE_KEYS[@]}"; do __czp_print "[${KEY}]=${MODULE[${KEY}]:-<empty>}"; done
}

# __czp_add_module()
#
# Adds a new module to CZP
#
# $* <Arguments>: Arguments to be passed into zparseopts, see $USAGE_MSG for more information
function __czp_add_module() {
    local -r USAGE_MSG="usage: czprompt add [<options>]

    -h, --help     prints this usage message
    --name         the name of the module
    --prefix       unstyled text that will be displayed before the module
    --suffix       unstyled text that will be displayed after the module
    --color        the color that the module's content will be displayed in
    -s, --shell    treat the --command input as a shell command rather than a Zsh prompt escape sequence
    --command      the Zsh prompt escape sequence, or shell command (depending on the --shell option), that will generate the module's content"

    # Option handling
    local -a HELP NAME PREFIX SUFFIX COLOR SHELL COMMAND
    if ! zparseopts -E -F -D -K -- {h,-help}=HELP -name:=NAME -prefix:=PREFIX -suffix:=SUFFIX -color:=COLOR {s,-shell}=SHELL -command:=COMMAND; then
        __czp_print "${USAGE_MSG}"
        return
    fi

    # Print usage message
    if [[ -n "${HELP}" ]]; then
        __czp_print "${USAGE_MSG}"
        return
    fi

    # Verify that a name was provided
    if [[ -z "${NAME[2]}" ]]; then
        __czp_print_error "error: --name argument is mandatory!"
        __czp_print_error "${USAGE_MSG}"
        return
    fi

    # Verify that a command was provided
    if [[ -z "${COMMAND[2]}" ]]; then
        __czp_print_error "error: --command argument is mandatory!"
        __czp_print_error "${USAGE_MSG}"
        return
    fi

    # Add the CZP_PROMPT_MODULE_ prefix to the unique module name argument
    local MODULE_NAME="${CZP_MODULE_NAME_PREFIX}${NAME[2]}"

    # Verify that we don't already have a module with the same name
    if [[ -n "${(P)MODULE_NAME}" ]]; then
        __czp_print_error "error: a module with name '${NAME[2]}' already exists!"
        return
    fi

    # Organize the arguments into an associative array describing the module's parameters
    local -a MODULE_PARAMS=(
        Prefix "${PREFIX[2]}"
        Suffix "${SUFFIX[2]}"
        Color "${COLOR[2]}"
        Shell "${${SHELL[1]:+true}:-false}"
        Command "${COMMAND[2]}"
    )

    # In order to dynamically determine the module name, the module's associative array
    # must be declared, populated, and set to read-only in 3 distinct steps
    typeset -Ag ${MODULE_NAME}
    set -A ${MODULE_NAME} "${MODULE_PARAMS[@]}"

    # Add the name of the associative array for the new module to the modules list
    CZP_PROMPT_MODULES+=(${MODULE_NAME})

    # Re-configure prompt to account for the fact that we added a new module
    __czp_configure_prompt
}

# __czp_remove_module()
#
# Removes existing modules from CZP
#
# $* <Arguments>: Arguments to be passed into zparseopts, and 1 or more names of modules to be removed, see $USAGE_MSG for more information
function __czp_remove_module() {
    local -r USAGE_MSG="usage: czprompt remove [<module names>]

    -h, --help     prints this usage message"

    # Option handling
    local -a HELP
    if ! zparseopts -F -- {h,-help}=HELP; then
        __czp_print "${USAGE_MSG}"
        return
    fi

    # Print usage message
    if [[ -n "${HELP}" ]]; then
        __czp_print "${USAGE_MSG}"
        return
    fi

    # Extract the names from the positional parameters of the modules to be removed
    local -a MODULE_NAMES=("${@}")

    # Verify that at least 1 module name was provided
    if [[ ${#MODULE_NAMES} -eq 0 ]]; then
        __czp_print_error "error: at least one module name must be provided"
        __czp_print_error "${USAGE_MSG}"
        return
    fi

    # Iterate through each of the passed module names
    for NAME in "${MODULE_NAMES[@]}"; do
        # Prepend the module name prefix to the current name
        local PREFIXED_NAME="${CZP_MODULE_NAME_PREFIX}${NAME}"

        # Check if the name is assigned to an existing module
        if [[ ! -v "${PREFIXED_NAME}" || "${CZP_PROMPT_MODULES[(r)${PREFIXED_NAME}]}" != "${PREFIXED_NAME}" ]]; then
            __czp_print "warning: no module named '${NAME}' exists"
            continue
        fi

        # Unset the associative array containing the parameters for the module
        unset "${NAME}"

        # Remove the module's name from the $CZP_PROMPT_MODULES array
        CZP_PROMPT_MODULES=("${(@)CZP_PROMPT_MODULES:#${PREFIXED_NAME}}")
        __czp_print "successfully removed module '${NAME}'"
    done;

    # Re-configure prompt to account for the fact that we added a new module
    __czp_configure_prompt
}

# __czp_list_modules()
#
# Lists CZP modules
#
# $* <Arguments>: Arguments to be passed into zparseopts, and 1 or more names of modules to be listed, see $USAGE_MSG for more information
function __czp_list_modules() {
    local -r USAGE_MSG="usage: czprompt modules [<options>] [<module names>]

    -h, --help     prints this usage message
    -s, --short    print only the names of the modules rather than all of their details"

    # Option handling
    local -a HELP SHORT
    if ! zparseopts -D -F -- {h,-help}=HELP {s,-short}=SHORT; then
        __czp_print "${USAGE_MSG}"
        return
    fi

    # Print usage message
    if [[ -n "${HELP}" ]]; then
        __czp_print "${USAGE_MSG}"
        return
    fi

    # Extract the names from the positional parameters of the modules to be listed
    local -a MODULE_NAMES=("${@}")

    # If no module names were specified, just list them all
    if [[ ${#MODULE_NAMES} -eq 0 ]]; then
        MODULE_NAMES=("${CZP_PROMPT_MODULES[@]#${CZP_MODULE_NAME_PREFIX}}")
    fi

    # Iterate through each module name
    for NAME in "${MODULE_NAMES[@]}"; do
        # Prepend the module name prefix to the current name
        local PREFIXED_NAME="${CZP_MODULE_NAME_PREFIX}${NAME}"

        # Check if the name is assigned to an existing module
        if [[ ! -v "${PREFIXED_NAME}" || "${CZP_PROMPT_MODULES[(r)${PREFIXED_NAME}]}" != "${PREFIXED_NAME}" ]]; then
            __czp_print "warning: no module named '${NAME}' exists"
            continue
        fi

        # Check if the user specified "short" mode
        if [[ -n "${SHORT}" ]]; then
            # Print only the module name
            __czp_print_styled "- %B${NAME}%b"
        else
            # Print all the module details
            __czp_print_module "${PREFIXED_NAME}"

            # Print an empty line after each module if its not the last one
            if [[ "${NAME}" != "${MODULE_NAMES[-1]}" ]]; then __czp_print ""; fi
        fi
    done
}


# __czp_configure_prompt()
#
# Configures the $prompt variable to support as many modules are currently loaded
function __czp_configure_prompt() {
    # Declare and clear the prompt
    declare -g prompt=""

    # Add a $CZP_PSVAR parameter for each expected prompt module
    for ((i = 1; i <= ${#CZP_PROMPT_MODULES}; i++)); do
        prompt+='${CZP_PSVAR['${i}']}'
    done

    # Add a new line
    prompt+='${CZP_NEWLINE}'
    # Add the second line of the prompt, just the prompt character
    prompt+='%F{%(?.${CZP_PROMPT_CHARACTER_COLOR_SUCCESS}.${CZP_PROMPT_CHARACTER_COLOR_FAIL})}${CZP_PROMPT_CHARACTER}%f'

}

# __czp_prompt_module_async()
#
# Asynchronously executes a prompt module's command so that it shows up in the prompt next time the prompt is refreshed
# The callback function will handle putting the output into $CZP_PSVAR
# To be called from a zsh-async worker
#
# $1 <Order Number>: The 1-indexed order that this module will be displayed in, where 1 is the left-most module in the prompt
# $2 <Prefix>: The module's prefix text
# $3 <Suffix>: The module's suffix text
# $4 <Color>: The module's desired text color
# $5 <Shell>: Whether or not the module's command field is to be interpreted as a Zsh prompt escape sequence, or to be executed as a shell command
# $6 <Command>: The Zsh prompt escape sequence, or shell command that will be executed to provide the text content of the module
function __czp_prompt_module_async() {
    local -i PROMPT_ORDER_NUM="${1}"
    local PROMPT_MODULE_PREFIX="${2}"
    local PROMPT_MODULE_SUFFIX="${3}"
    local PROMPT_MODULE_COLOR="${4}"
    local PROMPT_MODULE_SHELL="${5}"
    local PROMPT_MODULE_COMMAND="${6}"

    # Get the output for the module's command
    local PROMPT_MODULE_CONTENT
    if [[ "${PROMPT_MODULE_SHELL}" == true ]]; then
        # Evaluate $PROMPT_MODULE_COMMAND as a shell command
        PROMPT_MODULE_CONTENT="$(eval ${PROMPT_MODULE_COMMAND})"
    else
        # Interpret $PROMPT_MODULE_COMMAND as a Zsh prompt escape
        PROMPT_MODULE_CONTENT="${(%)PROMPT_MODULE_COMMAND}"
    fi

    # Don't generate any output if the content of the prompt was empty
    if [[ -n "${PROMPT_MODULE_CONTENT}" ]]; then
        print -- "${PROMPT_MODULE_PREFIX}%F{${PROMPT_MODULE_COLOR}}${PROMPT_MODULE_CONTENT}%f${PROMPT_MODULE_SUFFIX}"
    fi

    # Return the order number of this module so the callback knows where to put its output
    return ${PROMPT_ORDER_NUM}
}

# __czp_prompt_module_async_callback()
#
# Called after an async module is finished executing
#
# TODO: Handle possible errors when Job Name comes back as "[async]"
#
# $1 <Job Name>: The job name, which is the name of the function passed to the worker via async_job()
# $2 <Return Code>: Return code of the function passed to the worker via async_job(), -1 indicates a zsh-async error
# $3 <Stdout Result>: The resulting stdout output from the job execution
# $4 <Exec Time>: The amount of time in floating-point seconds that the job execution took
# $5 <Stderr Result>: The resulting stderr output from the job execution
# $6 <Has Next>: Whether or not another async job has completed
function __czp_prompt_module_async_callback() {
    local JOB_NAME="${1}"
    local -i RETURN_CODE="${2}"
    local STDOUT_RESULT="${3}"
    local -F EXEC_TIME="${4}"
    local STDERR_RESULT="${5}"
    local -i HAS_NEXT="${6}"
    local -i PROMPT_ORDER_NUM=${RETURN_CODE}

    # Put the stdout output from the module into the appropriate $CZP_PSVAR slot
    CZP_PSVAR[${PROMPT_ORDER_NUM}]="${STDOUT_RESULT}"

    # Add the separator if we have output and aren't the last module
    if [[ -n "${STDOUT_RESULT}" && ${PROMPT_ORDER_NUM} -lt ${#CZP_PROMPT_MODULES} ]]; then
        CZP_PSVAR[${PROMPT_ORDER_NUM}]+="${CZP_MODULE_SEPARATOR}"
    fi

    # Check if there are any more results buffered
    if [[ ${HAS_NEXT} -eq 0 ]]; then
        # If not, reset the prompt and redisplay the command line
        zle .reset-prompt
        zle -R
    fi

}

# __czp_init()
#
# Initializes the prompt and any supporting bits
function __czp_init() {
    # Initialize zsh-async
    async_init

    # Perform initial configuration of the prompt
    __czp_configure_prompt
}

# precmd()
#
# Executed before each prompt
# See https://zsh.sourceforge.io/Doc/Release/Functions.html#Hook-Functions
function precmd() {
    # Stop the worker if it's currently running
    # This needs to be done so update the worker environment to match the user's environment (e.g., to get proper $(pwd) output),
    # as well as to ensure any jobs that have not finished yet are stopped
    async_stop_worker "${CZP_WORKER_NAME}"

    # Start a fresh worker
    async_start_worker "${CZP_WORKER_NAME}"

    # Register a callback function to run when the async prompt module job completes
    async_register_callback "${CZP_WORKER_NAME}" __czp_prompt_module_async_callback

    # Start async workers and jobs for each of the modules
    for ((i = 1; i <= ${#CZP_PROMPT_MODULES}; i++)); do
        # The quotes are surrounding the parameter expansion are necessary to allow prompt module fields to be empty strings
        # Parameter expansion explanation
        #  - P: Expand the names of the inner associative arrays (for each module) into the array values
        #  - k: Replace the array values with their respective key names
        #  - v: Add back the array values, following their respective key names
        #  - @: Since the whole expression is in double quotes, expand each array element into its own word, each surrounded by double quotes
        local -A MODULE=("${(Pvk@)CZP_PROMPT_MODULES[${i}]}")

        # Start the prompt module job
        async_job "${CZP_WORKER_NAME}" __czp_prompt_module_async "${i}" "${MODULE[Prefix]}" "${MODULE[Suffix]}" "${MODULE[Color]}" "${MODULE[Shell]}" "${MODULE[Command]}"
    done
}

# czprompt()
#
# The user-facing interface into clean-zsh-prompt
function czprompt() {
    local -r USAGE_MSG="usage: czprompt <sub-menu>

    add       add a new prompt module
    remove    remove prompt modules
    modules   list the specified modules identified by name, or all loaded modules if no module names are specified
    prompt    print the prompt that czprompt is providing to Zsh (useful for debugging)
    help      print this menu"

    local -r SUBMENU_SELECTOR="${1}"
    local -ar SUBMENU_ARGS=("${@:2}")
    case "${SUBMENU_SELECTOR}" in
        add)
            __czp_add_module "${SUBMENU_ARGS[@]}"
            ;;
        remove)
            __czp_remove_module "${SUBMENU_ARGS[@]}"
            ;;
        modules)
            __czp_list_modules "${SUBMENU_ARGS[@]}"
            ;;
        prompt)
            print -r -- "${(qqqq%%)prompt}"
            ;;
        *)
            __czp_print "${USAGE_MSG}"
            ;;
    esac
    return
}

###############
# MAIN SCRIPT #
###############

# Add completions to fpath
# TODO: Check if there is a "better" way to do this
fpath+="${0:a:h}/completions"

# Initialize the prompt
__czp_init
