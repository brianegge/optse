#!/bin/sh

THIS_DIR=$(dirname $0)
exec ruby --disable-gems $THIS_DIR/download.rb "$@"
