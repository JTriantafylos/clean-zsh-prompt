# clean-zsh-prompt

A simple, asynchronous prompt framework for Zsh, written in pure Zsh scripting language.

clean-zsh-prompt works on the basis that each **module** (independent section of your prompt) will run asynchronously, meaning you could add long-running functions to your prompt without affecting the usability of your shell. The long-running modules will simply update your prompt as their results come in, without interrupting your usage.

## Installation

Simply clone this repository to a location of your choosing:

```sh
git clone --recurse-submodules git@github.com:JTriantafylos/clean-zsh-prompt.git
```

and add the following line to your `.zshrc` (or equivalent):

```sh
source <Path to repository>/clean-zsh-prompt.zsh
```

> Want support added for your favorite Zsh package manager, open an issue and let me know!

## Usage

clean-zsh-prompt in controlled entirely via the `czprompt` shell function. Running `czprompt help` will give you a description of the available functionality.

The general idea behind clean-zsh-prompt is that each prompt module has its content determined either by expanding a Zsh prompt escape sequence (see zshmisc(1) § EXPANSION OF PROMPT SEQUENCES), or by the output (stdout specifically) of a specified shell command(s).

Adding a module to your prompt consists of running the `czprompt add` command. All available options can be seen by running `czprompt add --help`, though the only mandatory options are `--name`, which defines the name of the module, and `--command` which defines the Zsh prompt escape sequence, or shell command(s) (when `--shell` is passed), that will make up the content of the module. Adding a module via `czprompt add` is only persistent for the lifetime of your current shell session, meaning if you'd like to persist your modules, you will have to put the relevant `czprompt add` commands in your `.zshrc` or similar.

## Examples

### Directory Module

```sh
czprompt add --name 'directory' --color 'blue' --command '%~'
```

### Git Branch/Tag

```sh
czprompt add --name 'git_branch' --prefix 'on ' --color 'magenta' --shell --command '
    # Check if we are in a git directory
    git rev-parse --git-dir > /dev/null 2>&1 || return;

    # Determine the current branch or tag, and output it
    GIT_BRANCH_OR_TAG="$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match)";
    if [[ -n "${GIT_BRANCH_OR_TAG}" ]]; then
        print " ${GIT_BRANCH_OR_TAG}";
    fi
'
```

### Git Status

```sh
czprompt add --name 'git_status' --color 'red' --shell --command '
    # Check if we are in a git directory
    git rev-parse --git-dir > /dev/null 2>&1 || return;

    # Variable to hold the symbols for each type of status
    GIT_SYMBOLS="";

    # Variable to hold the output of `git status`
    GIT_STATUS="$(git status --porcelain=v1)"

    # Variable to hold the output of `git status --branch`
    GIT_BRANCH_STATUS="$(git status --branch --porcelain=v1)"

    # Check if the current branch is ahead of upstream
    grep -m 1 "ahead" <<< "${GIT_BRANCH_STATUS}" > /dev/null 2>&1 && GIT_SYMBOLS+="↑";

    # Check if the current branch is behind upstream
    grep -m 1 "behind" <<< "${GIT_BRANCH_STATUS}" > /dev/null 2>&1 && GIT_SYMBOLS+="↓";

    # Check if anything is stashed
    if [[ -n "$(git stash list)" ]]; then GIT_SYMBOLS+="$"; fi;

    # Check if we have any deleted files
    grep -m 1 "^.?D" <<< "${GIT_STATUS}" > /dev/null 2>&1 && GIT_SYMBOLS+="✘";

    # Check if we have any renamed files
    grep -m 1 "^.?R" <<< "${GIT_STATUS}" > /dev/null 2>&1 && GIT_SYMBOLS+="»";

    # Check if we have any unstaged modified files
    grep -m 1 "^.M" <<< "${GIT_STATUS}" > /dev/null 2>&1 && GIT_SYMBOLS+="!";

    # Check if we have any added, or modified and staged files
    grep -m 1 "^(A|M) " <<< "${GIT_STATUS}" > /dev/null 2>&1 && GIT_SYMBOLS+="+";

    # Check if we have any untracked files
    grep -m 1 "^\?\?" <<< "${GIT_STATUS}" > /dev/null 2>&1 && GIT_SYMBOLS+="?";

    # Outut the collection of git symbols
    if [[ -n "${GIT_SYMBOLS}" ]]; then print "[${GIT_SYMBOLS}]"; fi
'
```

## Contributing

If you have any fixes or improvements you would like to see in clean-zsh-prompt, feel free to raise an issue or open a pull request.
