#!/bin/bash

############################################################################################################
#                                                                                                          #
#      This script is Free Software, it's licensed under the GPLv2 and has ABSOLUTELY NO WARRANTY          #
#                                                                                                          #
############################################################################################################
#                                                                                                          #
#      Please see the LICENSE; and the README file for information, Version History and TODO               #
#                                                                                                          #
############################################################################################################
#                                                                                                          #
#      Name:              lede-userpkgs.sh                                                                 #
#      Version:           0.2.1                                                                            #
#      Date:              Fri, Jun 30 2017                                                                 #
#      Author:            Callea Gaetano Andrea (aka cga)                                                  #
#      Contributors:                                                                                       #
#      Language:          BASH                                                                             #
#      Location:          https://github.com/aasgit/lede-userpkgs                                          #
#                                                                                                          #
############################################################################################################

############################

## the script has to be run as root (or with sudo), let's make sure of that:
if [ $EUID != 0 ]; then
    echo
    echo "You must run this script with root powers (sudo is fine too)."
    echo
    exit 1
fi

############################

## GLOBAL VARIABLES

SCRIPTN="${0##*/}"                                          # name of this script
SCRPATH="/tmp"                                              # the path where to save the lists
PKGLIST="$SCRPATH/opkg.pkgs.list"                           # default package list
BCKLIST="$SCRPATH/opkg.pkgs.$(date +%F-%H%M%S).list"        # the backup list copy with date and time
INSTLST="$PKGLIST"                                          # the list to install packages from
TEMPLST="$SCRPATH/opkg.temp.list"                           # dependencies list for --install
DEPSLST="$SCRPATH/opkg.deps.list"                           # dependencies list for --install
NOLIST=false                                                # if true: print to screen instead of file
DRYRUN=false                                                # options for dry run. not there yet

############################

## FUNCTINOS

## usage commands
usage() {
cat <<USAGE

Usage: $SCRIPTN [options...] command

Available commands:
    -h   --help                    print this help
    -r   --readme                  print a verbose version of this help
    -u   --update                  update the opkg package database (do this at least once. see '--readme')
    -g   --gen-list                create a list of currently manually installed packages to file
    -p   --print-list              print a list to screen instead of writing to file
    -b   --backup-list             backup a copy of the list of packages
    -c   --backup-config           backup configuration files with 'sysupgrade'
    -e   --erase                   interactively remove backup and list files created by the script
    -i   --install                 read the package list from file and install them
    -x   --restore-config          restore configuration files from an archive

Options (see 'readme' command):
    -l   --list                    to use with 'install': manually specifiy a list file
    -d   --dry-run                 to use with 'install': perform a dry run of install

USAGE
}

readme() {
cat <<README
'$SCRIPTN' can be used:

    -- before sysupgrade: to create a list of currently user manually installed packages.
    -- before sysupgrade: to create a backup of configuration files.
    -- after  sysupgrade: to reinstall those packages that are not part of the new firmware image.
    -- after  sysupgrade: to restore previously created configuration files backup.

IMPORTANT: in both cases, run an update at least once (before and after sysupgrade!!!)

To reinstall all packages that were not part of the firmware image, after the firmware upgrade, use the -i or --install command.

To manually specify a [saved] list of pacakges, including path, without this option defaults to '$INSTLST':

    $SCRIPTN --list listfile --install

To perform a dry-run of install, it will print on screen instead of executing:

    $SCRIPTN --dry-run --install

To restore previously created configuration files backup from an archive, user -x or --restore-config command.

    $SCRIPTN --restore-config backupfile.tar.gz

IMPORTANT: run an update at least once (before and after sysupgrade!!!)

README
}

############################

## update list of available packages
update() {
    echo
    echo "Updating the package list...."
    opkg update >/dev/null 2>&1
    echo
    echo "Done!"
}

############################

## setlist
listset() {
    ## first: let's get the epoc time of busybox as a date reference
    FLASHTM=$(opkg status busybox | awk '/Installed-Time/ {print $2}')
    ## second: let's get the list of all currently installed packages
    LSTINST=$(opkg list-installed | awk '{print $1}')
    ## now let's use those to determine the user installed packages list
    for PACKAGE in $LSTINST; do
        if [ "$(opkg status $PACKAGE | awk '/Installed-Time:/ {print $2}')" != "$FLASHTM" ]; then
            echo $PACKAGE
        fi
    done
}

setlist() {
if [ $NOLIST == true ]; then
        echo
        echo "Here's a list of the packages that were installed manually. This doesn't write to $PKGLIST:"
        sleep 3
        echo
        listset
        echo
        echo "NOTE: NO list was actually saved or created. Make sure to run: $SCRIPTN --gen-list"
        echo
    else
        echo
        echo "Saving the package list of the current manually installed packages to $PKGLIST"
        echo
        listset >> "$PKGLIST"
        echo "Done"
        echo
fi
}

############################

## backup configuration files, same as:
# - https://lede-project.org/docs/howto/backingup
# - https://wiki.openwrt.org/doc/howto/generic.backup#backup_openwrt_configuration
bckcfg() {
    sysupgrade --create-backup "$SCRPATH/backup-$(cat /proc/sys/kernel/hostname)-$(date +%F-%H%M%S).tar.gz"
}

## backup an existing packages list previously created
bcklist() {
    if [ -f $PKGLIST ]; then
        if [ -s $PKGLIST ]; then
            echo
            cp $PKGLIST $BCKLIST
            echo "Copied the existing '$PKGLIST' to '$BCKLIST'"
            echo
            exit 0
        else
            echo
            echo "The file '$PKGLIST' is empty! Nothing to backup here..."
            echo
            exit 2
        fi
    else
        echo
        echo "The file '$PKGLIST' doesn't exist! Nothing to backup here..."
        echo
        exit 3
    fi
}

############################

erase() {
# let's get rid of the old packages lists (including backups!!!)
    if ls $SCRPATH/opkg.*.list >/dev/null 2>&1 ; then
        local aretherefile=0
    else
        local aretherefile=1
    fi

    if ls $SCRPATH/backup-$(cat /proc/sys/kernel/hostname)-*.tar.gz >/dev/null 2>&1 ; then
        local aretherebcks=0
    else
        local aretherebcks=1
    fi

    if [ "$aretherefile" == 0 ] || [ "$aretherebcks" == 0 ] ; then
        echo
        echo "Do you want to remove these files?"
        echo
        if [ "$aretherefile" == 0 ] ; then
            rm -i $SCRPATH/opkg.*.list
        fi
        if [ "$aretherebcks" == 0 ] ; then
            rm -i $SCRPATH/backup-$(cat /proc/sys/kernel/hostname)-*.tar.gz
        fi
        echo
    else
        echo "No files to delete. Bye..."
        exit 4
    fi
}

############################

### not necessary in this script, but leaving it here for now....
checkdeps() {
# let's check the dependencies of packages in $INSTLST and create a dependencies list too
    echo
    echo "'checkdeps' is not needed. deps as in mforkel script is pointless here."
    echo "we already have an '$INSTLST' that is made of new pacakges only!!!!!!!!"
    echo
    while IFS= read -r PACKAGE; do
        opkg status "$PACKAGE" | awk '/Depends/ {for (i=2;i<=NF;i++) print $i}' | sed 's/,//g' >> "$TEMPLST"
        cat "$TEMPLST" | sort -u >> "$DEPSLST"
        rm -f "$TEMPLST" >/dev/null 2>&1
    done < "$INSTLST"
}

############################

install() {
    if [ $INSTLST ]; then
        if [ -f $INSTLST ]; then
            if [ -s $INSTLST ]; then
                echo
                echo "Installing packages from list '$INSTLST' : this may take a while..."
                echo
                if $DRYRUN; then
                    while IFS= read -r PACKAGE; do
                        echo opkg install "$PACKAGE"
                    done < "$INSTLST"
                    echo
                    echo "THIS WAS A DRY-RUN....."
                else
                    while IFS= read -r PACKAGE; do
                        opkg install "$PACKAGE"
                    done < "$INSTLST"
                    echo
                    echo "Done! You may want to restore configurations now."
                fi
                echo
                exit 0
            else
                echo
                echo "The file '$INSTLST' is empty!!! Can't install from this..."
                echo
                exit 5
            fi
        else
            echo
            echo "The packages list file '$INSTLST' doesn't exist!!! Did you forget to create or save one?"
            echo
            exit 6
        fi
    else
        echo
        echo "You must specify an install list argument to -l --list"
        echo
        exit 99
    fi
}

############################

cfgrestore(){
    echo
    echo "NOT implemented yet!!!"
    echo
    exit 99
}

############################

## MAIN ##

## parse command line options and commands:
while true; do
    case "$1" in
        -h|--help|'') usage; exit 0;;
        -r|--readme) usage; readme; exit 0;;
        -u|--update) opkg update; exit 0;;
        -g|--gen-list) setlist; exit 0;;
        -p|--print-list) NOLIST=true; setlist; exit 0;;
        -b|--backup-list) bcklist; exit 0;;
        -c|--backup-config) bckcfg; exit 0;;
        -e|--erase) erase; exit 0;;
        -x|--restore-config) cfgrestore; exit 0;;
        -i|--install) install; exit 0;;
        -l|--list) shift; INSTLST="$1"; shift;;
        -d|--dry-run) DRYRUN=true; shift;;
        *) echo; echo "$SCRIPTN: unknown command '$1'"; usage; exit 127;;
    esac
done

