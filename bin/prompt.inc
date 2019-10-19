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
 	       if [ "x$CH" = "xA" ]; then
 	               SKIP_PROMPT=y
 	               return
 	       fi
 	       [ "x$CH" = "xn" ] && abort "cancelled by user"
 	       [ "x$CH" = "xy" ] && return
	done
}

