#!/usr/bin/env bash
#
# Yamada Hayao
# Twitter: @Hayao0819
# Email  : hayao@fascone.net
#
# (c) 2019-2020 Fascode Network.
#
# build.sh
#
# The main script that runs the build
#

set -e
# set -u
script_path="$(readlink -f ${0%/*})"

# alteriso settings
#
# Do not change this variable.
# To change the settings permanently, edit the config file.

arch=$(uname -m)

os_name="Alter Linux"
iso_name=alterlinux
iso_label="ALTER_$(date +%Y%m)"
iso_publisher='Fascode Network <https://fascode.net>'
iso_application="${os_name} Live/Rescue CD"
iso_version=$(date +%Y.%m.%d)
install_dir=alter
work_dir=work
out_dir=out
gpg_key=

# AlterLinux additional settings
password='alter'
boot_splash=false
kernel='zen'
theme_name="alter-logo"
theme_pkg="plymouth-theme-alter-logo-git"
sfs_comp="zstd"
sfs_comp_opt=""
bash_debug=false
debug=false
rebuild=false
japanese=false
channel_name='xfce'
cleaning=false
username='alter'
mkalteriso="${script_path}/system/mkalteriso"
usershell="/bin/bash"
noconfirm=false
nodepend=false
rebuildfile="${work_dir}/build_options"
dependence=(
    "alterlinux-keyring"
#   "archiso"
    "arch-install-scripts"
    "curl"
    "dosfstools"
    "git"
    "libburn"
    "libisofs"
    "lz4"
    "lzo"
    "make"
    "squashfs-tools"
    "libisoburn"
 #  "lynx"
    "xz"
    "zlib"
    "zstd"
)


# Load config file
[[ -f "${script_path}"/config ]] && source "${script_path}"/config


umask 0022


# Color echo
# usage: echo_color -b <backcolor> -t <textcolor> -d <decoration> [Text]
#
# Text Color
# 30 => Black
# 31 => Red
# 32 => Green
# 33 => Yellow
# 34 => Blue
# 35 => Magenta
# 36 => Cyan
# 37 => White
#
# Background color
# 40 => Black
# 41 => Red
# 42 => Green
# 43 => Yellow
# 44 => Blue
# 45 => Magenta
# 46 => Cyan
# 47 => White
#
# Text decoration
# You can specify multiple decorations with ;.
# 0 => All attributs off (ノーマル)
# 1 => Bold on (太字)
# 4 => Underscore (下線)
# 5 => Blink on (点滅)
# 7 => Reverse video on (色反転)
# 8 => Concealed on

echo_color() {
    local backcolor
    local textcolor
    local decotypes
    local echo_opts
    local arg
    local OPTIND
    local OPT

    echo_opts="-e"

    while getopts 'b:t:d:n' arg; do
        case "${arg}" in
            b) backcolor="${OPTARG}" ;;
            t) textcolor="${OPTARG}" ;;
            d) decotypes="${OPTARG}" ;;
            n) echo_opts="-n -e"     ;;
        esac
    done

    shift $((OPTIND - 1))

    echo ${echo_opts} "\e[$([[ -v backcolor ]] && echo -n "${backcolor}"; [[ -v textcolor ]] && echo -n ";${textcolor}"; [[ -v decotypes ]] && echo -n ";${decotypes}")m${@}\e[m"
}


# Show an INFO message
# $1: message string
_msg_info() {
    local echo_opts="-e"
    local arg
    local OPTIND
    local OPT
    while getopts 'n' arg; do
        case "${arg}" in
            n) echo_opts="${echo_opts} -n" ;;
        esac
    done
    shift $((OPTIND - 1))
    echo ${echo_opts} "$( echo_color -t '36' '[build.sh]')    $( echo_color -t '32' 'Info') ${@}"
}


# Show an Warning message
# $1: message string
_msg_warn() {
    local echo_opts="-e"
    local arg
    local OPTIND
    local OPT
    while getopts 'n' arg; do
        case "${arg}" in
            n) echo_opts="${echo_opts} -n" ;;
        esac
    done
    shift $((OPTIND - 1))
    echo ${echo_opts} "$( echo_color -t '36' '[build.sh]') $( echo_color -t '33' 'Warning') ${@}" >&2
}


# Show an debug message
# $1: message string
_msg_debug() {
    local echo_opts="-e"
    local arg
    local OPTIND
    local OPT
    while getopts 'n' arg; do
        case "${arg}" in
            n) echo_opts="${echo_opts} -n" ;;
        esac
    done
    shift $((OPTIND - 1))
    if [[ ${debug} = true ]]; then
        echo ${echo_opts} "$( echo_color -t '36' '[build.sh]')   $( echo_color -t '35' 'Debug') ${@}"
    fi
}


# Show an ERROR message then exit with status
# $1: message string
# $2: exit code number (with 0 does not exit)
_msg_error() {
    local echo_opts="-e"
    local _error="$2"
    local arg
    local OPTIND
    local OPT
    local OPTARG
    while getopts 'n' arg; do
        case "${arg}" in
            n) echo_opts="${echo_opts} -n" ;;
        esac
    done
    shift $((OPTIND - 1))
    echo ${echo_opts} "$( echo_color -t '36' '[build.sh]')   $( echo_color -t '31' 'Error') ${1}" >&2
    if [[ -n "${_error}" ]]; then
        exit ${_error}
    fi
}


_usage () {
    echo "usage ${0} [options] [channel]"
    echo
    echo " General options:"
    echo
    echo "    -b                 Enable boot splash"
    echo "                        Default: disable"
    echo "    -j                 Enable Japanese mode."
    echo "                        Default: disable"
    echo "    -l                 Enable post-build cleaning."
    echo "                        Default: disable"
    echo "    -d                 Enable debug messages."
    echo "                        Default: disable"
    echo "    -x                 Enable bash debug mode.(set -xv)"
    echo "                        Default: disable"
    echo "    -h                 This help message and exit."
    echo
    echo "    -c <comp_type>     Set SquashFS compression type (gzip, lzma, lzo, xz, zstd)"
    echo "                        Default: ${sfs_comp}"
    echo "    -g <gpg_key>       Set gpg key"
    echo "                        Default: ${gpg_key}"
    echo "    -k <kernel>        Set special kernel type."
    echo "                       See below for available kernels."
    echo "                        Default: zen"
    echo "    -o <out_dir>       Set the output directory"
    echo "                        Default: ${out_dir}"
    echo "    -p <password>      Set a live user password"
    echo "                        Default: ${password}"
    echo "    -t <options>       Set compressor-specific options."
    echo "                        Default: empty"
    echo "    -u <username>      Set user name."
    echo "                        Default: ${username}"
    echo "    -w <work_dir>      Set the working directory"
    echo "                        Default: ${work_dir}"
    echo
    echo "    --noconfirm        Does not check the settings before building."
    echo "    --nodepend         Do not check package dependencies before building."
    echo
    echo "A list of kernels available for each architecture."
    echo
    local kernel
    local list
    for list in $(ls ${script_path}/system/kernel_list-*); do
        echo " ${list#${script_path}/system/kernel_list-}:"
        echo -n "    "
        for kernel in $(grep -h -v ^'#' ${list}); do
            echo -n "${kernel} "
        done
        echo
    done
    echo
    echo "You can switch between installed packages, files included in images, etc. by channel."
    echo
    echo " Channel:"
    for i in $(ls -l "${script_path}"/channels/ | awk '$1 ~ /d/ {print $9 }'); do
        if [[ -n $(ls "${script_path}"/channels/${i}) ]]; then
            if [[ ! ${i} = "share" ]]; then
                if [[ ! $(echo "${i}" | sed 's/^.*\.\([^\.]*\)$/\1/') = "add" ]]; then
                    if [[ ! -d "${script_path}/channels/${i}.add" ]]; then
                        channel_list="${channel_list[@]} ${i}"
                    fi
                else
                    channel_list="${channel_list[@]} ${i}"
                fi
            fi
        fi
    done
    channel_list="${channel_list[@]} rebuild"
    for _channel in ${channel_list[@]}; do
        if [[ -f "${script_path}/channels/${_channel}/description.txt" ]]; then
            description=$(cat "${script_path}/channels/${_channel}/description.txt")
        elif [[ "${_channel}" = "rebuild" ]]; then
            description="Rebuild using the settings of the previous build."
        else
            description="This channel does not have a description.txt."
        fi
        if [[ $(echo "${_channel}" | sed 's/^.*\.\([^\.]*\)$/\1/') = "add" ]]; then
            echo -ne "    $(echo ${_channel} | sed 's/\.[^\.]*$//')"
            for i in $( seq 1 $(( 23 - ${#_channel} )) ); do
                echo -ne " "
            done
        else
            echo -ne "    ${_channel}"
            for i in $( seq 1 $(( 19 - ${#_channel} )) ); do
                echo -ne " "
            done
        fi
        echo -ne "${description}\n"
    done


    exit "${1}"
}


# Check the value of a variable that can only be set to true or false.
check_bool() {
    local 
    case $(eval echo '$'${1}) in
        true | false) : ;;
                   *) _msg_error "The value ${boot_splash} set is invalid" "1";;
    esac
}

check_bool boot_splash
check_bool debug
check_bool bash_debug
check_bool rebuild
check_bool japanese
check_bool cleaning
check_bool noconfirm

# Unmount chroot dir
umount_chroot () {
    local mount
    for mount in $(mount | awk '{print $3}' | grep $(realpath ${work_dir}) | tac); do
        _msg_info "Unmounting ${mount}"
        umount "${mount}"
    done
}

# Helper function to run make_*() only one time.
run_once() {
    if [[ ! -e "${work_dir}/build.${1}_${arch}" ]]; then
        _msg_debug "Running $1 ..."
        "$1"
        touch "${work_dir}/build.${1}_${arch}"
        umount_chroot
    else
        _msg_debug "Skipped because ${1} has already been executed."
    fi
}


# rm helper
# Delete the file if it exists.
# For directories, rm -rf is used.
# If the file does not exist, skip it.
# remove <file> <file> ...
remove() {
    local _list
    local _file
    _list=($(echo "$@"))
    for _file in "${_list[@]}"; do
        _msg_debug "Removeing ${_file}"
        if [[ -f ${_file} ]]; then
            rm -f "${_file}"
        elif [[ -d ${_file} ]]; then
            rm -rf "${_file}"
        fi
    done
}


# Preparation for build
prepare_build() {
    # Check architecture for each channel
    if [[ ! "${channel_name}" = "rebuild" ]]; then
        if [[ -z $(cat ${script_path}/channels/${channel_name}/architecture | grep -h -v ^'#' | grep -x "${arch}") ]]; then
            _msg_error "${channel_name} channel does not support current architecture (${arch})." "1"
        fi
    fi


    # Create a working directory.
    [[ ! -d "${work_dir}" ]] && mkdir -p "${work_dir}"


    # Check work dir
    if [[ -n $(ls -a "${work_dir}" 2> /dev/null | grep -xv ".." | grep -xv ".") ]] && [[ ! "${rebuild}" = true ]]; then
        umount_chroot
        _msg_info "Deleting the contents of ${work_dir}..."
        remove "${work_dir%/}"/*
    fi


    # Save build options
    local save_var
    save_var() {
        local out_file="${rebuildfile}"
        local i
        echo "#!/usr/bin/env bash" > "${out_file}"
        echo "# Build options are stored here." >> "${out_file}"
        for i in ${@}; do
            echo -n "${i}=" >> "${out_file}"
            echo -n '"' >> "${out_file}"
            eval echo -n '$'{${i}} >> "${out_file}"
            echo '"' >> "${out_file}"
        done
    }
    if [[ ${rebuild} = false ]]; then
        # If there is pacman.conf for each channel, use that for building
        if [[ -f "${script_path}/channels/${channel_name}/pacman-${arch}.conf" ]]; then
            build_pacman_conf="${script_path}/channels/${channel_name}/pacman-${arch}.conf"
        fi


        # If there is config for each channel. load that.
        if [[ -f "${script_path}/channels/${channel_name}/config.any" ]]; then
            source "${script_path}/channels/${channel_name}/config.any"
            _msg_debug "The settings have been overwritten by the ${script_path}/channels/${channel_name}/config.any"
        fi

        if [[ -f "${script_path}/channels/${channel_name}/config.${arch}" ]]; then
            source "${script_path}/channels/${channel_name}/config.${arch}"
            _msg_debug "The settings have been overwritten by the ${script_path}/channels/${channel_name}/config.${arch}"
        fi


        # Save the value of the variable for use in rebuild.
        save_var \
            arch \
            os_name \
            iso_name \
            iso_label \
            iso_publisher \
            iso_application \
            iso_version \
            install_dir \
            work_dir \
            out_dir \
            gpg_key \
            mkalteriso_option \
            password \
            boot_splash \
            kernel \
            theme_name \
            theme_pkg \
            sfs_comp \
            sfs_comp_opt \
            debug \
            japanese \
            channel_name \
            cleaning \
            username mkalteriso \
            usershell \
            build_pacman_conf
    else
        # Load rebuild file
        source "${work_dir}/build_options"

        # Delete the lock file.
        # remove "$(ls ${work_dir}/* | grep "build.make")"
    fi


    # Unmount
    local mount
    for mount in $(mount | awk '{print $3}' | grep $(realpath ${work_dir})); do
        _msg_info "Unmounting ${mount}"
        umount "${mount}"
    done


    # Generate iso file name.
    if [[ "${japanese}" = true  ]]; then
        if [[ $(echo "${channel_name}" | sed 's/^.*\.\([^\.]*\)$/\1/') = "add" ]]; then
            iso_filename="${iso_name}-$(echo ${channel_name} | sed 's/\.[^\.]*$//')-jp-${iso_version}-${arch}.iso"
        else
            iso_filename="${iso_name}-${channel_name}-jp-${iso_version}-${arch}.iso"
        fi
    else
        if [[ $(echo "${channel_name}" | sed 's/^.*\.\([^\.]*\)$/\1/') = "add" ]]; then
            iso_filename="${iso_name}-$(echo ${channel_name} | sed 's/\.[^\.]*$//')-${iso_version}-${arch}.iso"
        else
            iso_filename="${iso_name}-${channel_name}-${iso_version}-${arch}.iso"
        fi
    fi


    # Check packages
    if [[ ${arch} = $(uname -m) ]]; then
        local installed_pkg
        local installed_ver
        local check_pkg
        local check_failed=false

        installed_pkg=($(pacman -Q | awk '{print $1}'))
        installed_ver=($(pacman -Q | awk '{print $2}'))

        check_pkg() {
            local i
            local ver
            for i in $(seq 0 $(( ${#installed_pkg[@]} - 1 ))); do
                if [[ "${installed_pkg[${i}]}" = ${1} ]]; then
                    ver=$(pacman -Sp --print-format '%v' --config ${build_pacman_conf} ${1} 2> /dev/null)
                    if [[ "${installed_ver[${i}]}" = "${ver}" ]]; then
                        echo -n "installed"
                        return 0
                    elif [[ -z ${ver} ]]; then
                        echo "norepo"
                        return 0
                    else
                        echo -n "old"
                        return 0
                    fi
                fi
            done

            if [[ "${check_failed}" = true ]]; then
                exit 1
            fi
        }
    fi

    # Load loop kernel module
    if [[ -z $(lsmod | awk '{print $1}' | grep -x "loop") ]]; then
        sudo modprobe loop
    fi
}


# Show settings.
show_settings() {
    echo
    if [[ "${boot_splash}" = true ]]; then
        _msg_info "Boot splash is enabled."
        _msg_info "Theme is used ${theme_name}."
    fi
    _msg_info "Use the ${kernel} kernel."
    _msg_info "Live username is ${username}."
    _msg_info "Live user password is ${password}."
    _msg_info "The compression method of squashfs is ${sfs_comp}."
    if [[ $(echo "${channel_name}" | sed 's/^.*\.\([^\.]*\)$/\1/') = "add" ]]; then
        _msg_info "Use the $(echo ${channel_name} | sed 's/\.[^\.]*$//') channel."
    else
        _msg_info "Use the ${channel_name} channel."
    fi
    [[ "${japanese}" = true ]] && _msg_info "Japanese mode has been activated."
    _msg_info "Build with architecture ${arch}."
    echo
    if [[ ${noconfirm} = false ]]; then
        echo "Press Enter to continue or Ctrl + C to cancel."
        read
    else
        :
        #sleep 3
    fi
}


# Setup custom pacman.conf with current cache directories.
make_pacman_conf() {
    _msg_debug "Use ${build_pacman_conf}"
    local _cache_dirs
    _cache_dirs=($(pacman -v 2>&1 | grep '^Cache Dirs:' | sed 's/Cache Dirs:\s*//g'))
    sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n ${_cache_dirs[@]})|g" ${build_pacman_conf} > "${work_dir}/pacman-${arch}.conf"
}

# Base installation, plus needed packages (airootfs)
make_basefs() {
    ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" init
    # ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" -p "haveged intel-ucode amd-ucode memtest86+ mkinitcpio-nfs-utils nbd zsh efitools" install
    ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" -p "bash haveged intel-ucode amd-ucode mkinitcpio-nfs-utils nbd efitools" install

    # Install plymouth.
    if [[ "${boot_splash}" = true ]]; then
        if [[ -n "${theme_pkg}" ]]; then
            ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" -p "plymouth ${theme_pkg}" install
        else
            ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" -p "plymouth" install
        fi
    fi

    # Install kernel.
    if [[ ! "${kernel}" = "core" ]]; then
        ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" -p "linux-${kernel} linux-${kernel}-headers broadcom-wl-dkms" install
    else
        ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" -p "linux linux-headers broadcom-wl" install
    fi
}

# Additional packages (airootfs)
make_packages() {
    # インストールするパッケージのリストを読み込み、配列pkglistに代入します。
    installpkglist() {
        set +e
        local _loadfilelist
        local _pkg
        local _file
        local jplist
        local excludefile
        local excludelist
        local _pkglist

        #-- Detect package list to load --#
        # Append the file in the share directory to the file to be read.

        # Package list for Japanese
        jplist="${script_path}/channels/share/packages.${arch}/jp.${arch}"

        # Package list for non-Japanese
        nojplist="${script_path}/channels/share/packages.${arch}/non-jp.${arch}"

        if [[ "${japanese}" = true ]]; then
            _loadfilelist=($(ls "${script_path}"/channels/share/packages.${arch}/*.${arch} | grep -xv "${nojplist}"))
        else
            _loadfilelist=($(ls "${script_path}"/channels/share/packages.${arch}/*.${arch} | grep -xv "${jplist}"))
        fi


        # Add the files for each channel to the list of files to read.

        # Package list for Japanese
        jplist="${script_path}/channels/${channel_name}/packages.${arch}/jp.${arch}"

        # Package list for non-Japanese
        nojplist="${script_path}/channels/${channel_name}/packages.${arch}/non-jp.${arch}"

        if [[ "${japanese}" = true ]]; then
            # If Japanese is enabled, add it to the list of files to read other than non-jp.
            _loadfilelist=(${_loadfilelist[@]} $(ls "${script_path}"/channels/${channel_name}/packages.${arch}/*.${arch} | grep -xv "${nojplist}"))
        else
            # If Japanese is disabled, add it to the list of files to read other than jp.
            _loadfilelist=(${_loadfilelist[@]} $(ls "${script_path}"/channels/${channel_name}/packages.${arch}/*.${arch} | grep -xv ${jplist}))
        fi


        #-- Read package list --#
        # Read the file and remove comments starting with # and add it to the list of packages to install.
        for _file in ${_loadfilelist[@]}; do
            _msg_debug "Loaded package file ${_file}."
            pkglist=( ${pkglist[@]} "$(grep -h -v ^'#' ${_file})" )
        done
        if [[ ${debug} = true ]]; then
            sleep 3
        fi

        # Exclude packages from the share exclusion list
        excludefile="${script_path}/channels/share/packages.${arch}/exclude"
        if [[ -f "${excludefile}" ]]; then
            excludelist=( $(grep -h -v ^'#' "${excludefile}") )

            # 現在のpkglistをコピーする
            _pkglist=(${pkglist[@]})
            unset pkglist
            for _pkg in ${_pkglist[@]}; do
                # もし変数_pkgの値が配列excludelistに含まれていなかったらpkglistに追加する
                if [[ ! $(printf '%s\n' "${excludelist[@]}" | grep -qx "${_pkg}"; echo -n ${?} ) = 0 ]]; then
                    pkglist=(${pkglist[@]} "${_pkg}")
                fi
            done
        fi

        if [[ -n "${excludelist[@]}" ]]; then
            _msg_debug "The following packages have been removed from the installation list."
            _msg_debug "Excluded packages: ${excludelist[@]}"
        fi

        # Exclude packages from the exclusion list for each channel
        excludefile="${script_path}/channels/${channel_name}/packages.${arch}/exclude"
        if [[ -f "${excludefile}" ]]; then
            excludelist=( $(grep -h -v ^'#' "${excludefile}") )
        
            # 現在のpkglistをコピーする
            _pkglist=(${pkglist[@]})
            unset pkglist
            for _pkg in ${_pkglist[@]}; do
                # もし変数_pkgの値が配列excludelistに含まれていなかったらpkglistに追加する
                if [[ ! $(printf '%s\n' "${excludelist[@]}" | grep -qx "${_pkg}"; echo -n ${?} ) = 0 ]]; then
                    pkglist=(${pkglist[@]} "${_pkg}")
                fi
            done
        fi
            
        
        # Sort the list of packages in abc order.
        pkglist=(
            "$(
                for _pkg in ${pkglist[@]}; do
                    echo "${_pkg}"
                done \
                | sort
            )"
        )


        #-- Debug code --#
        #for _pkg in ${pkglist[@]}; do
        #    echo -n "${_pkg} "
        #done
        # echo "${pkglist[@]}"


        set -e
    }

    installpkglist

    # _msg_debug "${pkglist[@]}"

    # Create a list of packages to be finally installed as packages.list directly under the working directory.
    echo "# The list of packages that is installed in live cd." > ${work_dir}/packages.list
    echo "#" >> ${work_dir}/packages.list
    echo >> ${work_dir}/packages.list
    for _pkg in ${pkglist[@]}; do
        echo ${_pkg} >> ${work_dir}/packages.list
    done

    # Install packages on airootfs
    ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" -p "${pkglist[@]}" install
}

# Customize installation (airootfs)
make_customize_airootfs() {
    # Overwrite airootfs with customize_airootfs.
    local copy_airootfs

    copy_airootfs() {
        local i 
        for i in "${@}"; do
            local _dir="${1%/}"
            if [[ -d "${_dir}" ]]; then
                cp -af "${_dir}"/* "${work_dir}/${arch}/airootfs"
            fi
        done
    }

    copy_airootfs "${script_path}/channels/share/airootfs.any"
    copy_airootfs "${script_path}/channels/share/airootfs.${arch}"
    copy_airootfs "${script_path}/channels/${channel_name}/airootfs.any"
    copy_airootfs "${script_path}/channels/${channel_name}/airootfs.${arch}"

    # Replace /etc/mkinitcpio.conf if Plymouth is enabled.
    if [[ "${boot_splash}" = true ]]; then
        cp "${script_path}/mkinitcpio/mkinitcpio-plymouth.conf" "${work_dir}/${arch}/airootfs/etc/mkinitcpio.conf"
    fi

    # Code to use common pacman.conf in archiso.
    # cp "${script_path}/pacman.conf" "${work_dir}/${arch}/airootfs/etc"
    # cp "${build_pacman_conf}" "${work_dir}/${arch}/airootfs/etc"

    # Get the optimal mirror list.
    local mirrorlisturl
    local mirrorlisturl_all
    local mirrorlisturl_jp


    case "${arch}" in
        "x86_64")
            mirrorlisturl_jp='https://www.archlinux.org/mirrorlist/?country=JP'
            mirrorlisturl_all='https://www.archlinux.org/mirrorlist/?country=all'
            ;;
        "i686")
            mirrorlisturl_jp='https://archlinux32.org/mirrorlist/?country=jp'
            mirrorlisturl_all='https://archlinux32.org/mirrorlist/?country=all'
            ;;
    esac

    if [[ "${japanese}" = true ]]; then
        mirrorlisturl="${mirrorlisturl_jp}"
    else
        mirrorlisturl="${mirrorlisturl_all}"
    fi
    curl -o "${work_dir}/${arch}/airootfs/etc/pacman.d/mirrorlist" "${mirrorlisturl}"

    # Add install guide to /root (disabled)
    # lynx -dump -nolist 'https://wiki.archlinux.org/index.php/Installation_Guide?action=render' >> ${work_dir}/${arch}/airootfs/root/install.txt


    # customize_airootfs.sh options
    # -b            : Enable boot splash.
    # -d            : Enable debug mode.
    # -i <inst_dir> : Set install dir
    # -j            : Enable Japanese.
    # -k <kernel>   : Set kernel name.
    # -o <os name>  : Set os name.
    # -p <password> : Set password.
    # -s <shell>    : Set user shell.
    # -t            : Set plymouth theme.
    # -u <username> : Set live user name.
    # -x            : Enable bash debug mode.
    # -r            : Enable rebuild.


    # Generate options of customize_airootfs.sh.
    local addition_options
    local share_options
    addition_options=
    if [[ ${boot_splash} = true ]]; then
        if [[ -z ${theme_name} ]]; then
            addition_options="${addition_options} -b"
        else
            addition_options="${addition_options} -b -t ${theme_name}"
        fi
    fi
    if [[ ${debug} = true ]]; then
        addition_options="${addition_options} -d"
    fi
    if [[ ${bash_debug} = true ]]; then
        addition_options="${addition_options} -x"
    fi
    if [[ ${japanese} = true ]]; then
        addition_options="${addition_options} -j"
    fi
    if [[ ${rebuild} = true ]]; then
        addition_options="${addition_options} -r"
    fi

    share_options="-p '${password}' -k '${kernel}' -u '${username}' -o '${os_name}' -i '${install_dir}' -s '${usershell}' -a '${arch}'"


    # X permission
    if [[ -f ${work_dir}/${arch}/airootfs/root/customize_airootfs.sh ]]; then
    	chmod 755 "${work_dir}/${arch}/airootfs/root/customize_airootfs.sh"
    fi
    if [[ -f "${work_dir}/${arch}/airootfs/root/customize_airootfs.sh" ]]; then
        chmod 755 "${work_dir}/${arch}/airootfs/root/customize_airootfs.sh"
    fi
    if [[ -f "${work_dir}/${arch}/airootfs/root/customize_airootfs_${channel_name}.sh" ]]; then
        chmod 755 "${work_dir}/${arch}/airootfs/root/customize_airootfs_${channel_name}.sh"
    elif [[ -f "${work_dir}/${arch}/airootfs/root/customize_airootfs_$(echo ${channel_name} | sed 's/\.[^\.]*$//').sh" ]]; then
        chmod 755 "${work_dir}/${arch}/airootfs/root/customize_airootfs_$(echo ${channel_name} | sed 's/\.[^\.]*$//').sh"
    fi

    # Execute customize_airootfs.sh.
    if [[ -z ${addition_options} ]]; then
        ${mkalteriso} ${mkalteriso_option} \
            -w "${work_dir}/${arch}" \
            -C "${work_dir}/pacman-${arch}.conf" \
            -D "${install_dir}" \
            -r "/root/customize_airootfs.sh ${share_options}" \
            run
        if [[ -f "${work_dir}/${arch}/airootfs/root/customize_airootfs_${channel_name}.sh" ]]; then
            ${mkalteriso} ${mkalteriso_option} \
                -w "${work_dir}/${arch}" \
                -C "${work_dir}/pacman-${arch}.conf" \
                -D "${install_dir}" \
                -r "/root/customize_airootfs_${channel_name}.sh ${share_options}" \
                run
        elif [[ -f "${work_dir}/${arch}/airootfs/root/customize_airootfs_$(echo ${channel_name} | sed 's/\.[^\.]*$//').sh" ]]; then
            ${mkalteriso} ${mkalteriso_option} \
                -w "${work_dir}/${arch}" \
                -C "${work_dir}/pacman-${arch}.conf" \
                -D "${install_dir}" \
                -r "/root/customize_airootfs_$(echo ${channel_name} | sed 's/\.[^\.]*$//').sh ${share_options}" \
                run
        fi
    else
        ${mkalteriso} ${mkalteriso_option} \
            -w "${work_dir}/${arch}" \
            -C "${work_dir}/pacman-${arch}.conf" \
            -D "${install_dir}" \
            -r "/root/customize_airootfs.sh ${share_options} ${addition_options}" \
            run

        if [[ -f "${work_dir}/${arch}/airootfs/root/customize_airootfs_${channel_name}.sh" ]]; then
            ${mkalteriso} ${mkalteriso_option} \
                -w "${work_dir}/${arch}" \
                -C "${work_dir}/pacman-${arch}.conf" \
                -D "${install_dir}" \
                -r "/root/customize_airootfs_${channel_name}.sh ${share_options} ${addition_options}" \
                run
        elif [[ -f "${work_dir}/${arch}/airootfs/root/customize_airootfs_$(echo ${channel_name} | sed 's/\.[^\.]*$//').sh" ]]; then
            ${mkalteriso} ${mkalteriso_option} \
                -w "${work_dir}/${arch}" \
                -C "${work_dir}/pacman-${arch}.conf" \
                -D "${install_dir}" \
                -r "/root/customize_airootfs_$(echo ${channel_name} | sed 's/\.[^\.]*$//').sh ${share_options} ${addition_options}" \
                run
        fi
    fi


    # Delete customize_airootfs.sh.
    remove "${work_dir}/${arch}/airootfs/root/customize_airootfs.sh"
    remove "${work_dir}/${arch}/airootfs/root/customize_airootfs_${channel_name}.sh"
}

# Copy mkinitcpio archiso hooks and build initramfs (airootfs)
make_setup_mkinitcpio() {
    local _hook
    mkdir -p "${work_dir}/${arch}/airootfs/etc/initcpio/hooks"
    mkdir -p "${work_dir}/${arch}/airootfs/etc/initcpio/install"
    for _hook in "archiso" "archiso_shutdown" "archiso_pxe_common" "archiso_pxe_nbd" "archiso_pxe_http" "archiso_pxe_nfs" "archiso_loop_mnt"; do
        cp "${script_path}/system/initcpio/hooks/${_hook}" "${work_dir}/${arch}/airootfs/etc/initcpio/hooks"
        cp "${script_path}/system/initcpio/install/${_hook}" "${work_dir}/${arch}/airootfs/etc/initcpio/install"
    done
    sed -i "s|/usr/lib/initcpio/|/etc/initcpio/|g" "${work_dir}/${arch}/airootfs/etc/initcpio/install/archiso_shutdown"
    cp "${script_path}/system/initcpio/install/archiso_kms" "${work_dir}/${arch}/airootfs/etc/initcpio/install"
    cp "${script_path}/system/initcpio/archiso_shutdown" "${work_dir}/${arch}/airootfs/etc/initcpio"
    if [[ "${boot_splash}" = true ]]; then
        cp "${script_path}/mkinitcpio/mkinitcpio-archiso-plymouth.conf" "${work_dir}/${arch}/airootfs/etc/mkinitcpio-archiso.conf"
    else
        cp "${script_path}/mkinitcpio/mkinitcpio-archiso.conf" "${work_dir}/${arch}/airootfs/etc/mkinitcpio-archiso.conf"
    fi
    gnupg_fd=
    if [[ "${gpg_key}" ]]; then
      gpg --export "${gpg_key}" >"${work_dir}/gpgkey"
      exec 17<>$"{work_dir}/gpgkey"
    fi

    if [[ ! ${kernel} = "core" ]]; then
        ARCHISO_GNUPG_FD=${gpg_key:+17} ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" -r "mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux-${kernel} -g /boot/archiso.img" run
    else
        ARCHISO_GNUPG_FD=${gpg_key:+17} ${mkalteriso} ${mkalteriso_option} -w "${work_dir}/${arch}" -C "${work_dir}/pacman-${arch}.conf" -D "${install_dir}" -r 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' run
    fi

    if [[ "${gpg_key}" ]]; then
      exec 17<&-
    fi
}

# Prepare kernel/initramfs ${install_dir}/boot/
make_boot() {
    mkdir -p "${work_dir}/iso/${install_dir}/boot/${arch}"
    cp "${work_dir}/${arch}/airootfs/boot/archiso.img" "${work_dir}/iso/${install_dir}/boot/${arch}/archiso.img"

    if [[ ! "${kernel}" = "core" ]]; then
        cp "${work_dir}/${arch}/airootfs/boot/vmlinuz-linux-${kernel}" "${work_dir}/iso/${install_dir}/boot/${arch}/vmlinuz-linux-${kernel}"
    else
        cp "${work_dir}/${arch}/airootfs/boot/vmlinuz-linux" "${work_dir}/iso/${install_dir}/boot/${arch}/vmlinuz"
    fi
}

# Add other aditional/extra files to ${install_dir}/boot/
make_boot_extra() {
    # In AlterLinux, memtest has been removed.
    # cp "${work_dir}/${arch}/airootfs/boot/memtest86+/memtest.bin" "${work_dir}/iso/${install_dir}/boot/memtest"
    # cp "${work_dir}/${arch}/airootfs/usr/share/licenses/common/GPL2/license.txt" "${work_dir}/iso/${install_dir}/boot/memtest.COPYING"
    cp "${work_dir}/${arch}/airootfs/boot/intel-ucode.img" "${work_dir}/iso/${install_dir}/boot/intel_ucode.img"
    cp "${work_dir}/${arch}/airootfs/usr/share/licenses/intel-ucode/LICENSE" "${work_dir}/iso/${install_dir}/boot/intel_ucode.LICENSE"
    cp "${work_dir}/${arch}/airootfs/boot/amd-ucode.img" "${work_dir}/iso/${install_dir}/boot/amd_ucode.img"
    cp "${work_dir}/${arch}/airootfs/usr/share/licenses/amd-ucode/LICENSE" "${work_dir}/iso/${install_dir}/boot/amd_ucode.LICENSE"
}

# Prepare /${install_dir}/boot/syslinux
make_syslinux() {
    if [[ ! ${kernel} = "core" ]]; then
        _uname_r="$(file -b ${work_dir}/${arch}/airootfs/boot/vmlinuz-linux-${kernel} | awk 'f{print;f=0} /version/{f=1}' RS=' ')"
    else
        _uname_r="$(file -b ${work_dir}/${arch}/airootfs/boot/vmlinuz-linux | awk 'f{print;f=0} /version/{f=1}' RS=' ')"
    fi
    mkdir -p "${work_dir}/iso/${install_dir}/boot/syslinux"

    for _cfg in ${script_path}/syslinux/${arch}/*.cfg; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
             s|%OS_NAME%|${os_name}|g;
             s|%INSTALL_DIR%|${install_dir}|g" "${_cfg}" > "${work_dir}/iso/${install_dir}/boot/syslinux/${_cfg##*/}"
    done

    if [[ ${boot_splash} = true ]]; then
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
             s|%OS_NAME%|${os_name}|g;
             s|%INSTALL_DIR%|${install_dir}|g" \
             "${script_path}/syslinux/${arch}/pxe-plymouth/archiso_pxe-${kernel}.cfg" > "${work_dir}/iso/${install_dir}/boot/syslinux/archiso_pxe.cfg"

        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
             s|%OS_NAME%|${os_name}|g;
             s|%INSTALL_DIR%|${install_dir}|g" \
             "${script_path}/syslinux/${arch}/sys-plymouth/archiso_sys-${kernel}.cfg" > "${work_dir}/iso/${install_dir}/boot/syslinux/archiso_sys.cfg"
    else
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
             s|%OS_NAME%|${os_name}|g;
             s|%INSTALL_DIR%|${install_dir}|g" \
             "${script_path}/syslinux/${arch}/pxe/archiso_pxe-${kernel}.cfg" > "${work_dir}/iso/${install_dir}/boot/syslinux/archiso_pxe.cfg"

        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
             s|%OS_NAME%|${os_name}|g;
             s|%INSTALL_DIR%|${install_dir}|g" \
             "${script_path}/syslinux/${arch}/sys/archiso_sys-${kernel}.cfg" > "${work_dir}/iso/${install_dir}/boot/syslinux/archiso_sys.cfg"
    fi

    if [[ -f "${script_path}/channels/${channel_name}/splash.png" ]]; then
        cp "${script_path}/channels/${channel_name}/splash.png" "${work_dir}/iso/${install_dir}/boot/syslinux"
    else
        cp "${script_path}/syslinux/${arch}/splash.png" "${work_dir}/iso/${install_dir}/boot/syslinux"
    fi
    cp "${work_dir}"/${arch}/airootfs/usr/lib/syslinux/bios/*.c32 "${work_dir}/iso/${install_dir}/boot/syslinux"
    cp "${work_dir}/${arch}/airootfs/usr/lib/syslinux/bios/lpxelinux.0" "${work_dir}/iso/${install_dir}/boot/syslinux"
    cp "${work_dir}/${arch}/airootfs/usr/lib/syslinux/bios/memdisk" "${work_dir}/iso/${install_dir}/boot/syslinux"
    mkdir -p "${work_dir}/iso/${install_dir}/boot/syslinux/hdt"
    gzip -c -9 "${work_dir}/${arch}/airootfs/usr/share/hwdata/pci.ids" > "${work_dir}/iso/${install_dir}/boot/syslinux/hdt/pciids.gz"
    gzip -c -9 "${work_dir}/${arch}/airootfs/usr/lib/modules/${_uname_r}/modules.alias" > "${work_dir}/iso/${install_dir}/boot/syslinux/hdt/modalias.gz"
}

# Prepare /isolinux
make_isolinux() {
    mkdir -p "${work_dir}/iso/isolinux"

    sed "s|%INSTALL_DIR%|${install_dir}|g" \
        "${script_path}/system/isolinux.cfg" > "${work_dir}/iso/isolinux/isolinux.cfg"
    cp "${work_dir}/${arch}/airootfs/usr/lib/syslinux/bios/isolinux.bin" "${work_dir}/iso/isolinux/"
    cp "${work_dir}/${arch}/airootfs/usr/lib/syslinux/bios/isohdpfx.bin" "${work_dir}/iso/isolinux/"
    cp "${work_dir}/${arch}/airootfs/usr/lib/syslinux/bios/ldlinux.c32" "${work_dir}/iso/isolinux/"
}

# Prepare /EFI
make_efi() {
    mkdir -p "${work_dir}/iso/EFI/boot"
    cp "${work_dir}/${arch}/airootfs/usr/share/efitools/efi/HashTool.efi" "${work_dir}/iso/EFI/boot/"
    if [[ "${arch}" = "x86_64" ]]; then
        cp "${work_dir}/${arch}/airootfs/usr/share/efitools/efi/PreLoader.efi" "${work_dir}/iso/EFI/boot/bootx64.efi"
        cp "${work_dir}/${arch}/airootfs/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "${work_dir}/iso/EFI/boot/loader.efi"
    fi

    mkdir -p "${work_dir}/iso/loader/entries"
    cp "${script_path}/efiboot/loader/loader.conf" "${work_dir}/iso/loader/"
    cp "${script_path}/efiboot/loader/entries/uefi-shell-v2-x86_64.conf" "${work_dir}/iso/loader/entries/"
    cp "${script_path}/efiboot/loader/entries/uefi-shell-v1-x86_64.conf" "${work_dir}/iso/loader/entries/"

    sed "s|%ARCHISO_LABEL%|${iso_label}|g;
         s|%OS_NAME%|${os_name}|g;
         s|%INSTALL_DIR%|${install_dir}|g" \
        "${script_path}/efiboot/loader/entries/usb/archiso-x86_64-usb-${kernel}.conf" > "${work_dir}/iso/loader/entries/archiso-x86_64.conf"

    # EFI Shell 2.0 for UEFI 2.3+
    curl -o "${work_dir}/iso/EFI/shellx64_v2.efi" "https://raw.githubusercontent.com/tianocore/edk2/UDK2018/ShellBinPkg/UefiShell/X64/Shell.efi"
    # EFI Shell 1.0 for non UEFI 2.3+
    curl -o "${work_dir}/iso/EFI/shellx64_v1.efi" "https://raw.githubusercontent.com/tianocore/edk2/UDK2018/EdkShellBinPkg/FullShell/X64/Shell_Full.efi"
}

# Prepare efiboot.img::/EFI for "El Torito" EFI boot mode
make_efiboot() {
    mkdir -p "${work_dir}/iso/EFI/archiso"
    truncate -s 64M "${work_dir}/iso/EFI/archiso/efiboot.img"
    mkfs.fat -n ARCHISO_EFI "${work_dir}/iso/EFI/archiso/efiboot.img"

    mkdir -p "${work_dir}/efiboot"
    mount "${work_dir}/iso/EFI/archiso/efiboot.img" "${work_dir}/efiboot"

    mkdir -p "${work_dir}/efiboot/EFI/archiso"

    if [[ ! ${kernel} = "core" ]]; then
        cp "${work_dir}/iso/${install_dir}/boot/${arch}/vmlinuz-linux-${kernel}" "${work_dir}/efiboot/EFI/archiso/vmlinuz-linux-${kernel}.efi"
    else
        cp "${work_dir}/iso/${install_dir}/boot/${arch}/vmlinuz" "${work_dir}/efiboot/EFI/archiso/vmlinuz.efi"
    fi

    cp "${work_dir}/iso/${install_dir}/boot/${arch}/archiso.img" "${work_dir}/efiboot/EFI/archiso/archiso.img"

    cp "${work_dir}/iso/${install_dir}/boot/intel_ucode.img" "${work_dir}/efiboot/EFI/archiso/intel_ucode.img"
    cp "${work_dir}/iso/${install_dir}/boot/amd_ucode.img" "${work_dir}/efiboot/EFI/archiso/amd_ucode.img"

    mkdir -p "${work_dir}/efiboot/EFI/boot"
    cp "${work_dir}/${arch}/airootfs/usr/share/efitools/efi/HashTool.efi" "${work_dir}/efiboot/EFI/boot/"

    if [[ "${arch}" = "x86_64" ]]; then
        cp "${work_dir}/${arch}/airootfs/usr/share/efitools/efi/PreLoader.efi" "${work_dir}/efiboot/EFI/boot/bootx64.efi"
        cp "${work_dir}/${arch}/airootfs/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "${work_dir}/efiboot/EFI/boot/loader.efi"
    fi

    mkdir -p "${work_dir}/efiboot/loader/entries"
    cp "${script_path}/efiboot/loader/loader.conf" "${work_dir}/efiboot/loader/"
    cp "${script_path}/efiboot/loader/entries/uefi-shell-v2-x86_64.conf" "${work_dir}/efiboot/loader/entries/"
    cp "${script_path}/efiboot/loader/entries/uefi-shell-v1-x86_64.conf" "${work_dir}/efiboot/loader/entries/"

    #${script_path}/efiboot/loader/entries/archiso-x86_64-cd.conf

    sed "s|%ARCHISO_LABEL%|${iso_label}|g;
         s|%OS_NAME%|${os_name}|g;
         s|%INSTALL_DIR%|${install_dir}|g" \
        "${script_path}/efiboot/loader/entries/cd/archiso-x86_64-cd-${kernel}.conf" > "${work_dir}/efiboot/loader/entries/archiso-x86_64.conf"

    cp "${work_dir}/iso/EFI/shellx64_v2.efi" "${work_dir}/efiboot/EFI/"
    cp "${work_dir}/iso/EFI/shellx64_v1.efi" "${work_dir}/efiboot/EFI/"

    umount -d "${work_dir}/efiboot"
}

# Build airootfs filesystem image
make_prepare() {
    cp -a -l -f "${work_dir}/${arch}/airootfs" "${work_dir}"
    ${mkalteriso} ${mkalteriso_option} -w "${work_dir}" -D "${install_dir}" pkglist
    pacman -Q --sysroot "${work_dir}/airootfs" > "${work_dir}/packages-full.list"
    ${mkalteriso} ${mkalteriso_option} -w "${work_dir}" -D "${install_dir}" ${gpg_key:+-g ${gpg_key}} -c "${sfs_comp}" -t "${sfs_comp_opt}" prepare
    remove "${work_dir}/airootfs"

    if [[ "${cleaning}" = true ]]; then
        remove "${work_dir}/${arch}/airootfs"
    fi
}

# Build ISO
make_iso() {
    ${mkalteriso} ${mkalteriso_option} -w "${work_dir}" -D "${install_dir}" -L "${iso_label}" -P "${iso_publisher}" -A "${iso_application}" -o "${out_dir}" iso "${iso_filename}"

    if [[ ${cleaning} = true ]]; then
        remove "$(ls ${work_dir}/* | grep "build.make")"
        remove "${work_dir}"/pacman-*.conf
        remove "${work_dir}/efiboot"
        remove "${work_dir}/iso"
        remove "${work_dir}/${arch}"
        remove "${work_dir}/packages.list"
        remove "${work_dir}/packages-full.list"
        remove "${rebuildfile}"
        if [[ -z $(ls $(realpath "${work_dir}")/* 2>/dev/null) ]]; then
            remove ${work_dir}
        fi
    fi
    _msg_info "The password for the live user and root is ${password}."
}


# Parse options
while getopts 'a:w:o:g:p:c:t:hbk:xs:jlu:d-:' arg; do
    case "${arg}" in
        p) password="${OPTARG}" ;;
        w) work_dir="${OPTARG}" ;;
        o) out_dir="${OPTARG}" ;;
        g) gpg_key="${OPTARG}" ;;
        c)
            # compression format check.
            if [[ ${OPTARG} = "gzip" ||  ${OPTARG} = "lzma" ||  ${OPTARG} = "lzo" ||  ${OPTARG} = "lz4" ||  ${OPTARG} = "xz" ||  ${OPTARG} = "zstd" ]]; then
                sfs_comp="${OPTARG}"
            else
                _msg_error "Invalid compressors ${arg}" "1"
            fi
            ;;
        t) sfs_comp_opt=${OPTARG} ;;
        b) boot_splash=true ;;
        k)
            if [[ -n $(cat ${script_path}/system/kernel_list-${arch} | grep -h -v ^'#' | grep -x "${OPTARG}") ]]; then
                kernel="${OPTARG}"
            else
                _msg_error "Invalid kernel ${OPTARG}" "1"
            fi
            ;;
        x) 
            debug=true
            bash_debug=true
            ;;
        d) debug=true;;
        j) japanese=true ;;
        l) cleaning=true ;;
        u) username="${OPTARG}" ;;
        h) _usage 0 ;;
        a) 
            case "${OPTARG}" in
                "i686" | "x86_64" ) arch="${OPTARG}" ;;
                +) _msg_error "Invaild architecture '${OPTARG}'" '1' ;;
            esac
            ;;
        -)
            case "${OPTARG}" in
                help)_usage 0 ;;
                noconfirm) noconfirm=true ;;
                nodepend) nodepend=true ;;
                *)
                    _msg_error "Invalid argument '${OPTARG}'"
                    _usage 1
                    ;;
            esac
            ;;
        *)
           _msg_error "Invalid argument '${arg}'"
           _usage 1
           ;;
    esac
done


# Check root.
if [[ ${EUID} -ne 0 ]]; then
    _msg_warn "This script must be run as root." >&2
    # echo "Use -h to display script details." >&2
    # _usage 1
    _msg_warn "Re-run 'sudo ${0} ${@}'"
    sudo ${0} ${@}
    exit 1
fi


# Show config message
[[ -f "${script_path}"/config ]] && _msg_debug "The settings have been overwritten by the "${script_path}"/config."


# Debug mode
mkalteriso_option="-a ${arch} -v"
if [[ "${bash_debug}" = true ]]; then
    set -x
    set -v
    mkalteriso_option="${mkalteriso_option} -x"
fi


# Pacman configuration file used only when building
build_pacman_conf=${script_path}/system/pacman-${arch}.conf


# Parse options
set +e

shift $((OPTIND - 1))

if [[ -n "${1}" ]]; then
    channel_name="${1}"

    # Channel list
    # check_channel <channel name>
    check_channel() {
        local channel_list
        local i
        channel_list=()
        for i in $(ls -l "${script_path}"/channels/ | awk '$1 ~ /d/ {print $9 }'); do
            if [[ -n $(ls "${script_path}"/channels/${i}) ]]; then
                if [[ ! ${i} = "share" ]]; then
                    if [[ ! $(echo "${i}" | sed 's/^.*\.\([^\.]*\)$/\1/') = "add" ]]; then
                        if [[ ! -d "${script_path}/channels/${i}.add" ]]; then
                            channel_list="${channel_list[@]} ${i}"
                        fi
                    else
                        channel_list="${channel_list[@]} ${i}"
                    fi
                fi
            fi
        done
        for i in ${channel_list[@]}; do
            if [[ $(echo "${i}" | sed 's/^.*\.\([^\.]*\)$/\1/') = "add" ]]; then
                if [[ $(echo ${i} | sed 's/\.[^\.]*$//') = ${1} ]]; then
                    echo -n "true"
                    return 0
                fi
            else
                if [[ ${i} = ${1} ]]; then
                    echo -n "true"
                    return 0
                fi
            fi
        done
        if [[ "${channel_name}" = "rebuild" ]] || [[ "${channel_name}" = "clean" ]]; then
            echo -n "true"
            return 0
        else
            echo -n "false"
            return 1
        fi
    }

    if [[ $(check_channel "${channel_name}") = false ]]; then
        _msg_error "Invalid channel ${channel_name}" "1"
    fi

    if [[ -d "${script_path}"/channels/${channel_name}.add ]]; then
        channel_name="${channel_name}.add"
    elif [[ "${channel_name}" = "rebuild" ]]; then
        if [[ -f "${rebuildfile}" ]]; then
                rebuild=true
        else
            _msg_error "The previous build information is not in the working directory." "1"
        fi
    elif [[ "${channel_name}" = "clean" ]]; then
            umount_chroot
            rm -rf "${work_dir}"
            exit 
    fi

    _msg_debug "channel path is ${script_path}/channels/${channel_name}"
fi

set -e


prepare_build
show_settings
run_once make_pacman_conf
run_once make_basefs
run_once make_packages
run_once make_customize_airootfs
run_once make_setup_mkinitcpio
run_once make_boot
run_once make_boot_extra
run_once make_syslinux
run_once make_isolinux
run_once make_efi
run_once make_efiboot
run_once make_prepare
run_once make_iso
