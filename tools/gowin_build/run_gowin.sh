#!/bin/bash
# run_gowin.sh -- run gw_sh headless on Linux with the environment it needs.
#   GOWIN_HOME=/path/to/gowin NAME=... TOP=... SRC=... ./run_gowin.sh build.tcl
# The environment is set ONLY for this process: exporting it in your shell
# breaks openFPGALoader (libbz2 from Gowin's lib dir).
GOWIN_HOME=${GOWIN_HOME:-$HOME/tools/gowin}
export LD_PRELOAD=/lib64/libfreetype.so.6          # the bundled freetype breaks Qt on some distros
export QT_QPA_PLATFORM=minimal                     # no display needed
export QT_PLUGIN_PATH=$GOWIN_HOME/IDE/plugins/qt
export LD_LIBRARY_PATH=$GOWIN_HOME/IDE/lib
exec "$GOWIN_HOME/IDE/bin/gw_sh" "$@"
