#

# Cloudfoundry resets HOME as /home/$USER/app
# https://docs.run.pivotal.io/devguide/deploy-apps/environment-variable.html#HOME
# https://github.com/cloudfoundry/java-buildpack/issues/300
if [ -d ~/.ssh ]; then
	export REAL_HOME="$HOME"
elif [ -d "/home/$USER/.ssh" ]; then
	# We are probably on Cloudfoundry
	export REAL_HOME="/home/$USER"
fi

case `uname -s` in
	Darwin)
		CF_OS=macosx64
		;;
	Linux)
		# We're making a blind assumption this is a 64bit install
		CF_OS=linux64
		;;
	Windows)
		FATAL "Whilst we could, possibly, support Windows this functionality is completely untested. You can test it by removing this line"
		# windows64-exe
		CF_OS=windows32-exe
		;;
	*)
		FATAL Unknown operating system
		;;
esac

export JENKINS_CONFIG_SEED_REPO="${JENKINS_CONFIG_SEED_REPO:-https://github.com/ONSdigital/Jenkins-Seed-Config}"
export JENKINS_SCRIPTS_REPO="${JENKINS_SCRIPTS_REPO:-https://github.com/ONSdigital/Jenkins-Scripts}"

export JENKINS_BACKUP_USERNAME='backup_user'
export JENKINS_BACKUP_PASSWORD="${JENKINS_BACKUP_PASSWORD:-backup_user}"

BINARIES_DIR="$SCRIPTS_DIR/binaries"
DOWNLOADS_DIR="$SCRIPTS_DIR/downloads"
WORK_DIR="$SCRIPTS_DIR/work"

PROFILE='00_profile'
PROFILE_DEBUG='01_profile_debug'
PROFILE_GENERATE_VARS='02_profile_generate-vars'
PROFILE_GENERATED_VARS='03_profile_generated-vars'
PROFILE_LOCAL_VARS='04_profile_local-vars'
PROFILE_ENV='05_profile-env'

DEFAULT_ORIGIN=origin
DEFAULT_BRANCH=master

# Until a proper SSL cert is added
IGNORE_SSL="${IGNORE_SSL:-true}"

# Placeholders
# admin:Tr4ff1cCh4os
# readonly:N0tRe4l1y5ecure

CF_URL='https://cli.run.pivotal.io/stable?release=linux64-binary&source=github-rel'
CF="$BINARIES_DIR/cf"

# Script used to turn Cloudfoundry $VCAP_SERVICES var (JSON string) into proper shell variables
CF_VARS_GENERATOR='vcap_services_json_extract.py'
CF_LOCAL_VARS_GENERATOR='service_key_json_extract.py'

# In seconds
CF_SERVICE_DELAY=10
CF_SERVICE_RETRIES=480
# Bitbucket and/or GitHub can sometimes be quite slow
SSH_KEYSCAN_TIMEOUT=10

# Original working directory
ORIGINAL_DIR="`pwd`"
