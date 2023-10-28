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

# The color that the prompt character will be displayed with
declare CZP_PROMPT_CHARACTER_COLOR="green"

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

# czp_add_module()
#
# Adds a new module to CZP
#
# $1 <Module Name>: A unique module name
# $2 <Prefix>: The constant prefix text that will come before the module
# $3 <Suffix>: The constant suffix text that will come after the module
# $4 <Color>: The text color that the module will be displayed in
# $5 <Shell>: Whether or not the module's command field is to be interpreted as a Zsh prompt escape sequence, or to be executed as a shell command
# $6 <Command>: The Zsh prompt escape sequence, or shell command that will be executed to provide the text content of the module
function czp_add_module() {
    # Add the CZP_PROMPT_MODULE_ prefix to the unique module name argument
    local MODULE_NAME="${CZP_MODULE_NAME_PREFIX}${1}"
    # Organize the arguments into an associative array describing the module's parameters
    local -a MODULE_PARAMS=(
        Prefix "${2}"
        Suffix "${3}"
        Color "${4}"
        Shell "${5}"
        Command "${6}"
    )

    # In order to dynamically determine the module name, the module's associative array
    # must be declared, populated, and set to read-only in 3 distinct steps
    declare -Ag "${MODULE_NAME}"
    set -A ${MODULE_NAME} "${MODULE_PARAMS[@]}"
    declare -gr "${MODULE_NAME}"

    # Add the name of the associative array for the new module to the modules list
    CZP_PROMPT_MODULES+=("${MODULE_NAME}")

    # Re-configure prompt to account for the fact that we added a new module
    czp_configure_prompt
}

# czp_configure_prompt()
#
# Configures the $prompt variable to support as many modules are currently loaded
function czp_configure_prompt() {
    # Declare and clear the prompt
    declare -g prompt=""

    # Add a $CZP_PSVAR parameter for each expected prompt module
    for ((i = 1; i <= "${#CZP_PROMPT_MODULES}"; i++)); do
        prompt+='${CZP_PSVAR['${i}']}'
    done

    # Add a new line
    prompt+='${CZP_NEWLINE}'
    # Add the second line of the prompt, just the prompt character
    prompt+='%F{${CZP_PROMPT_CHARACTER_COLOR}}${CZP_PROMPT_CHARACTER}%f'

}

# czp_prompt_module_async()
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
function czp_prompt_module_async() {
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
        print "${PROMPT_MODULE_PREFIX}%F{${PROMPT_MODULE_COLOR}}${PROMPT_MODULE_CONTENT}%f${PROMPT_MODULE_SUFFIX}"
    fi

    # Return the order number of this module so the callback knows where to put its output
    return "${PROMPT_ORDER_NUM}"
}

# czp_prompt_module_async_callback()
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
function czp_prompt_module_async_callback() {
    local JOB_NAME="${1}"
    local -i RETURN_CODE="${2}"
    local STDOUT_RESULT="${3}"
    local -F EXEC_TIME="${4}"
    local STDERR_RESULT="${5}"
    local -i HAS_NEXT="${6}"
    local -i PROMPT_ORDER_NUM="${RETURN_CODE}"

    # Don't bother doing any more work if the module is empty
    if [[ -z "${STDOUT_RESULT}" ]]; then
        return
    fi

    # Put the stdout output from the module into the appropriate $CZP_PSVAR slot
    CZP_PSVAR[${PROMPT_ORDER_NUM}]="${STDOUT_RESULT}"

    # Add the separator if we have output and aren't the last module
    if [[ "${PROMPT_ORDER_NUM}" -lt "${#CZP_PROMPT_MODULES}" ]]; then
        CZP_PSVAR[${PROMPT_ORDER_NUM}]+="${CZP_MODULE_SEPARATOR}"
    fi

    # Check if there are any more results buffered
    if [[ "${HAS_NEXT}" -eq 0 ]]; then
        # If not, reset the prompt and redisplay the command line
        zle .reset-prompt
        zle -R
    fi

}

# precmd()
#
# Executed before each prompt
# See https://zsh.sourceforge.io/Doc/Release/Functions.html#Hook-Functions
function precmd() {
    # Stop the worker if it's currently running
    # This needs to be done so update the worker environment to match the user's environment (e.g., to get proper $(pwd) output)
    async_stop_worker "${CZP_WORKER_NAME}"

    # Start a fresh worker
    async_start_worker "${CZP_WORKER_NAME}"

    # Register a callback function to run when the async prompt module job completes
    async_register_callback "${CZP_WORKER_NAME}" czp_prompt_module_async_callback

    # Start async workers and jobs for each of the modules
    for ((i = 1; i <= "${#CZP_PROMPT_MODULES}"; i++)); do
        # The quotes are surrounding the parameter expansion are necessary to allow prompt module fields to be empty strings
        # Parameter expansion explanation
        #  - P: Expand the names of the inner associative arrays (for each module) into the array values
        #  - k: Replace the array values with their respective key names
        #  - v: Add back the array values, following their respective key names
        #  - @: Since the whole expression is in double quotes, expand each array element into its own word, each surrounded by double quotes
        local -A MODULE=("${(Pvk@)CZP_PROMPT_MODULES[${i}]}")

        # Start the prompt module job
        async_job "${CZP_WORKER_NAME}" czp_prompt_module_async "${i}" "${MODULE[Prefix]}" "${MODULE[Suffix]}" "${MODULE[Color]}" "${MODULE[Shell]}" "${MODULE[Command]}"
    done
}

###############
# MAIN SCRIPT #
###############

# Initialize zsh-async
async_init

# Perform initial configuration of the prompt
czp_configure_prompt
