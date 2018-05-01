#!/bin/sh
#
# script to set Atari program args after TOS starts it.
#
# this is achieved by chaining breakpoints from Hatari startup
# to program startup, and finally writing the arguments to
# the program basepage.

set -e

# name or path to hatari Mercurial version
hatari=hatari

usage ()
{
	name=${0##*/}
	echo "usage: $name [Hatari args] -- <Atari program> <program args>"
	echo
	echo "Script for running Hatari so that it autostarts given Atari program"
	echo "and inserts given arguments to program (to its basepage, with builtin"
	echo "Hatari debugger facilities)."
	echo
	echo "If arguments have same (host) path prefix as given Atari program,"
	echo "those prefixes are replaced with 'C:\', Unix path separators ('/')"
	echo "are replaced with Atari ones ('\\') and whole filename upper-cased."
	echo
	echo "Other arguments are passed unmodified."
	echo
	echo "Example:"
	echo "	$name -m -- atari/sidplay.ttp atari/sids/test.sid"
	echo
	echo "ERROR: $1!"
	exit 1
}

# --------- argument parsing --------

# generic argument checking
if [ $# -lt 3 ]; then
	usage "not enough arguments"
fi
echo " $* " | grep -q ' -- '
if [ $? -ne 0 ]; then
	usage "Separator missing for Hatari -- Atari options"
fi

# collect/remove hatari arguments
for arg in $*; do
	shift
	if [ $arg = '--' ]; then
		break
	fi
	hatari="$hatari $arg"
done

# check atari program
prg=$1
shift
if [ \! -f $prg ]; then
	usage "given Atari program doesn't exist"
fi

# builtin shell echo can be broken, so that it interprets backlashes by default,
# i.e. concatenating '\' path separator with dirname 't', produces TAB, not '\t'...
# -> use separate echo binary
echo=$(which echo)

# temporary dir for debugger scripts
dir=$(mktemp -d)

# collect/convert atari program arguments
args=$dir/args
rm -f $args
touch $args
prefix=""
drive="C:\\"
path="${prg%/*}/"
for arg in $*; do
	if [ "${arg#$path}" != "$arg" ]; then
		# file path needing conversion
		if [ \! -f $arg ]; then
			usage "given file name '$arg' doesn't exits"
		fi
		# prefix with separator & drive letter & remove host path,
		# upper-case, convert path separators
		$echo -n "${prefix}${drive}${arg#$path}" | tr a-z A-Z | tr '/' '\\' >> $args
	else
		$echo -n "${prefix}$arg" >> $args
	fi
	prefix=" "
	shift
done

# calculate command line length and append zero just in case
cmdlen=$(wc -c $args | awk '{print $1}')
printf "\0" >> $args
if [ $cmdlen -gt 126 ]; then
	usage "command line is too long, $cmdlen chars (basepage limit is 126)"
fi

# --------- debugger scripts --------

# until TOS has started, it's not possible to set breakpoint
# to program startup, there's no valid basepage and therefore
# no valid TEXT variable.  So set breakpoint on Pexec(0,...)
cat > $dir/pexec.ini << EOF
b GemdosOpcode = 0x4B && GemdosParam = 0x0 :once :quiet :trace :file $dir/start.ini
EOF

# real work can be done when program starts,
# i.e. PC is at TEXT section beginning
cat > $dir/start.ini << EOF
b pc = text :once :trace :quiet :file $dir/basepage.ini
EOF

# add command line args args to program basepage 
cat > $dir/basepage.ini << EOF
setopt dec
w "basepage+0x80" $cmdlen
l $args "basepage+0x81"
info basepage
EOF

# --------- ready, run ----------

# show args & debugger scripts
head $dir/*

# run Hatari
echo $hatari --parse $dir/pexec.ini $prg
$hatari --parse $dir/pexec.ini $prg

# cleanup
rm -r $dir
