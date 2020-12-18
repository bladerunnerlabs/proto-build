#!/bin/bash
#
# script: git_pull.sh
#
# Copyright (c) 2019 - BladeRunner Labs
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the "Software")
# to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# -----------------------------------------------------------------------------
# This script is intended for development in multiple git-repo environments.
# It starts with a "seed repo", where all or most of the changes were introduced.
# Then few "secondary repos" are cloned or pulled according to a set of rules
# defined by a text configuration file.
# The configuration file is processed line-by-line.
# Each non-empty line (after stripping the # comments) contains a repo rule.
#
# Repo rules should have four fields:
#
# 1. *local branch*: a regular expression to be matched against the actual seed repo
#     branch; only the lines which have their local branch strings matched are
#     subbmitted to git pull processing
# 2. *repo url*: the git url of a repo to be cloned or pulled
# 3. *checkout id*: a git id (branch, tag, commit) to be used in checkout
# 4. *directory*: the name of a directory to which the secondary repo is cloned,
#     or existing directory in which the secondary repo is pulled or
#     checked out locally.
#
# Configuration file example:
#
# local     | Repo-URL                   | Checkout-ID               | Directory
# branch    |                            | branch, tag, commit       |
# ---------------------------------------------------------------------------------
# feature/* | ${url_prefix}core-repo.git | release/acceptance_master | ../core-repo
# release/* | ${url_prefix}core-repo.git | cmake                     | ../core-repo
#
#

SCRIPT_NAME=`basename $0`
SCRIPT_DIR=`dirname $0`
SCRIPT_DIR=`readlink -e ${SCRIPT_DIR}`
BROOT_DIR=`readlink -e ${SCRIPT_DIR}/../..`

DEF_CFG_FNAME="./git_pull.cfg"
DEF_SEED_BRANCH="master"
DEF_SEED_REMOTE="origin"

ACTION_CLONE=false
ACTION_PULL=false
ACTION_LOCAL=false

VERBOSE=false
DRY_RUN=false

GIT_WORK="git"

# default variables to be used in .cfg file
dir="${BROOT_DIR}"

if [[ "${TERM}" = xterm* ]]; then
    YELLOW="\033[93m"
    GREEN="\033[92m"
    BLUE="\033[94m"
    RED="\033[91m"
    NORM="\033[0m"
elif [[ "${TERM}" = linux* ]]; then
    YELLOW="\033[33;1m"
    GREEN="\033[32;1m"
    BLUE="\033[34;1m"
    RED="\033[31;1m"
    NORM="\033[0m"
fi

function msg_blue()
{
    echo -e "${BLUE}$@${NORM}"
}

function msg_yellow()
{
    echo -e "${YELLOW}$@${NORM}"
}

function msg_red()
{
    echo -e "${RED}$@${NORM}"
}

function msg_green()
{
    echo -e "${GREEN}$@${NORM}"
}

function msg_verbose()
{
    if [[ "${VERBOSE}" == true ]]; then
        echo -e "$@"
    fi
}

function err_exit()
{
    if [[ -n "$*" ]]; then
        msg_red "$*"
    fi
    exit 1
}

function ask_user()
{
    if [[ "${AUTO_FORCE}" == true ]]; then
        echo "true"
    fi
    # temporary workaround
    echo "false"

    #local prompt_msg="$1"
    #local old_stty_cfg
    #local _pressed

    #msg_yellow "${promt_msg} (y for Yes, any key for No): "

    #old_stty_cfg=`stty -g`
    #stty raw -echo
    #local _pressed=$( while ! head -c 1; do true; done )
    #stty $old_stty_cfg

    #if [[ "${_pressed}" == "y" || "${_pressed}" == "Y" ]]; then
    #    echo "true"
    #fi
}

function usage()
{
    echo -e "Usage: ${BLUE}${SCRIPT_NAME}${NORM} [options]"
    echo -e "\nSeed options:"
    echo -e "${BLUE}-u | --seed-url [git-url]${NORM}: clone the seed repo, pull using its configuraton"
    echo -e "${BLUE}-d | --seed-dir [dir-name]${NORM}: pull the seed dir, pull using its configuraton"
    echo -e "       (*) --seed-dir and --seed-url are mutually exclusive, one of them is mandatory"
    echo -e "${BLUE}-n | --seed-remote-name [remote-name]${NORM}: rename git remote after seed-url clone or"
    echo -e "       pull the seed-dir using this git remote [${DEF_SEED_REMOTE}]"
    echo -e "${BLUE}-b | --seed-branch [branch]${NORM}: checkout branch in the seed repo [${DEF_SEED_BRANCH}]"
    echo -e "\nConfiguration file options:"
    echo -e "${BLUE}-c | --config [filename]${NORM}: configuraton file [${DEF_CFG_FNAME}]"
    echo -e "${BLUE}-E | --eval [statement]${NORM}: evaluate var assignment, e.g.: -E ext_dir=external"
    echo -e "\nConfiguration format:"
    echo -e "${GREEN}Local-brach | ${GREEN}Repo-URL${NORM} | ${GREEN}Checkout-ID${NORM} {branch|tag|commit} | ${GREEN}Directory${NORM}"
    echo -e "       all fields may contain vars, e.g.: \${ext_dir}/3rd-party-repo (see --eval)"
    echo -e "\nCheckout policies:"
    echo -e "${BLUE}-C | --clone${NORM}: clone all repos [off]"
    echo -e "${BLUE}-P | --pull${NORM}: pull all repos [on]"
    echo -e "${BLUE}-L | --local${NORM}: update all repos from the local replicas of the git remote [off]"
    echo -e "       (*) --clone, --pull, --local are mutually exclusive, one of them is mandatory"
    echo -e "${BLUE}-f | --force${NORM}: try to enforce the policy if it can't be satisfied [off]"
    echo -e "       for clone: rmdir and re-clone if directory exists (unpushed changes are lost)"
    echo -e "       for pull: clone if dir does not exist"
    echo -e "       for local, pull: reset local changes if any (uncommitted changes are lost)"
    echo -e "${BLUE}-y | --yes${NORM}: don't ask before enforcing the policy (dangerous!) [off]"
    echo -e "\nExecution options:"
    echo -e "${BLUE}-D | --dry ${NORM}: perform dry run, only print processed lines [off]"
    echo -e "${BLUE}-V | --verbose${NORM}: produce verbose output, [off]"
    echo -e "${BLUE}-h | --help   ${NORM}: print the help message"
    exit $1
}

function parse_args()
{
    options=$(getopt \
            -o "u:d:n:b:c:E:CPLfyDVh" \
            -l "seed-url:,seed-dir:,seed-remote-name:,seed-branch:,config:,eval:,clone,pull,local,force,yes,dry,verbose,help" \
        -- "$@")
    if [ $? -ne 0 ]; then
        msg_red "${SCRIPT_NAME}: failed to parse arguments\n"
        usage 1
    fi

    eval set -- ${options}

    while [ $# -gt 1 ]; do
        case $1 in
            -u|--seed-url) CMD_SEED_URL=$2; shift; ;;
            -d|--seed-dir) CMD_SEED_DIR=$2; shift; ;;
            -n|--seed-remote-name) CMD_SEED_REMOTE=$2; shift; ;;
            -b|--seed-branch) CMD_SEED_BRANCH=$2; shift; ;;
            -c|--config) CMD_CFG_FNAME=$2; shift; ;;
            -E|--eval) eval "$2"; shift; ;;
            -C|--clone) ACTION_CLONE=true; shift; ;;
            -P|--pull) ACTION_PULL=true; ;;
            -L|--local) ACTION_LOCAL=true; ;;
            -f|--force) FORCE_ACTION=true; ;;
            -y|--yes) AUTO_FORCE=true; ;;
            -D|--dry) DRY_RUN=true; ;;
            -V|--verbose) VERBOSE=true; ;;
            -h|--help) usage 0; ;;
                # default options
                (--) shift; break ;;
                (-*) msg_red "${SCRIPT_NAME}: error - unrecognized option $1\n" 1>&2;
                usage 1; ;;
                (*) break ;;
        esac
        shift
    done
}

args="$@"
parse_args ${args}

# check that mutually exclusive args were not supplied simltaneously
# but at least of the mandatory args was supplied

[[ -z "${CMD_SEED_URL}" && -z "${CMD_SEED_DIR}" ]] && \
    err_exit "one of the args: -u|--seed-url, -d|--seed-dir must be supplied"
[[ -n "${CMD_SEED_URL}" && -n "${CMD_SEED_DIR}" ]] && \
    err_exit "-u|--seed-url and -d|--seed-dir can't be supplied simultaneously"

[[ "${ACTION_CLONE}" != true && "${ACTION_PULL}" != true && "${ACTION_LOCAL}" != true ]] && \
    err_exit "one of the args: -C|--clone, -P|--pull, -L|--local must be supplied"
[[ "${ACTION_CLONE}" == true && "${ACTION_PULL}" == true ]] && \
    err_exit "-C|--clone and -P|--pull can't be supplied simultaneously"
[[ "${ACTION_CLONE}" == true && "${ACTION_LOCAL}" == true ]] && \
    err_exit "-C|--clone and -L|--local can't be supplied simultaneously"
[[ "${ACTION_PULL}" == true && "${ACTION_LOCAL}" == true ]] && \
    err_exit "-P|--pull and -L|--local can't be supplied simultaneously"

function log_exec()
{
    local cmd_arr=("$*")
    msg_blue "$*"
    $* || err_exit "${cmd_arr[0]} failed"
}

function quiet_exec()
{
    $* 2>/dev/null
}

function quiet_exec_err_exit()
{
    $* 2>/dev/null || err_exit "\"$*\" failed"
}

function test_git_url()
{
    local url="$1"
    if [[ ! "${DRY_RUN}" == true ]]; then
        msg_blue "test ${url} connectivity"
        quiet_exec ${GIT_WORK} ls-remote --exit-code --heads ${url} 1>/dev/null || err_exit "${url} can't be reached"
    else
        msg_blue "DRY test ${url} connectivity"
    fi
}

function test_branch_name()
{
    local name="$1"
    msg_blue "test git id: ${name}"
    ${GIT_WORK} rev-parse --verify --quiet ${name} || err_exit "${name} does not exist"
}

function repo_name_from_url()
{
    local url="$1"
    local name="${url%%.git}"
    name="${name##*\/}"
    echo "${name}"
}

function generate_remote_name()
{
    local url="$1"

    local gitf
    local name

    gitf="${url/*[:\/]/}"
    gitf="${gitf%%.git}"
    gitf="${gitf//[.:]/-}"

    if [[ "${url}" = git@* ]]; then
        name="${url/git@/}"
        name="${name/:*/}"
    elif [[ "${url}" = https:\/\/* ]]; then
        name="${url/https:\/\//}"
        name="${name/\/*/}"
    elif [[ "${url}" = ssh:\/\/* ]]; then
        name="${url/ssh:\/\/*@/}"
        name="${name/\/*/}"
    fi

    if [[ -n "${name}" ]]; then
        name="${name//[.:]/-}_"
    fi

    echo "${name}${gitf}" # retval
}

function list_remotes()
{
    quiet_exec ${GIT_WORK} remote
}

function get_remote_url_cached()
{
    local remote_name="$1"

    quiet_exec ${GIT_WORK} remote show -n ${remote_name} | grep "Fetch URL" | head -n 1 | awk '{print $3}'
}

function find_remote_by_url()
{
    local url="$1"; shift
    local remotes_list
    local remote_url
    local remote_name

    remotes_list=`list_remotes` || err_exit "\"git remote\" failed"
    for remote_name in ${remotes_list}; do
        remote_url=`get_remote_url_cached ${remote_name}` || return $?
        if [[ "${remote_url}" == "${url}" ]]; then
            echo "${remote_name}" # print retval
            return 0
        fi
    done
}

function find_url_by_remote()
{
    local name="$1"; shift
    local remotes_list
    local remote_url
    local remote_name

    remotes_list=`list_remotes` || err_exit "\"git remote\" failed"
    for remote_name in ${remotes_list}; do
        if [[ "${remote_name}" == "${name}" ]]; then
            remote_url=`get_remote_url_cached ${remote_name}` || return $?
            echo "${remote_url}" # print retval
            return 0
        fi
    done
}

function current_branch()
{
    quiet_exec ${GIT_WORK} symbolic-ref -q --short HEAD # print retval
}

function current_tag()
{
    quiet_exec ${GIT_WORK} describe --tags --exact-match HEAD # print retval
}

function current_commit_id()
{
    quiet_exec ${GIT_WORK} rev-parse HEAD # print retval
}

function get_commit_id()
{
    local git_id="$1"
    ${GIT_WORK} rev-parse --verify --quiet ${git_id} || return 1
}

function current_head_string()
{
    local id
    local tag
    local br
    local str

    id=`current_commit_id` || return $?
    tag=`current_tag`
    br=`current_branch`

    if [[ -n "${br}" ]]; then
        str="${str}${br}/"
    else
        str="${str}[detached]/"
    fi
    [[ -n "${tag}" ]] && str="${str}${tag}/"
    str="${str}${id:0:7}"

    echo "${str}" # print retval
}

function current_head_match()
{
    local git_id="$1"

    local id
    local tag
    local br

    id=`current_commit_id` || return $?
    tag=`current_tag`
    br=`current_branch`

    if [[ "${br}" == ${git_id} ]]; then
        echo "${br}" # retval
    elif [[ "${tag}" == ${git_id} ]]; then
        echo "${tag}" # retval
    elif [[ "${id}" == ${git_id} ]]; then
        echo "${id}" # retval
    fi
}

function checkout_branch()
{
    local dir="$1"; shift
    local remote_name="$1"; shift
    local branch="$1"; shift
    local commit_id

    if [[ -n "`${GIT_WORK} diff --name-only`" ]]; then
        msg_yellow "uncommitted chages found"
        if [[ `ask_user "reset (changes will be lost)?"` == true ]]; then
            log_exec "${GIT_WORK} reset --hard"
        else
            err_exit "can't proceed with checkout"
        fi
    fi

    if [[ -n "`${GIT_WORK} ls-files --others --exclude-standard`" ]]; then
        msg_yellow "untracked files found"
        if [[ `ask_user "remove (files will be lost)?"` == true ]]; then
            log_exec "${GIT_WORK} clean -fdx"
            #else
            # workaround
            #err_exit "can't proceed with checkout"
        fi
    fi

    commit_id=`get_commit_id ${branch}`
    if [[ -n "${commit_id}" ]]; then

        local cur_head_match=`current_head_match ${branch}`
        local cur_head_id=`current_head_string`

        if [[ -z "${cur_head_match}" ]]; then
            echo "${branch} exists but the current ${dir} git head: ${cur_head_id}"
            log_exec "${GIT_WORK} checkout ${branch}"
        else
            msg_green "current ${dir} git head: ${cur_head_id}"
        fi

        test_branch_name ${remote_name}/${branch}
        log_exec "${GIT_WORK} rebase ${remote_name}/${branch}"
    else
        echo "${branch} never checked out"
        log_exec "${GIT_WORK} checkout -t ${remote_name}/${branch}"
    fi
}

function clone_repo()
{
    local dir="$1"; shift
    local url="$1"; shift
    local branch="$1"; shift
    local remote_name="$1"; shift

    if [[ "${DRY_RUN}" == true ]]; then
        msg_blue "DRY clone: ${url} to ${dir}, branch: ${branch}"
        return
    fi

    # clone must be done from the root dir
    log_exec "git clone ${url} ${dir}"

    GIT_WORK="git -C ${dir}"

    if [[ -z "${remote_name}" ]]; then
        remote_name=`find_remote_by_url ${url}` || err_exit "\"git remote\" failed"
    elif [[ "${remote_name}" != origin ]]; then
        log_exec "${GIT_WORK} remote rename origin ${remote_name}"
    fi
    checkout_branch ${dir} ${remote_name} ${branch}
}

function pull_repo_by_url()
{
    local dir="$1"; shift
    local url="$1"; shift
    local branch="$1"; shift
    local def_remote_name="$1"; shift
    local remote_name

    if [[ "${DRY_RUN}" == true ]]; then
        msg_blue "DRY pull: dir: ${dir} url: ${url} default remote: ${def_remote_name} branch: ${branch}"
        return
    fi

    GIT_WORK="git -C ${dir}"

    remote_name=`find_remote_by_url ${url}` || err_exit "\"git remote\" failed"
    if [[ -z "${remote_name}" ]]; then
        remote_name="${def_remote_name}"
        log_exec "${GIT_WORK} remote add ${remote_name} ${url}"
    else
        msg_green "found ${url} as remote: ${remote_name} in dir: ${dir}"
    fi

    log_exec "${GIT_WORK} fetch ${remote_name}"

    checkout_branch ${dir} ${remote_name} ${branch}
}

function checkout_local()
{
    local dir="$1"; shift
    local url="$1"; shift
    local branch="$1"; shift
    local def_remote_name="$1"; shift
    local remote_name

    if [[ "${DRY_RUN}" == true ]]; then
        msg_blue "DRY local checkout: ${url} branch: ${branch} in dir: ${dir}"
        return
    fi

    GIT_WORK="git -C ${dir}"

    remote_name=`find_remote_by_url ${url}` || err_exit "\"git remote\" failed"
    if [[ -z "${remote_name}" ]]; then
        err_exit "local checkout requested but no cached remote found for: ${url}"
    else
        msg_green "in dir: ${dir} found ${url} as remote: ${remote_name}"
    fi

    checkout_branch ${dir} ${remote_name} ${branch}
}

function check_dir_under_broot()
{
    local dir_str="$1"
    local dir_path="$2"
    [[ "${dir_path}" = ${BROOT_DIR}/* ]] || err_exit "${dir_str}: ${dir_path} is not under build-root: ${BROOT_DIR}"
}

# start

CFG_FNAME="${CMD_CFG_FNAME:-${DEF_CFG_FNAME}}"

SEED_REMOTE="${CMD_SEED_REMOTE:-${DEF_SEED_REMOTE}}"
SEED_BRANCH="${CMD_SEED_BRANCH:-${DEF_SEED_BRANCH}}"

if [[ -n "${CMD_SEED_URL}" ]]; then # clone seed url
    msg_green "\nseed by git url: ${CMD_SEED_URL}"

    SEED_DIR=`repo_name_from_url ${CMD_SEED_URL}` || err_exit "failed to find git URL: ${CMD_SEED_URL}"
    msg_blue "inferred seed-dir: ${SEED_DIR} from seed-url: ${CMD_SEED_URL}"
    SEED_DIR=`readlink -m ${SEED_DIR}` || err_exit "seed-dir: ${SEED_DIR} is invalid"
    check_dir_under_broot "seed-dir" "${SEED_DIR}"
    if [[ -d ${SEED_DIR} ]]; then
        pull_repo_by_url ${SEED_DIR} ${CMD_SEED_URL} ${SEED_BRANCH}
        msg_verbose "seed from url complete: url, pull"
    else
        clone_repo ${SEED_DIR} ${CMD_SEED_URL} ${SEED_BRANCH} ${SEED_REMOTE}
        msg_verbose "seed from url complete: url, clone"
    fi
else # pull seed dir
    msg_green "\nseed by updating dir: ${CMD_SEED_DIR}"

    SEED_DIR=`readlink -e ${CMD_SEED_DIR}` || err_exit "seed dir: ${CMD_SEED_DIR} does not exist"
    GIT_WORK="git -C ${SEED_DIR}"
    SEED_URL=`find_url_by_remote ${SEED_REMOTE}` || err_exit "failed to find git remote: ${SEED_REMOTE} in dir: ${SEED_DIR}"
    [[ -z "${SEED_URL}" ]] && err_exit "no git remote: ${SEED_REMOTE} in dir: ${SEED_DIR}"
    msg_blue "seed dir: ${SEED_DIR} remote: ${SEED_REMOTE} url: ${SEED_URL}"
    pull_repo_by_url ${SEED_DIR} ${SEED_URL} ${SEED_BRANCH}
    msg_verbose "seed from dir complete: dir, pull"
fi
echo

CFG_PATH="${SEED_DIR}/${CFG_FNAME}"
if [[ -f "${CFG_PATH}" ]]; then
    msg_verbose "reading config file: ${BLUE}${CFG_PATH}${NORM}"
else
    err_exit "config file ${CFG_PATH} does not exist"
fi

cur_git_id=`current_head_string` || err_exit "\"git rev-parse HEAD\" failed, not a git directory? ${PWD}"
msg_verbose "Current git id: ${BLUE}${cur_git_id}${NORM}\n"

line_num=1
num_cols=4

while IFS=' ,|' read -a cols; do
    GIT_WORK="git -C ${SEED_DIR}"
    if [[ ${#cols[@]} == ${num_cols} ]]; then
        # use eval to allow variables in the strings
        eval "branch_regex=${cols[0]}"
        eval "fetch_url=${cols[1]}"
        eval "fetch_branch=${cols[2]}"
        eval "fetch_dir=${cols[3]}"
        echo "[${fetch_dir}]"
        fetch_dir=`readlink -f ${fetch_dir}`

        summary=
        summary="${summary}line:${YELLOW}${line_num}${NORM} "
        summary="${summary}local regex:${YELLOW}${branch_regex}${NORM}, "
        summary="${summary}remote url:${YELLOW}${fetch_url}${NORM} "
        summary="${summary}branch/tag/id:${YELLOW}${fetch_branch}${NORM}, "
        summary="${summary}dir:${YELLOW}${fetch_dir}${NORM} "

        def_remote_name=`generate_remote_name ${fetch_url}`

        regex_match=`current_head_match "${branch_regex}"` || err_exit "retrieving git id failed"
        if [[ -n "${regex_match}" ]]; then
            echo -e "${summary}"
            echo -e "local git head:${YELLOW}${regex_match}${NORM} matches rule: ${YELLOW}${branch_regex}${NORM}"

            check_dir_under_broot "git dir" "${fetch_dir}"

            if [[ "${ACTION_CLONE}" == true ]]; then
                test_git_url ${fetch_url}
                if [[ -d ${fetch_dir} ]]; then
                    if [[ "${FORCE_ACTION}" = true || `ask_user "${fetch_dir} exists - can't clone; remove and re-clone?"` == true ]]; then
                        log_exec "rm -rf ${dir}"
                    else
                        err_exit "${fetch_dir} exists, can't clone"
                    fi
                fi
                clone_repo ${fetch_dir} ${fetch_url} ${fetch_branch} || err_exit "clone failed"
            elif [[ "${ACTION_PULL}" == true ]]; then
                test_git_url ${fetch_url}
                if [[ -d ${fetch_dir} ]]; then
                    pull_repo_by_url ${fetch_dir} ${fetch_url} ${fetch_branch} ${def_remote_name} || err_exit "pull failed"
                else
                    #if [[ "${FORCE_ACTION}" = true || `ask_user "${fetch_dir} does not exist - can't pull; clone?"` == true ]]; then
                    if true; then # workaround, while ask_user disabled
                        msg_yellow "${fetch_dir} does not exist, can't pull - clone instead"
                        clone_repo ${fetch_dir} ${fetch_url} ${fetch_branch} || err_exit "clone failed"
                    else
                        err_exit "${fetch_dir} does not exist, can't pull"
                    fi
                fi
            elif [[ "${ACTION_LOCAL}" == true ]]; then
                if [[ -d ${fetch_dir} ]]; then
                    checkout_local ${fetch_dir} ${fetch_url} ${fetch_branch} ${def_remote_name} || err_exit "local checkout failed"
                else
                    err_exit "${fetch_dir} does not exist, can't checkout locally"
                fi
            else
                err_exit "internal error: no action set?"
            fi

            msg_verbose "line:${YELLOW}${line_num}${NORM} Done"
            echo

        else
            msg_verbose "${summary}"
            msg_verbose "local git head:${RED}${cur_git_id}${NORM} does not match rule: ${YELLOW}${branch_regex}${NORM}"
            echo
        fi

    elif [[ ${#cols[@]} > 0 ]]; then
        msg_red "illegal syntax, cols:${#cols[@]} expected:${num_cols}"
        err_exit "line ${line_num}: \"${cols[@]}\""
    fi

    (( line_num++ ))

done < <(./multi-repo.py ${CFG_PATH})
#done < <(sed '/^[[:blank:]]*#/d;s/#.*//' ${CFG_PATH})

