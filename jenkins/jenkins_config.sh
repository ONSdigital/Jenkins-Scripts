#!/bin/sh
#
# Create new Jenkins config
#

set -ex

if [ -n "$SCRIPTS_DIR" ]; then
	# SCRIPTS_DIR is already set, so don't do anything
	:
elif [ -f "common/functions.sh" ]; then
	# Jenkins isn't there yet
	export SCRIPTS_DIR="`pwd`"

elif [ -f "scripts/common/functions.sh" ]; then
	# Jenkins isn't there yet
	export SCRIPTS_DIR="`pwd`/scripts"

elif basename $0 | grep -q scripts; then
	export SCRIPTS_DIR="`basename $0`"

else
	echo 'Unable to find functions.sh - are you running this'
	echo 'from the folder that contains functions.sh?'
	exit 1
fi

. $SCRIPTS_DIR/common/common.sh

[ -z "$JENKINS_INSTANCE" ] && FATAL "Not enough parameters set: JENKINS_INSTANCE='$JENKINS_INSTANCE'"

WRAPPER_SCRIPT="jenkins_wrapper-$JENKINS_INSTANCE.sh"
WRAPPER_SCRIPT_NEW="jenkins_wrapper-$JENKINS_INSTANCE.sh-new"
JENKINS_APPNAME="${JENKINS_APPNAME:-jenkins-$JENKINS_INSTANCE}"

configure_git

if [ ! -f "$WRAPPER_SCRIPT" ]; then
	git branch -r | grep -q "origin/$JENKINS_INSTANCE" && FATAL "$JENKINS_INSTANCE already exists - please update existing config, or remove the branch"

	git checkout -b "$JENKINS_INSTANCE"

	# Update .gitignore
	cat >>.gitignore <<EOF
!$WRAPPER_SCRIPT
!id_rsa
EOF
fi

cp jenkins_wrapper-template.sh "$WRAPPER_SCRIPT_NEW"

INFO 'Generating deployment wrapper'
for i in JENKINS_APPNAME \
	JENKINS_RELEASE_TYPE JENKINS_MEMORY JENKINS_DISK \
	DEPLOY_JENKINS_CONFIG_SEED_REPO DEPLOY_JENKINS_SCRIPTS_REPO \
	JENKINS_CONFIG_SEED_REPO JENKINS_SCRIPTS_REPO \
	CF_USERNAME CF_PASSWORD CF_ORG CF_SPACE CF_API_ENDPOINT \
	DISABLE_CSP SSH_KEYSCAN_HOSTS; do
	eval var="\$$i"

	if [ -n "$var" ]; then
		# Enrich wrapper script
		sed -i -re "s|^#export ($i)=.*$|export \1=\"$var\"|g" "$WRAPPER_SCRIPT_NEW"
	fi

	unset var
done

# Hopefully we are being run after the deployment completes
[ -f deployment/id_rsa ] || FATAL 'No SSH key'


if [ ! -f id_rsa ] || ! diff -q deployment/id_rsa id_rsa; then
	SSH_CHANGE=1
	cp deployment/id_rsa .
fi

if [ -f "$WRAPPER_SCRIPT" -a -f "$WRAPPER_SCRIPT_NEW" ] && diff -q "$WRAPPER_SCRIPT_NEW" "$WRAPPER_SCRIPT"; then
	# New wrapper and the old are the same
	rm "$WRAPPER_SCRIPT_NEW"
fi

if [ -f "$WRAPPER_SCRIPT_NEW" ]; then
	[ -f "$WRAPPER_SCRIPT" ] && rm -f "$WRAPPER_SCRIPT"

	SCRIPT_CHANGE=1

	mv "$WRAPPER_SCRIPT_NEW" "$WRAPPER_SCRIPT"
fi

[ -n "$SSH_CHANGE" ] && git add id_rsa
[ -n "$SCRIPT_CHANGE" ] && git add "$WRAPPER_SCRIPT"

git commit -am "Added deployment config for $JENKINS_APPNAME" || WARN 'No changes to commit'

git push --all
