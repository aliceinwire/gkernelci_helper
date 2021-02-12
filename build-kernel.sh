#!/bin/sh

set -e

MAKEOPTS="-j$(( $(getconf _NPROCESSORS_ONLN) + 1 ))"

if [ $# -lt 1 ]; then
	echo "Usage: $(basename $0) arch BUILDER_NAME BUILD_NUMBER SOURCEDIR [build|modules]"
	exit 1
fi

ARCH=$1
# make cannot handle ":" in a path, so we need to replace it
BUILDER_NAME=$(echo $2 | sed 's,:,_,g')
BUILD_NUMBER=$3
SOURCEDIR=$4
ACTION=$5

# hacks before Gbuildbot has all args
if [ "$2" = 'modules' ];then
	ACTION='modules'
fi
if [ -z "$ACTION" ];then
	ACTION=build
fi

build() {
	local defconfig="$1"
	local toolchain="$2"

	FDIR="$(dirname $(realpath $0))/linux-$ARCH-build/$BUILDER_NAME/$BUILD_NUMBER/$defconfig/$toolchain"

	echo "DEBUG: $ACTION for $ARCH/$defconfig to $FDIR"
	MAKEOPTS="$MAKEOPTS O=$FDIR"

	case $ACTION in
	build)
		echo "DO: mrproper"
		make $MAKEOPTS mrproper

		echo "DO: generate config from defconfig"
		make $MAKEOPTS $defconfig

		echo "DO: build"
		make $MAKEOPTS
	;;
	modules)
		rm -f $FDIR/nomodule
		grep -q 'CONFIG_MODULES=y' $FDIR/.config || touch $FDIR/nomodule
		if [ -e $FDIR/nomodule ];then
			echo "INFO: modules are disabled, skipping"
			return 0
		fi
		echo "DO: build modules"
		make $MAKEOPTS modules
		echo "DO: install modules"
		mkdir $FDIR/modules
		make $MAKEOPTS modules_install INSTALL_MOD_PATH="$FDIR/modules/"
		CPWD=($pwd)
		cd $FDIR/modules
		echo "DO: targz modules"
		tar czf ../modules.tar.gz lib
		cd $CPWD
		rm -r "$FDIR/modules/"

	;;
	*)
		echo "ERROR: unknow action: $ACTION"
		exit 1
	;;
	esac
}

BCONFIG="$(dirname $(realpath $0))/build-config/"
if [ ! -e "$BCONFIG/$ARCH" ];then
	echo "ERROR: $ARCH is unsupported"
	exit 1
fi

for defconfigdir in $(ls $BCONFIG/$ARCH)
do
	echo "INFO: $ARCH $defconfigdir"
	BCDIR=$BCONFIG/$ARCH/$defconfigdir
	if [ -e $BCDIR/defconfig ];then
		defconfig="$(cat $BCDIR/defconfig)"
	else
		echo "ERROR: no defconfig in $BCDIR, defaulting to defconfig"
		defconfig="defconfig"
	fi
	build $defconfig gcc
done
