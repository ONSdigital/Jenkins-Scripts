#!/bin/sh
#

set -e

################
# Functions
git_add(){
	git_add_rm add "$@"
}

git_rm(){
	git_add_rm rm "$@"
}


git_add_rm(){
	local action="$1"
	shift
	local files="$@"

	[ x"$action" = x"rm" ] && action="rm -r"

	echo "$files" | awk -v commit_msg="$GIT_COMMIT_MESSAGE" -v action="$action" '{
		split($0,files,/ ?, ?/)
		for(file in files){
			system("git " action " \"" files[file] "\"")
			system("git commit -m \"" commit_msg "\"")
		}
	}'
}

git_changes(){
	git status --porcelain | awk '!/^A /{
		print $0
		gsub(/^..? /,"")
		files[$0]++

		}END{
			for(file in files){
				printf("New/modified/deleted file/directory: %s\n",file)

				i++
			}

			exit i ? 1 : 0
		}' || return 1
}
################


################
# Vars
if [ -z "$SCRIPTS_DIR" ]; then
	echo FATAL This must be run from a pre-configured Jenkins

	exit 1
fi

. $SCRIPTS_DIR/common/common.sh

################
# Vars
if [ -n "$CF_INSTANCE_IP" -o ! -f /usr/share/tomcat/webapps/jenkins.war ]; then
	# We are running under Cloudfoundry or running via Jetty (eg java -jar jenkins.war)
        JENKINS_CLI_JAR="${JENKINS_CLI_JAR:-$WEBAPP_HOME/WEB-INF/jenkins-cli.jar}"

        # CF_INSTANCE_ADDR is available, but this doesn't seem to connect
        # CF_INSTANCE_IP is also available, but this doesn't seem to connect either
        JENKINS_LOCATION="0.0.0.0:${PORT:-8080}/"
else
        # Best guess
        JENKINS_CLI_JAR="${JENKINS_CLI_JAR:-/usr/share/tomcat/webapps/jenkins/WEB-INF/jenkins-cli.jar}"
        JENKINS_LOCATION="${JENKINS_LOCATION:-localhost:8080/jenkins/}"
fi

JENKINS_URL="http://$JENKINS_BACKUP_USERNAME:$JENKINS_BACKUP_PASSWORD@$JENKINS_LOCATION"
################

cd "$JENKINS_HOME"

################
# Update plugin list
INFO Generating, potentially, updated plugin list
$JAVA_HOME/bin/java -jar $JENKINS_CLI_JAR -noKeyAuth -s $JENKINS_URL list-plugins | awk '{print $1}' | sort >"plugin-list.new"
################

################
# Configure git
[ -f .git/config ] || FATAL "Are we in a git repository?"

configure_git

################

################
# Check if this is really an update
if diff -q /dev/null plugin-list 2>&1 >/dev/null; then
	FATAL "A blank plugin-list has been generated, does the $JENKINS_BACKUP_USERNAME have the correct permissions?"
fi

if [ ! -f plugin-list ] || ! diff -q plugin-list plugin-list.new; then
	INFO Plugins have changed
	diff -u plugin-list plugin-list.new || :

	INFO Updating plugins list

	mv -f plugin-list.new plugin-list
else
	rm -f plugin-list.new
fi
################

################
# Pre-populate .gitignore
if [ ! -f .gitignore ]; then
	INFO Populated initial .gitignore

	cat  >.gitignore <<EOF
.owner
*.bak
*.log
cache
fingerprints/
jobs/*/builds
jobs/*/promotions/*/last*
jobs/*/promotions/*/next*
jobs/*/promotions/*/builds
logs/
plugins/
tools/
updates/
userContent/readme.txt
workspace/
jobs/*/last*
jobs/*/next*

# Some of these may not be sensible
hudson.model.UpdateCenter.xml
identity.key.enc
nodeMonitors.xml
plugin-list
secrets/filepath-filters.d
secrets/hudson.model.Job.serverCookie
secrets/jenkins.model.Jenkins.crumbSalt
secrets/org.jenkinsci.main.modules.instance_identity.InstanceIdentity.KEY
secrets/whitelisted-callables.d
EOF

	git add .gitignore
	git commit -m 'Initial .gitignores' .gitignore

	CHANGES=1
fi
################

################
# Update .gitignore
if [ -n "$GIT_IGNORES" ]; then
	INFO Adding "$GIT_IGNORES" to .gitignore

	echo $GIT_IGNORES | awk '{
		split($0,ignores,/ ?, ?/)
		for(ignore in ignores){
			print ignores[ignore]
		}
	}' >>.gitignore

	git add .gitignore
	git commit -m 'Updated .gitignore' "$JENKINS_HOME/.gitignore"
	
	CHANGES=1
fi
################

################
# Ensure we have a commit message if we have files to add/delete
if [ -z "$GIT_COMMIT_MESSAGE" ] && [ -n "$GIT_ADD_FILES" -o -n "$GIT_DELETE_FILES" ]; then
	FATAL Unwilling to commit changes without Git commmit message
fi

################
# Add new files
if [ -n "$GIT_ADD_FILES" ]; then
	INFO Adding "$GIT_ADD_FILES"

	git_add "$GIT_ADD_FILES" 

	CHANGES=1
fi
################

################
# Delete old files
if [ -n "$GIT_DELETE_FILES" ]; then
	INFO Deleting "$GIT_DELETE_FILES"

	git_rm "$GIT_DELETE_FILES" 

	CHANGES=1
fi
################

################
# Check for untracked files
if ! git_changes; then
	INFO Uncommitted changes exist
	FAIL=1
fi
################

################
# Push any changes
if ! git push $DEFAULT_ORIGIN $DEFAULT_BRANCH; then
	INFO "Unable to push changess to Git, did you need to add the SSH key?"
	cat $REAL_HOME/.ssh/id_rsa.pub
	FATAL Try adding the above key and trying again
fi
################

if git_changes; then
	INFO Changes have been committed
	FAIL=0
fi

exit ${FAIL:-0}
