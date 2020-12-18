#!/bin/bash
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

DEF_BUILD_DIR='build'
DEF_INSTALL_SUBDIR='install'
DEF_MAKE_TARGET='install'
DEF_CONFIG='Debug'
DEF_USE_APP_NAME=

DEF_RELEASE_DIR=`readlink -e ~/release`

CMAKE_MIN_VER="3.12"

SCRIPT_NAME="$(basename $0)"
BUILD_ROOT="$(dirname $0)"
TOOLS_ROOT="${BUILD_ROOT}/build-runner"

TARPACK_PY="${TOOLS_ROOT}/pack/tarpack.py"
GIT_PULL_SH="${TOOLS_ROOT}/git/git_pull.sh"
UTEST_SH="${TOLS_ROOT}/run/utest.sh"

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

function exit_build()
{
    local ret_code=$1
    if [[ -z "${ret_code}" ]]; then
        ret_code=0
    fi
    local exit_msg=$2

    if [[ ${ret_code} != 0 ]]; then
        [[ -n "${exit_msg}" ]] && msg_red "\n${exit_msg}"
        msg_red "\n${SCRIPT_NAME} exit on error..."
    else
        [[ -n "${exit_msg}" ]] && msg_green "\n${exit_msg}"
        msg_green "\n${SCRIPT_NAME} done"
    fi
    exit ${ret_code}
}

function usage()
{
    echo -e "Usage: ${BLUE}${SCRIPT_NAME}${NORM} [options] ${BLUE}--${NORM} [make-options]\n"
    echo -e "scope options:"
    echo -e "${BLUE}-a | --app [name]${NORM}: application"
    echo -e "${BLUE}-m | --module [name]${NORM}: single module dir"
    echo -e "   (*) ${BLUE}-a${NORM} and ${BLUE}-m${NORM} are mutually exclusive, one is mandatory"
    echo -e "GIT ops:"
    echo -e "${BLUE}-u | --seed-url [git-url]${NORM}: clone the seed repo, pull using its configuraton"
    echo -e "${BLUE}-d | --seed-dir [dir-name]${NORM}: pull the seed dir and its dependencies"
    echo -e "   (*) ${BLUE}-u${NORM} and ${BLUE}-d${NORM} are mutually exclusive"
    echo -e "${BLUE}-B | --seed-branch [branch]${NORM}: checkout branch in the seed repo"
    echo -e "${BLUE}-R | --seed-remote [remote-name]${NORM}: rename git remote after clone or pull using this remote"
    echo -e "Build ops:"
    echo -e "${BLUE}-M | --make${NORM}: perform the build using CMake"
    echo -e "${BLUE}-P | --pack${NORM}: package all products into a tarball"
    echo -e "${BLUE}-U | --ut${NORM}: run all unit tests"
    echo
    echo -e "${BLUE}-b | --build-dir [dir]${NORM}: alternative build dir [${DEF_BUILD_DIR}]"
    echo -e "${BLUE}-i | --install-dir [dir]${NORM}: alternative install dir [build_dir/${DEF_INSTALL_SUBDIR}]"
    echo -e "${BLUE}-r | --release-dir [dir]${NORM}: tar.gz release dir [${DEF_RELEASE_DIR}]"
    echo
    echo -e "${BLUE}-t | --target [name]${NORM}: target name passed to make [${DEF_MAKE_TARGET}]"
    echo -e "${BLUE}-C | --clean${NORM}: remove both the build and install dirs"
    echo -e "   module or app-specific removal unsupported yet"
    echo -e "   for regular makefile-based clean use: --target clean"
    echo -e "${BLUE}-c | --config ${NORM}: build configuration, [${DEF_CONFIG}]"
    echo -e "   values: ${BLUE}Release, Debug${NORM}"
    echo -e "${BLUE}-T | --tree ${NORM}: single tree build mode, [off]"
    echo -e "${BLUE}-S | --shared ${NORM}: build shared libraries, [static]"
    echo -e "${BLUE}-D | --dry ${NORM}: perform dry run, only print command lines [off]"
    echo -e "${BLUE}-V | --verbose${NORM}: produce verbose output, [off]"
    echo -e "${BLUE}-h | --help   ${NORM}: print the help message"
    echo -e "\nall options after -- will be passed to make"
    echo -e "${BLUE}example${NORM}: ${SCRIPT_NAME} -V -- -j 3\n"
    exit $1
}

function parse_args()
{
    options=$(getopt \
        -o "a:m:u:d:B:R:MPUb:i:r:t:c:CTSDVh" \
        -l "app:,module:,seed-url:,seed-dir:,seed-branch:,seed-remote:,make,pack,ut,build-dir:,install-dir:,release-dir:,target:,config:,clean,tree,shared,dry,verbose,help" \
        -- "$@")
    if [ $? -ne 0 ]; then
        msg_red "${SCRIPT_NAME}: failed to parse arguments\n"
        usage 1
    fi

    eval set -- ${options}

    while [ $# -gt 1 ]; do
        case $1 in
            -a|--app) CMD_APP_NAME=$2; shift; ;;
            -m|--module) CMD_MODULE_NAME=$2; shift; ;;

            -u|--seed-url) CMD_OP_GIT_SEED_URL=true;
                    OPS_LIST="${OPS_LIST}seed-url ";
                    CMD_GIT_REPO_URL=$2;
                    shift; ;;
            -d|--seed-dir) CMD_OP_GIT_SEED_DIR=true;
                    OPS_LIST="${OPS_LIST}seed-dir ";
                    CMD_SEED_DIR=$2;
                    shift; ;;

            -B|--seed-branch) CMD_GIT_BRANCH=$2; shift; ;;
            -R|--seed-remote) CMD_GIT_REMOTE=$2; shift; ;;

            -M|--make) CMD_OP_MAKE=true; OPS_LIST="${OPS_LIST}make "; ;;
            -P|--pack) CMD_OP_PACK=true; OPS_LIST="${OPS_LIST}pack "; ;;
            -U|--ut) CMD_OP_UT=true; OPS_LIST="${OPS_LIST}ut "; ;;

            -b|--build-dir) CMD_BUILD_DIR=$2; shift; ;;
            -i|--install-dir) CMD_INSTALL_DIR=$2; shift; ;;
            -r|--release-dir) CMD_RELEASE_DIR=$2; shift; ;;

            -t|--target) CMD_MAKE_TARGET=$2; shift; ;;
            -c|--config) CMD_CONFIG=$2; shift; ;;
            -C|--clean) CMD_CLEAN=true; OPS_LIST="${OPS_LIST}clean "; ;;
            -T|--tree) CMD_SINGLE_TREE=true; ;;
            -S|--shared) SHARED=true; ;;
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

function is_module()
{
    local name="$1"
    local mod_name

    for mod_name in ${MODULES_LIST[*]}; do
        if [[ "${mod_name}" == "${name}" ]]; then
            echo "true"
            return
        fi
    done
    echo "false"
}

function is_3party()
{
    local name="$1"
    local mod_name

    for mod_name in ${MOD3P_LIST[*]}; do
        if [[ "${mod_name}" == "${name}" ]]; then
            echo "true"
            return
        fi
    done
    echo "false"
}

function is_app()
{
    local name="$1"
    local app_name

    for app_name in ${APPS_LIST[*]}; do
        if [[ "${app_name}" == "${name}" ]]; then
            echo "true"
            return
        fi
    done
    echo "false"
}

function get_app_index()
{
    local name="$1"
    local app_name i

    for (( i=0; i < ${#APPS_LIST[*]}; i++ )); do
        app_name=${APPS_LIST[${i}]}
        if [[ "${app_name}" == "${name}" ]]; then
            echo "$i"
            return
        fi
    done
}

function get_app_main_dir()
{
    local name="$1"
    local app_idx

    app_idx=`get_app_index ${name}`
    if [[ -z "${app_idx}" ]]; then
        msg_red "failed to find app: ${name}"
        exit_build 1
    fi

    echo "${APP_MAIN_MODULE_LIST[${app_idx}]}"
}

function get_app_submod_list()
{
    local name="$1"
    local app_idx

    app_idx=`get_app_index ${name}`
    if [[ -z "${app_idx}" ]]; then
        msg_red "failed to find app: ${name}"
        exit_build 1
    fi

    echo "${APP_SUBMOD_LIST[${app_idx}]}"
}

function get_app_3pmod_list()
{
    local name="$1"
    local app_idx

    app_idx=`get_app_index ${name}`
    if [[ -z "${app_idx}" ]]; then
        msg_red "failed to find app: ${name}"
        exit_build 1
    fi

    echo "${APP_3PARTY_LIST[${app_idx}]}"
}

function read_config()
{
    local CFG_PATH="$1"
    local line_num decl_type module_name app_name token alias_name
    local new_index app_modules i def_type

    SPTED_DECLS="MODULE|3PARTY|APP|DEFAULT"
    line_num=1
    while IFS=' ,|' read -a cols; do
        if [[ ${#cols[*]} == 0 ]]; then
            continue
        fi
        # use eval to allow variables in the strings
        eval "decl_type=${cols[0]}"

        case "${decl_type}" in
        MODULE)
            eval "module_name=${cols[1]}"
            MODULES_LIST=(${MODULES_LIST[*]} ${module_name})
            ;;
        3PARTY)
            eval "module_name=${cols[1]}"
            MOD3P_LIST=(${MOD3P_LIST[*]} ${module_name})
            ;;
        APP)
            eval "app_name=${cols[1]}"

            eval "token=${cols[2]}"
            if [[ "${token}" != "ALIAS" ]]; then
                msg_red "illegal syntax, expected: ALIAS, found: ${token}"
                exit_build 1 "line ${line_num}: \"${cols[@]}\""
            fi
            eval "alias_name=${cols[3]}"
            ALIAS_LIST=(${ALIAS_LIST[*]} ${alias_name})

            eval "token=${cols[4]}"
            if [[ "${token}" != "MODULE" ]]; then
                msg_red "illegal syntax, expected: MODULE, found: ${token}"
                exit_build 1 "line ${line_num}: \"${cols[@]}\""
            fi
            eval "main_name=${cols[5]}"
            APP_MAIN_MODULE_LIST=(${APP_MAIN_MODULE_LIST[*]} ${main_name})

            eval "token=${cols[6]}"
            if [[ "${token}" != "SUBMODULES" ]]; then
                msg_red "illegal syntax, expected: SUBMODULES, found: ${token}"
                exit_build 1 "line ${line_num}: \"${cols[@]}\""
            fi
            new_index=${#APPS_LIST[*]}
            APPS_LIST=(${APPS_LIST[*]} ${app_name})
            if [[ -z "${cols[3]}" ]]; then
                msg_red "illegal syntax, list of modules expected after: SUBMODULES, none found"
                exit_build 1 "line ${line_num}: \"${cols[@]}\""
            fi
            unset app_modules app_3party
            for (( i=7; i < ${#cols[*]}; i++ )) ; do
                eval "mod_name=${cols[${i}]}"
                if [[ `is_module ${mod_name}` == "true" ]]; then
                    app_modules="${app_modules} ${mod_name}"
                elif [[ `is_3party ${mod_name}` == "true" ]]; then
                    app_3party="${app_3party} ${mod_name}"
                else
                    msg_red "module: ${mod_name} not found"
                    exit_build 1 "line ${line_num}: \"${cols[@]}\""
                fi
            done
            APP_SUBMOD_LIST[${new_index}]="${app_modules}"
            APP_3PARTY_LIST[${new_index}]="${app_3party}"
            ;;
        DEFAULT)
            eval "def_type=${cols[1]}"
            eval "def_token=${cols[2]}"
            case "${def_type}" in
            APP)
                DEF_USE_APP_NAME="${def_token}"
                ;;
             TARGET)
                DEF_MAKE_TARGET="${def_token}"
                ;;
            *)
                msg_red "illegal syntax, unexpected DEFAULT type: ${def_type} expected: APP|TARGET"
                exit_build 1 "line ${line_num}: \"${cols[@]}\""
                ;;
            esac
            ;;
        *)
            msg_red "illegal syntax, unexpected decl type: ${decl_type} supported: ${SPTED_DECLS}"
            exit_build 1 "line ${line_num}: \"${cols[@]}\""
            ;;
        esac

        (( line_num++ ))
    done < <(sed '/^[[:blank:]]*#/d;s/#.*//' ${CFG_PATH})

    echo -e "Modules : ${YELLOW}${MODULES_LIST[*]}${NORM}"
    echo -e "3d-party: ${YELLOW}${MOD3P_LIST[*]}${NORM}"
    echo "Apps:"
    for (( i=0; i<${#APPS_LIST[*]}; i++ )); do
        echo -ne "${YELLOW}${APPS_LIST[${i}]}${NORM} "
        echo -ne "alias: ${YELLOW}${ALIAS_LIST[${i}]}${NORM} "
        echo -ne "main module: ${YELLOW}${APP_MAIN_MODULE_LIST[${i}]}${NORM} "
        echo -ne "submodules: ${YELLOW}${APP_SUBMOD_LIST[${i}]}${NORM} "
        echo -ne "3rd-party: ${YELLOW}${APP_3PARTY_LIST[${i}]}${NORM}"
        echo
    done
}

function generate_single_tree_cmake()
{
    local cmake_ver="$1"
    shift
    local proj_name="$1"
    shift
    local cmake_name="CMakeLists.txt"

    echo -e "# ${cmake_name} - auto-generated `date +'%D %T'`" > ${cmake_name}
    echo -e "cmake_minimum_required(VERSION ${cmake_ver})" >> ${cmake_name}
    echo -e "project(${proj_name})\n" >> ${cmake_name}
    echo -e "set(SINGLE_TREE YES)\n" >> ${cmake_name}
    for d in $*; do
        echo -e "add_subdirectory(${d})" >> ${cmake_name}
    done
}

function build_module()
{
    local _MODULE_NAME="$1"
    shift
    local _BUILD_TARGET="$1"
    shift
    local _CMAKE_ARGS="$@"

    if [[ "${_MODULE_NAME}" == "." ]]; then
        msg_yellow "Generate: single-tree CMakeLists.txt ${_CMAKE_ARGS}\n"

        local _MODULE_SRC_DIR="${BUILD_ROOT}"
        local _MODULE_BUILD_DIR="${BUILD_DIR}"
    else
        msg_yellow "\nMODULE START: ${_MODULE_NAME}"
        msg_green "Generate: ${_MODULE_NAME} ${_CMAKE_ARGS}\n"

        local _MODULE_SRC_DIR="${BUILD_ROOT}/${_MODULE_NAME}"
        local _MODULE_BUILD_DIR="${BUILD_DIR}/${_MODULE_NAME}"
    fi

    # cmake -H <home-dir> -B <build-dir>
    if [[ "${DRY_RUN}" == true ]]; then
        echo "cmake -H${_MODULE_SRC_DIR}" \
        "-B${_MODULE_BUILD_DIR}" \
        "-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}" \
        "-DCMAKE_PREFIX_PATH=${INSTALL_DIR}" \
        "${OPT_SHARED}" \
        "${OPT_VERBOSE}" \
        "${OPT_BUILD_TYPE}" \
        "${_CMAKE_ARGS}"
    else
        cmake -H${_MODULE_SRC_DIR} \
        -B${_MODULE_BUILD_DIR} \
        -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
        -DCMAKE_PREFIX_PATH=${INSTALL_DIR} \
        ${OPT_SHARED} \
        ${OPT_VERBOSE} \
        ${OPT_BUILD_TYPE} \
        ${_CMAKE_ARGS} || return 1
    fi

    if [[ "${_MODULE_NAME}" == "." ]]; then
        msg_yellow "\nBuild: single-tree CMakeLists.txt ${_CMAKE_ARGS}, target: ${_BUILD_TARGET}\n"
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        echo "cmake --build ${_MODULE_BUILD_DIR}" \
        "--target ${_BUILD_TARGET}" \
        "${extra_args}"
    else
        cmake --build ${_MODULE_BUILD_DIR} \
        --target ${_BUILD_TARGET} \
        ${extra_args} || return 1
    fi

    msg_yellow "\nMODULE DONE: ${_MODULE_NAME} ${_CMAKE_ARGS}, target: ${_BUILD_TARGET}"
}

function build_module_3rd_party()
{
    local _MODULE_NAME="$1"
    shift
    local _BUILD_TARGET="$1"
    shift
    local _CMAKE_ARGS="$@"

    msg_green "\nEXTERNAL BUILD - START: ${_MODULE_NAME}"
    build_module ${_MODULE_NAME} ${_BUILD_TARGET} ${_CMAKE_ARGS} -DBUILD_3RD_PARTY:BOOL=ON || exit_build 1
    msg_green "EXTERNAL BUILD - DONE: ${_MODULE_NAME}"

    msg_green "\nEXTERNAL EXPORT - START: ${_MODULE_NAME}"
    build_module ${_MODULE_NAME} ${MAKE_TARGET} ${_CMAKE_ARGS} -DBUILD_3RD_PARTY:BOOL=OFF || exit_build 1
    msg_green "EXTERNAL EXPORT - DONE: ${_MODULE_NAME}"
}

function build_app() # args: app_name {module-dir-list}
{
    local app_name=$1
    shift

    msg_green "\nAPP START: ${app_name} dirs: $@"
    if [[ "${CMD_SINGLE_TREE}" = true ]]; then
        generate_single_tree_cmake "${CMAKE_MIN_VER}" ${app_name} $@
        build_module "." ${MAKE_TARGET} || exit_build 1
    else
        local mod_dir
        for mod_dir in $@; do
            build_module ${mod_dir} ${MAKE_TARGET} || exit_build 1
        done
    fi
    msg_green "\nAPP DONE: ${app_name}"
}

function current_branch()
{
    local work_dir="$1"
    local dir_opt
    [[ -n "${work_dir}" ]] && dir_opt="-C ${work_dir}"
    git ${dir_opt} symbolic-ref -q --short HEAD 2>/dev/null
}

function current_tag()
{
    local work_dir="$1"
    local dir_opt
    [[ -n "${work_dir}" ]] && dir_opt="-C ${work_dir}"
    git ${dir_opt} describe --tags --exact-match HEAD 2>/dev/null
}

function current_commit_id()
{
    local work_dir="$1"
    local dir_opt
    [[ -n "${work_dir}" ]] && dir_opt="-C ${work_dir}"
    git ${dir_opt} rev-parse HEAD 2>/dev/null
}

function current_git_head_string()
{
    local work_dir="$1"
    local id
    local tag
    local br
    local str

    id=`current_commit_id ${work_dir}` || return $?
    tag=`current_tag ${work_dir}`
    br=`current_branch ${work_dir}`

    if [[ -n "${br}" ]]; then
        str="${str}${br}"
    else
        str="${str}[detached]"
    fi
    [[ -n "${tag}" ]] && str="${str}${tag}"
    str="${str}-${id:0:7}"

    echo "${str}" # print retval
}

function tarpack_app()
{
    local app_dir="$1"; shift
    local app_type="$1"; shift
    local app_version="$1"; shift
    local tar_links_dir="$1"; shift
    local release_dir="$1"; shift

    local yaml_name="tarpack.yaml"
    local tar_path="${release_dir}/pack_${app_type}_${app_version}.tgz"

    msg_yellow "Create tarpack for ${app_type} ver ${app_version} --> ${tar_path}"
    msg_yellow "tarpack symlinks dir: ${tar_links_dir}"
    ${TARPACK_PY} --dir ${app_dir} --yaml ${yaml_name} --tag ${app_type} --out ${tar_path} --tar-dir ${tar_links_dir} || exit_build 1
}

read_config "build.cfg"

# parse command line arguments
args="$@"
normal_args="${args%%-- *}" # all args until --
if [[ "${normal_args}" != "${args}" ]]; then
    extra_args="${args##* --}" # all args after --
fi
parse_args ${normal_args}

if [[ -n "${normal_args}" ]]; then
    msg_blue "Args: ${normal_args}"
else
    msg_blue "Args: None"
fi
if [[ -n "${extra_args}" ]]; then
    msg_blue "Extra args: ${extra_args}"
else
    msg_blue "Extra args: None"
fi

# check if required args are missing or mutually exclusive args supplied
if [[ -z "${CMD_APP_NAME}" && -z "${CMD_MODULE_NAME}" ]]; then
    exit_build 1 "neither --app nor --module supplied"
elif [[ -n "${CMD_APP_NAME}" && -n "${CMD_MODULE_NAME}" ]]; then
    exit_build 1 "both --app and --module args can't be accepted"
fi

if [[ -n "${CMD_OP_GIT_SEED_URL}" && -n "${CMD_OP_GIT_SEED_DIR}" ]]; then
    exit_build 1 "both --seed-url and --seed-dir args can't be accepted"
fi

if [[ -z "${OPS_LIST}" ]]; then
    msg_yellow "no ops supplied, assuming --make"
    CMD_OP_MAKE=true
    OPS_LIST="make"
fi

# apply default arg values if necessary
if [ -n "${CMD_MODULE_NAME}" ]; then
    if [[ `is_module ${CMD_MODULE_NAME}` == "true" || `is_3party ${CMD_MODULE_NAME}` == "true" ]]; then
        USE_MODULE_NAME="${CMD_MODULE_NAME}"
    else
        msg_red "module: ${CMD_MODULE_NAME} is undefined"
        exit_build 1
    fi

    if [[ ! -d "${USE_MODULE_NAME}" ]]; then
        msg_red "module directory: ${USE_MODULE_NAME} does not exist"
        exit_build 1
    fi
else
    USE_APP_NAME=${CMD_APP_NAME:-${DEF_USE_APP_NAME}}
    if [[ `is_app ${USE_APP_NAME}` != "true" ]]; then
        # ToDo: find app by alias
        msg_red "app: ${USE_MODULE_NAME} is undefined"
        exit_build 1
    fi
fi

BUILD_DIR=${CMD_BUILD_DIR:-${BUILD_ROOT}/${DEF_BUILD_DIR}}
BUILD_PATH=`eval readlink -m ${BUILD_DIR}` || exit_build 1 "build dir not found: ${BUILD_DIR}"

INSTALL_DIR=${CMD_INSTALL_DIR:-${BUILD_DIR}/${DEF_INSTALL_SUBDIR}}
INSTALL_PATH=`eval readlink -m ${INSTALL_DIR}` || exit_build 1 "install dir not found: ${INSTALL_DIR}"
INSTALL_DIR="${INSTALL_PATH}"

RELEASE_DIR="${CMD_RELEASE_DIR:-${DEF_RELEASE_DIR}}"
RELEASE_PATH=`eval readlink -m ${RELEASE_DIR}` || exit_build 1 "release dir not found: ${RELEASE_DIR}"
RELEASE_DIR="${RELEASE_PATH}"

MAKE_TARGET=${CMD_MAKE_TARGET:-${DEF_MAKE_TARGET}}

if [[ "${SHARED}" = true ]]; then
    OPT_SHARED="-DBUILD_SHARED:BOOL=ON"
else
    OPT_SHARED="-DBUILD_SHARED:BOOL=OFF"
fi

if [[ "${VERBOSE}" = true ]]; then
    OPT_VERBOSE="-DVERBOSE_MAKE:BOOL=ON"
else
    OPT_VERBOSE="-DVERBOSE_MAKE:BOOL=OFF"
fi

OPT_BUILD_TYPE="-DBUILD_TYPE:STRING=${CMD_CONFIG:-${DEF_CONFIG}}"

# print out the build parameters
if [[ -n "${USE_MODULE_NAME}" ]]; then
    msg_blue "module: ${USE_MODULE_NAME}"
else
    msg_blue "app: ${USE_APP_NAME}"
fi
msg_blue "ops: ${OPS_LIST}"
msg_blue "build dir: ${BUILD_DIR}, install dir: ${INSTALL_DIR}, release dir: ${RELEASE_DIR}"
if [[ "${CMD_SINGLE_TREE}" = true ]]; then
    msg_blue "build mode: single-tree"
else
    msg_blue "build mode: package-wise"
fi
msg_blue "make target: ${MAKE_TARGET}"
msg_blue "${OPT_BUILD_TYPE} ${OPT_SHARED} ${OPT_VERBOSE}"

[[ -n "${USE_APP_NAME}" ]] && app_dir=`get_app_main_dir ${USE_APP_NAME}`

# perform GIT update step if requested
if [[ "${CMD_OP_GIT_SEED_URL}" == true ]]; then
    [[ -z "${CMD_GIT_BRANCH}" ]] && exit_build 1 "no git branch supplied"
    [[ -n "${CMD_GIT_REMOTE}" ]] && GIT_REMOTE_ARG="-n ${CMD_GIT_REMOTE}"
    export BUILD_ROOT
    ${GIT_PULL_SH} -u ${CMD_GIT_REPO_URL} -b ${CMD_GIT_BRANCH} ${GIT_REMOTE_ARG} --pull || exit_build 1
elif [[ "${CMD_OP_GIT_SEED_DIR}" == true ]]; then
    [[ ! -d ${CMD_SEED_DIR} ]] && exit_build 1 "directory: ${app_dir} for app: ${USE_APP_NAME} not found"
    [[ -z "${CMD_GIT_BRANCH}" ]] && exit_build 1 "no git branch supplied"
    [[ -n "${CMD_GIT_REMOTE}" ]] && GIT_REMOTE_ARG="-n ${CMD_GIT_REMOTE}"
    export BUILD_ROOT
    ${GIT_PULL_SH} -d ${CMD_SEED_DIR} -b ${CMD_GIT_BRANCH} ${GIT_REMOTE_ARG} --pull || exit_build 1
fi

# perform total clean step if requested
if [[ "${CMD_CLEAN}" == true ]]; then
    msg_yellow "\nTotal clean"
    msg_blue "Remove ${INSTALL_DIR}"
    rm -rf ${INSTALL_DIR}
    msg_blue "Remove ${BUILD_DIR}"
    rm -rf ${BUILD_DIR}
fi

# perform build step if requested
if [[ "${CMD_OP_MAKE}" == true ]]; then
    if [ -n "${USE_MODULE_NAME}" ]; then
        if [[ `is_3party ${USE_MODULE_NAME}` == "true" ]]; then
            build_module_3rd_party ${USE_MODULE_NAME} ${MAKE_TARGET} || exit_build 1
        else
            build_module ${USE_MODULE_NAME} ${MAKE_TARGET} || exit_build 1
        fi
    else
        app_submodules=`get_app_submod_list ${USE_APP_NAME}`
        app_3p_modules=`get_app_3pmod_list ${USE_APP_NAME}`

        # build 3party modules serially
        for app_3pmod in ${app_3p_modules}; do
            build_module_3rd_party ${app_3pmod} ${MAKE_TARGET} || exit_build 1
        done

        # now build the app according to the conf
        build_app ${USE_APP_NAME} ${app_submodules} ${app_dir}
    fi
fi

# perform tarpack step if requested
if [[ "${CMD_OP_PACK}" == true ]]; then
    if [ -n "${USE_APP_NAME}" ]; then
        git_ver=`current_git_head_string ${app_dir}`
        msg_yellow "GIT version in ${app_dir}: ${git_ver}"

        mkdir -p "${RELEASE_DIR}" || exit_build 1

        export INSTALL_PATH

        app_types="col bbx rgw"
        for app_t in ${app_types}; do
            tarpack_app "${app_dir}" "${app_t}" "${git_ver}" "${BUILD_PATH}" "${RELEASE_DIR}"
        done
    fi
fi

# perform unit test step if requested
if [[ "${CMD_OP_UT}" == true ]]; then
    if [ -n "${USE_APP_NAME}" ]; then
        app_submodules=`get_app_submod_list ${USE_APP_NAME}`
    else
        exit_build 1 "no app name supplied"
    fi

    for ut_mod in ${app_dir} ${app_submodules}; do
        UTEST_PATH="${INSTALL_DIR}/${ut_mod}/utest"
        if [[ -d ${UTEST_PATH} ]]; then
            msg_green "${ut_mod} utests start"
            ${UTEST_SH} -d ${UTEST_PATH}
            msg_green "${ut_mod} utests done"
        else
            msg_red "utest dir: ${UTEST_PATH} does not exist"
        fi
    done
fi

exit_build 0
