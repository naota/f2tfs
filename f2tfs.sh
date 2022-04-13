#!/bin/bash

BOOZE_DIR=../booze
pushd ${BOOZE_DIR} >/dev/null
. ./booze.sh
popd >/dev/null

LOG_FILE=/tmp/log
rm -f ${LOG_FILE}
log() {
	echo $* >> ${LOG_FILE}
}

f2t_getattr() {
	local now=`date +%s`
	local times="$now $now $now"
	local ids="`id -u` `id -g`"
	if [ "$1" == "/" ]; then
		booze_out="0 $(printf '%o' $((S_IFDIR | 0755))) 2 $ids 0 0 0 $times"
		return 0
	else
		booze_err=-$ENOENT
		return 1
	fi
}

f2t_readdir() {
	booze_out="./.."
	return 0
}

f2t_open() {
	if [ "$1" == "/" ]; then
		return 0
	else
		booze_err=-$ENOENT
		return 1
	fi
}

declare -A f2t_ops
for name in ${BOOZE_CALL_NAMES[@]}; do
	if [ "`type -t f2t_$name`" == "function" ]; then
		f2t_ops[$name]=f2t_$name
	fi
done

booze f2t_ops "$1"
