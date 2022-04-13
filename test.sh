#!/bin/bash

MNT=/mnt/test

set -xe

./f2tfs.sh ${MNT}

trap "cd /; umount ${MNT}" 0 1 2 3 15

findmnt ${MNT}

pushd ${MNT}

ls -lai

cat user_id
USER_ID=15926668 
echo ${USER_ID} > user_id
test "$(cat user_id)" == ${USER_ID}

ls -lai
grep . *

TARGET=1511337915154333700
echo 1 > ${TARGET}

popd
