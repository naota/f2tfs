#!/bin/bash

BOOZE_DIR=../booze
pushd ${BOOZE_DIR} >/dev/null
. ./booze.sh
popd >/dev/null

USER_ID="0"

LOG_FILE=/tmp/log
rm -f ${LOG_FILE}
log() {
	echo $* >> ${LOG_FILE}
}

JOURNAL=journal
load_journal() {
	test -e ${JOURNAL} || return 0

	source ${JOURNAL}
	rm -f ${JOURNAL}
}
add_journal() {
	local name="$1"
	value=$(eval "echo \$${name}")
	echo ${name}=${value@Q} >> ${JOURNAL}
}

declare -A TWEET_FILES

mikcall() {
	read -r -d '' rb
	arg="[(\"code\", <\"${rb@E}\">), (\"file\", <\"org.mikutter.eval\">)]"

	log "${arg}"

	sudo -u naota gdbus call -a ${DBUS_SESSION_BUS_ADDRESS} \
		-d org.mikutter.dynamic \
		-o /org/mikutter/MyInstance \
		-m org.mikutter.eval.ruby \
		"${arg}" 2>>${LOG_FILE}
}

mikcall_tweets() {
	mikcall <<EOM
tw = Plugin.collect(:worlds).to_a[1]
result = nil
done = false
task = tw.user_timeline(:user_id => ${USER_ID}).next { |res|
  result = res
  done = true
}
while !done
  sleep 0.1
end
result.map { |msg|
  \\\\"#{msg.id} #{msg.message}\\\\"
}.join(\\\\"<>\\\\")
EOM
}

mikcall_fav() {
	local target="$1"

	mikcall <<EOM
tw = Plugin.collect(:worlds).to_a[1]
result = nil
done = false
target = ${target}
task = tw.user_timeline(:user_id => ${USER_ID}).next { |res|
  result = res
  done = true
}
while !done
  sleep 0.1
end
result.each { |msg|
  if msg.id == target
    msg.favorite
    return 'OK'
  end
}
return 'FAIL'
EOM
}

regular_file_stat() {
	local ino="$1"
	local size="$2"

	local now=`date +%s`
	local times="$now $now $now"
	local ids="`id -u` `id -g`"

	echo "$ino $(printf '%o' $((S_IFREG | 0644))) 1 $ids 0 ${size} 1 $times"
}

f2t_getattr() {
	local path="$1"
	local now=`date +%s`
	local times="$now $now $now"
	local ids="`id -u` `id -g`"

	load_journal

	# booze_out="<ino> <mode> <nlink> <uid> <gid> <rdev> <size>
	# 	     <blocks> <atime> <mtime> <ctime>"
	fname="${path#/}"
	cont=${TWEET_FILES[$fname]}
	if [[ -n "${cont}" ]]; then
		size=$(printf "%s\n" "${cont}" | wc -c)
		booze_out=$(regular_file_stat ${fname} ${size})
		return 0
	fi

	case "$path" in
	"/")
		booze_out="1 $(printf '%o' $((S_IFDIR | 0755))) 2 $ids 0 0 0 $times"
		return 0
		;;
	"/user_id")
		booze_out=$(regular_file_stat 2 $(( ${#USER_ID} + 1 )))
		return 0
		;;
	*)
		booze_err=-$ENOENT
		return 1
		;;
	esac
}

f2t_readdir() {
	booze_out="./../user_id"

	if [[ "${USER_ID}" == 0 ]]; then
		return 0
	fi

	res=$(mikcall_tweets | sed -e "s/^('//; s/',)$//")
	log "${res}"
	text=$(eval echo -e "${res}")
	while : ; do
		item=${text%%<>*}
		text=${text#*<>}
		log "${item}"

		fname="${item%% *}"
		content="${item#* }"
		TWEET_FILES[${fname}]="${content}"

		[[ "${text}" == "${item}" ]] && break
	done

	for fname in "${!TWEET_FILES[@]}"; do
		booze_out+="/${fname}"
	done
	
	return 0
}

check_file_path() {
	local $path="$1"

	fname="${path#/}"
	cont=${TWEET_FILES[$fname]}
	if [[ -n "${cont}" ]]; then
		return 0
	fi

	case $path in
	"/" | "/user_id")
		return 0
		;;
	*)
		booze_err=-$ENOENT
		return 1
		;;
	esac
}

f2t_open() {
	local path="$1"

	check_file_path "$path" || return 1
	return 0
}

f2t_read() {
	local path="$1"
	local readlen="$2"
	local offset="$3"

	check_file_path "$path" || return 1
	load_journal

	fname="${path#/}"
	cont=${TWEET_FILES[$fname]}
	if [[ -n "${cont}" ]]; then
		printf "%s\n" "${cont}"
		return 0
	fi

	case $path in
	"/user_id")
		if [[ ${offset} != 0 ]]; then
			return 0
		fi

		log "read USER_ID=${USER_ID}"
		echo ${USER_ID}
		;;
	esac

	return 0
}

f2t_truncate() {
	local path="$1"
	local len="$2"

	check_file_path "$path" || return 1

	case $path in
	"/user_id")
		if [[ ${len} != 0 ]]; then
			booze_err=-$EINVAL
			return 1
		fi

		USER_ID=""
		log "truncate USER_ID=${USER_ID}"
		;;
	esac

	return 0
}

f2t_write() {
	local path="$1"
	local writelen="$2"
	local offset="$3"

	check_file_path "$path" || return 0

	fname="${path#/}"
	cont=${TWEET_FILES[$fname]}
	if [[ -n "${cont}" ]]; then
		if [[ ${offset} != 0 || ${writelen} != 2 ]]; then
			booze_err=-$EIO
			booze_out=-$EIO
			return 1
		fi

		written="$(</dev/stdin)"
		log "written=${written}"
		if [[ "${written}" == "1" ]]; then
			mikcall_fav ${fname}
			booze_out=${writelen}
			return 0
		else
			booze_err=-$EIO
			booze_out=-$EIO
			return 1
		fi
	fi

	case $path in
	"/user_id")
		if [[ ${offset} != 0 ]]; then
			booze_err=-$EIO
			booze_out=-$EIO
			return 1
		fi

		USER_ID="$(</dev/stdin)"
		add_journal USER_ID
		log "write USER_ID=${USER_ID}"
		booze_out=$(( ${#USER_ID} + 1 ))
		;;
	esac

	return 0
}

declare -A f2t_ops
for name in ${BOOZE_CALL_NAMES[@]}; do
	if [ "`type -t f2t_$name`" == "function" ]; then
		f2t_ops[$name]=f2t_$name
	fi
done

rm ${JOURNAL}
booze -o use_ino f2t_ops "$1"
