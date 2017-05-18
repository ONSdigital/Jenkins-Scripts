#
#
# $Header$
#

if [ -z "$SCRIPTS_DIR" ]; then
	echo '$SCRIPTS_DIR MUST be set'

	exit 1
fi

for i in vars.sh functions.sh; do
	. "$SCRIPTS_DIR/common/$i"
done
