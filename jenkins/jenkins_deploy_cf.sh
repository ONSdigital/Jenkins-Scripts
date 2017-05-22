#!/bin/sh
#
#
set -e

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

. "$SCRIPTS_DIR/common/common.sh"

JENKINS_APPNAME="${JENKINS_APPNAME:-jenkins}"
JENKINS_RELEASE_TYPE="${JENKINS_RELEASE_TYPE:-STABLE}"
# 4096M minimum to avoid complaints about insufficient cache
JENKINS_MEMORY="${JENKINS_MEMORY:-4096M}"
# 2048M maximum allow storage
JENKINS_DISK="${JENKINS_DISK:-2048M}"

JENKINS_STABLE_WAR_URL="${JENKINS_STABLE_WAR_URL:-http://mirrors.jenkins-ci.org/war-stable/latest/jenkins.war}"
JENKINS_LATEST_WAR_URL="${JENKINS_LATEST_WAR_URL:-http://mirrors.jenkins-ci.org/war/latest/jenkins.war}"

# Jenkins will not start without this plugin
DEFAULT_PLUGINS="https://updates.jenkins-ci.org/latest/matrix-auth.hpi"

# Default private key
SSH_PRIVATE_KEY='id_rsa'

# Parse options
for i in `seq 1 $#`; do
	[ -z "$1" ] && break

	case "$1" in
		-n|--name)
			JENKINS_APPNAME="$2"
			shift 2
			;;
		-r|--release-type)
			JENKINS_RELEASE_TYPE="$2"
			shift 2
			;;
		-m|--memory)
			JENKINS_MEMORY="$2"
			shift 2
			;;
		-b|--cf-download-url)
			CF_URL="$2"
			CF_URL_SET=1
			shift 2
			;;
		-d|--disk-quota)
			JENKINS_DISK="$2"
			shift 2
			;;
		-c|--config-repo)
			JENKINS_CONFIG_NEW_REPO="$2"
			shift 2
			;;
		--deploy-config-repo)
			DEPLOY_JENKINS_CONFIG_NEW_REPO="$2"
			shift 2
			;;
		-k|--ssh-private-key)
			[ -f "$SSH_PRIVATE_KEY" ] || INFO "$SSH_PRIVATE_KEY does not exist so we'll generate one"
			SSH_PRIVATE_KEY="$2"
			shift 2
			;;
		-K|--ssh-keyscan-host)
			[ -n "$SSH_KEYSCAN_HOSTS" ] && SSH_KEYSCAN_HOSTS="$SSH_KEYSCAN_HOSTS $2" || SSH_KEYSCAN_HOSTS="$2"
			shift 2
			;;
		-C|--config-seed-repo)
			JENKINS_CONFIG_SEED_REPO="$2"
			shift 2
			;;
		--deploy-config-seed-repo)
			DEPLOY_JENKINS_CONFIG_SEED_REPO="$2"
			shift 2
			;;
		-S|--scripts-repo)
			JENKINS_SCRIPTS_REPO="$2"
			shift 2
			;;
		--deploy-scripts-repo)
			DEPLOY_JENKINS_SCRIPTS_REPO="$2"
			shift 2
			;;
		-P|--plugins)
			# comma separated list of plugins to preload
			PLUGINS="$2"
			shift 2
			;;
		-X|--disable-csp-security)
			DISABLE_CSP=1
			shift
			;;
		-D|--debubg)
			DEBUG=1
			shift
			;;
		-a|--cf-api-endpoint)
			CF_API_ENDPOINT="$2"
			shift 2
			;;
		-u|--cf-username)
			CF_USERNAME="$2"
			shift 2
			;;
		-p|--cf-password)
			CF_PASSWORD="$2"
			shift 2
			;;
		-s|--cf-space)
			shift
			for j in $@; do
				case "$j" in
					-*)
						break
						;;
					*)
						[ -n "$CF_SPACE" ] && CF_SPACE="$CF_SPACE $j" || CF_SPACE="$j"
						shift
				esac
			done
			;;
		-o|--cf-organisation)
			shift
			for j in $@; do
				case "$j" in
					-*)
						break
						;;
					*)
						[ -n "$CF_ORG" ] && CF_ORG="$CF_ORG $j" || CF_ORG="$j"
						shift
				esac
			done
			;;
		*)
			FATAL "Unknown option $1"
			;;
	esac
done

for m in CF_API_ENDPOINT CF_USERNAME CF_PASSWORD CF_SPACE CF_ORG; do
	eval v="\$$m"

	[ -z "$v" ] && FATAL "$m has not been set"

	unset v
done

if [ -z "$CF_URL_SET" ] && ! uname -s | grep -q 'Linux'; then
	FATAL "You must set -b|--cf-download-url to point to th location of the CF download for your machine"
fi

which unzip >/dev/null 2>&1 || FATAL 'Please install unzip: sudo yum install -y unzip'


case "$JENKINS_RELEASE_TYPE" in
	[Ll][Aa][Tt][Ee][Ss][Tt])
		JENKINS_WAR_URL="$JENKINS_LATEST_WAR_URL"
		;;

	[Ss][Tt][Aa][Bb][Ll][Ee])
		JENKINS_WAR_URL="$JENKINS_STABLE_WAR_URL"
		;;
	*)
		echo "Unknown Jenkins type: $JENKINS_RELEASE_TYPE"
		echo "Valid types: latest or stable"

		exit 1
esac

# Ensure we are clean
[ -d deployment ] && rm -rf deployment

mkdir -p deployment

cd deployment

# Ensure we have the latest version
[ -f "../jenkins-$JENKINS_RELEASE_TYPE.war" ] && CURL_OPT="-z ../jenkins-$JENKINS_RELEASE_TYPE.war"
curl -L $CURL_OPT -o ../jenkins-$JENKINS_RELEASE_TYPE.war "$JENKINS_WAR_URL"

# Explode the jar file
unzip ../jenkins-$JENKINS_RELEASE_TYPE.war

# We need to remove the manifest.mf, otherwise Cloudfoundry tries to be intelligent and run Main.class rather
# rather than deploying to Tomcat
# Sometimes we get MANIFEST.MF and sometimes we get manifest.mf
find META-INF -iname MANIFEST.MF -delete

# Allow disabling of CSP
if [ -n "$DISABLE_CSP" -a x"$DISABLE_CSP" != x"false" ]; then
	# Sanity check...
	[ -f WEB-INF/init.groovy ] && FATAL deployment/WEB-INF/init.groovy already exists

	cat >WEB-INF/init.groovy <<EOF
import hudson.model.*

println('Setting hudson.model.DirectoryBrowserSupport.CSP==""\n')
System.setProperty("hudson.model.DirectoryBrowserSupport.CSP", "")
EOF
fi

# Generate our manifest
cat >manifest.yml <<EOF
applications:
- name: $JENKINS_APPNAME
  memory: $JENKINS_MEMORY
  disk_quota: $JENKINS_DISK
  health-check-type: none
  instances: 1
  env:
    JBP_CONFIG_SPRING_AUTO_RECONFIGURATION: '{enabled: false}'
EOF

git clone "${DEPLOY_JENKINS_CONFIG_SEED_REPO:-$JENKINS_CONFIG_SEED_REPO}" -b master jenkins_home

if [ x"$DEPLOY_JENKINS_CONFIG_SEED_REPO" != x"$JENKINS_CONFIG_SEED_REPO" ]; then
	cd jenkins_home

	INFO 'Fixing seed repo origin'
	git remote set-url origin "$JENKINS_CONFIG_SEED_REPO"
	
	cd -
fi

if [ -n "$JENKINS_CONFIG_NEW_REPO" ]; then
	cd jenkins_home

	INFO Renaming origin repository as seed repository
	git remote rename origin seed

	INFO Adding new origin repository
	git remote add origin ${DEPLOY_JENKINS_CONFIG_NEW_REPO:-$JENKINS_CONFIG_NEW_REPO}

	INFO Pushing configuration to new repository
	git push origin master || FATAL "Unable to push to ${DEPLOY_JENKINS_CONFIG_NEW_REPO:-$JENKINS_CONFIG_NEW_REPO} - does the repository exist and/or do permissions allow pushing?"

	if [ x"$DEPLOY_JENKINS_CONFIG_NEW_REPO" != x"$JENKINS_CONFIG_NEW_REPO" ]; then
		INFO 'Fixing config repo origin'
		git remote set-url origin "$JENKINS_CONFIG_NEW_REPO"
	fi

	cd -
fi

# Disable initial config.xml - it'll get renamed by init.groovy
mv jenkins_home/config.xml jenkins_home/_config.xml

INFO 'Installing initial plugin(s)'
[ -d jenkins_home/plugins ] || mkdir -p jenkins_home/plugins
OLDIFS="$IFS"
IFS=,

cd jenkins_home/plugins

for p in ${PLUGINS:-$DEFAULT_PLUGINS}; do
	INFO "Downloading $p"

	curl -O "$p"
done

cd -

IFS="$OLDIFS"

# Using submodules is painful, as the submodule is a point-in-time checkout, unless its manually updated
# and then the parent repo has the change committed
git clone "${DEPLOY_JENKINS_SCRIPTS_REPO:-$JENKINS_SCRIPTS_REPO}" -b master jenkins_scripts

if [ x"$DEPLOY_JENKINS_SCRIPTS_REPO" != x"$JENKINS_SCRIPTS_REPO" ]; then
	cd jenkins_scripts

	INFO 'Fixing scripts repo origin'
	git remote set-url origin "$JENKINS_SCRIPTS_REPO"

	cd -
fi

# Cloudfoundry nobbles the .git or if its renamed it nobbles .git*/{branchs,objects,refs} - so we have to jump through a few hoops
tar -zcf jenkins_home_scripts.tgz jenkins_home jenkins_scripts

rm -rf jenkins_home jenkins_scripts

# Detect the SED variant - this is only really useful when running jenkins/jenkins_deploy.sh
# Some BSD sed variants don't handle -r they use -E for extended regular expression
# GNU sed doesn't complain when -E is used, so we check for the BSD variant
sed </dev/null 2>&1 | grep -q GNU && SED_OPT='-r' || SED_OPT='-E'

# Suck in the SSH keys for our Git repos
for i in $JENKINS_CONFIG_REPO $JENKINS_CONFIG_SEED_REPO $JENKINS_SCRIPTS_REPO; do
	# We only want to scan a host if we are connecting via SSH
	echo $i | grep -Eq '^((https?|file|git)://|~?/)' && continue

	echo $i | sed $SED_OPT -e 's,^[a-z]+://([^@]+@)([a-z0-9\.-]+)([:/].*)?$,\2,g' | xargs ssh-keyscan -T $SSH_KEYSCAN_TIMEOUT >>known_hosts
done

# ... and any extra keys
for i in $SSH_KEYSCAN_HOSTS; do
	ssh-keyscan -T $SSH_KEYSCAN_TIMEOUT $i
done | sort -u >>known_hosts

if [ ! -f "$ORIGINAL_DIR/$SSH_PRIVATE_KEY" ]; then
	# Ensure we have a key
	ssh-keygen -t rsa -f "id_rsa" -N '' -C "$JENKINS_APPNAME"

	INFO "You will need to add the following public key to the correct repositories to allow access"
	INFO "We'll print this again at the end in case you miss this time"
	cat id_rsa.pub
else
	grep -q 'BEGIN DSA PRIVATE KEY' "$ORIGINAL_DIR/$SSH_PRIVATE_KEY" && KEY_NAME="id_dsa"
	grep -q 'BEGIN RSA PRIVATE KEY' "$ORIGINAL_DIR/$SSH_PRIVATE_KEY" && KEY_NAME="id_rsa"

	[ -z "$KEY_NAME" ] && FATAL Unable to determine ssh key type

	cp "$ORIGINAL_DIR/$SSH_PRIVATE_KEY" $KEY_NAME


	# Ensure our key has the correct permissions, otherwise ssh-keygen fails
	chmod 0600 $KEY_NAME

	INFO Calculating SSH public key from "$SSH_PRIVATE_KEY"
	ssh-keygen -f $KEY_NAME -y >$KEY_NAME.pub
fi

mkdir -p .profile.d

# Preconfigure our environment
cat >.profile.d/00_jenkins_preconfig.sh <<'EOF_OUTER'
set -e

# We use WEBAPP_HOME to find the jenkins-cli.jar
export WEBAPP_HOME="$PWD"

export JENKINS_HOME="$WEBAPP_HOME/jenkins_home"
export SCRIPTS_DIR="$WEBAPP_HOME/jenkins_scripts"

# Cloudfoundry resets HOME as /home/$USER/app
# https://docs.run.pivotal.io/devguide/deploy-apps/environment-variable.html#HOME
# https://github.com/cloudfoundry/java-buildpack/issues/300
export REAL_HOME="/home/$USER"

tar -zxf jenkins_home_scripts.tgz

cd "$JENKINS_HOME"

[ -f _init.groovy ] && cp _init.groovy init.groovy

cd -

# Create ~/.ssh in the correct place. CF incorrectly sets HOME=/home/$USER/app despite it pointing to
# /home/$USER in /etc/passwd
[ -d "$REAL_HOME/.ssh" ] || mkdir -m 0700 -p $REAL_HOME/.ssh

# Configure SSH
for i in dsa rsa; do
	[ -f "id_$i" -a -f "id_$i.pub" ] || continue

	mv id_$i id_$i.pub $REAL_HOME/.ssh/
done

cat known_hosts >>$REAL_HOME/.ssh/known_hosts

# Remove our temporary files
rm -f known_hosts id_rsa id_rsa.pub
rm -f jenkins_home_scripts.tgz

cat >.profile.d/00_jenkins_config <<EOF
export WEBAPP_HOME="$WEBAPP_HOME"
export SCRIPTS_DIR="$SCRIPTS_DIR"
export JENKINS_HOME="$JENKINS_HOME"
EOF

# No point in repeating ourselves, so we remove this script and assume things stay static
rm -f .profile.d/00_jenkins_preconfig.sh
EOF_OUTER

# These two profiles are here to workaround Cloudfoundry's lack of persistent storage.  If an application crashes,
# shutdown or moves local storage is lost
#
# Until we add the new SSH key this will fail, this isn't a concern as a fresh deployment should have an identical
# config to that held in Git
cat >.profile.d/01_jenkins_git_update.sh <<'EOF'
cd "$JENKINS_HOME"

echo If the SSH key has not yet been added to the Git repositories you may see errors here
git pull origin master || :

cd -

cd "$SCRIPTS_DIR"

git pull origin master || :

cd -
EOF

cf_login

cf_create_org

cf_create_space

cf_push "$JENKINS_APPNAME"

INFO
INFO "Jenkins should be available shortly"
INFO
INFO "Please wait whilst things startup... (this could take a while)"

if [ -n "$DEBUG" ]; then
	INFO "Debug has been enabled"
	INFO "Output Jenkins logs. Please do not interrupt, things should exit once Jenkins has loaded correctly"

	sleep 10
fi

$CF logs "$JENKINS_APPNAME" | tee "$JENKINS_APPNAME-deploy.log" | awk -v debug="$DEBUG" '{
	if($0 ~ /Jenkins is fully up and running/)
		exit 0

	if(debug)
		print $0

	if($0 ~ /(Jenkins stopped|Failed to list up hs_err_pid files)/){
		printf("There was an issue deploying Jenkins, try restarting, otherwise redeploy")
		exit 1
	}
}' && SUCCESS=1 || SUCCESS=0

# We try our best to get things to work properly, but both Jenkins and Cloudfoundry work against us:
# Jenkins, often, doesn't correctly load all of the plugins - so we run the plugin loading 3 times
# Cloudfoundry sometimes performs a port check the very moment Jenkins is restarted resulting in a
# redeploy - so we've disabled the port checking.
INFO
INFO
if [ x"$SUCCESS" = x"1" ]; then
	INFO "Jenkins may still be loading, so hold tight"
	INFO
	INFO "You will need to add the following public key to ${JENKINS_CONFIG_NEW_REPO:-$JENKINS_CONFIG_SEED_REPO}"
	INFO
	cat "$SSH_PRIVATE_KEY"
	INFO
	# If we can find the log line of the failed plugin we could add it to the above AWK section and present a warning to load
	# a given plugin - as we run the plugin load three times, we'd need a little bit of logic there
	INFO "Even though Jenkins may have finished loading, its possible not all of the plugins were loaded. Unfortunately"
	INFO "this is difficult to detect - so run the 'Backup Jenkins' job and ensure the plugin list doesn't have any changes"
	INFO "or at the very least looks sensible"
	# Need to make domain name configurable - env var of domain may be available, or easily set during deployment
	INFO "Check if there is any data under: https://$JENKINS_APPNAME.apps.${CF_INSTANCE_DOMAIN:-CF_DOMAIN}/administrativeMonitor/OldData/manage"
	INFO "if there is, check its sensible, otherwise redeploy"
	INFO
	INFO "Your Jenkins should will shortly be accessible from https://$JENKINS_APPNAME.apps.${CF_INSTANCE_DOMAIN:-CF_DOMAIN}"
else
	tail -n20 "$JENKINS_APPNAME-deploy-deploy.log"

	FATAL "Jenkins failed, please retry. Check $JENKINS_APP_NAME-deploy.log for more details"
fi
