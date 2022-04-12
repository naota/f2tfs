#!/bin/bash

MNT=/mnt/test

set -xe

./f2tfs.sh ${MNT}

ls -lai ${MNT}

umount ${MNT}
