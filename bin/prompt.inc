abort()
{
        echo "$0 Abort: $*"
        exit 1
}
prompt()
{
        echo "-------------------------"
        [ -z "$*" ] || echo "$*"
        [ -z "$*" ] || echo "-------------------------"
	
        [ -z "$SKIP_PROMPT" ] || return

    while [ 1 ]; do
	echo -n "Confirm(y/n/A) ?"
	read CH
	[ -z "$CH" ] && sleep 1
	[ -z "$CH" ] && continue
	[ "$CH" = "y" ] && return
	[ "$CH" = "n" ] && abort "cancelled by user"
	[ "$CH" = "A" ] && break  
    done
	export SKIP_PROMPT=y
}

print()
{
	echo "`date +%H:%M:%S-%d.%m.%y`:[$0]: $*"
}

wait()
{
	[ -z "$1" ] && return
	let DELAY=$1 || return
	echo -n "waiting [$DELAY]: ("
	for I in `seq $DELAY -1 1`; do echo -n "$I "; sleep 1; done
	echo "): Ok"
}
