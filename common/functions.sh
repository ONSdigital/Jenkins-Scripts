#


FATAL(){
	echo "FATAL $@"

	exit 1
}

INFO(){
	echo "INFO $@"
}

cf_logged_in(){
	if "$CF" target >/dev/null 2>/dev/null; then
		INFO "Logged in"

		return 0
	else
		INFO "Not logged in"

		return 1
	fi
}

cf_login(){
	# Cannot and must not use any cf_*() functions that call cf_login()
	#
	local cf_api_endpoint="${1:-$CF_API_ENDPOINT}"
	local cf_username="${2:-$CF_USERNAME}"
	local cf_password="${3:-$CF_PASSWORD}"
	local cf_space="${4:-$CF_SPACE}"

	[ -n "$5" ] && shift 4

	local cf_org="${@:-$CF_ORG}"

	if [ -z "$cf_api_endpoint" -o -z "$cf_username" -o -z "$cf_password" -o -z "$cf_space" -o -z "$cf_org" ]; then
		[ -z "$cf_api_endpoint" ] && INFO CF_API_ENDPOINT has not been set
		[ -z "$cf_username" ] && INFO CF_USERNAME has not been set
		[ -z "$cf_password" ] && INFO CF_PASSWORD has not been set
		[ -z "$cf_space" ] && INFO CF_SPACE has not been set
		[ -z "$cf_org" ] && INFO CF_ORG has not been set
		FATAL "Not enough details to login, has CF_API_ENDPOINT, CF_USERNAME, CF_PASSWORD, CF_SPACE and CF_ORG been set?"
	fi

	# We should ensure Cloudfoundry (cf) is installed before doing anything
	install_cf

	# If we are logged in, check if we are pointing at the correct API endpoint
	if "$CF" target >/dev/null 2>&1 && ! "$CF" target 2>&1 | grep -Eq "^api endpoint:.*$cf_api_endpoint"; then
		"$CF" logout

		local logged_out=1
	fi

	# We shouldn't login unless we have to.  Cloudfoundry doesn't supply an easy way to determine if
	# we are logged in
	# We MUST not use cf_target() here as that calls cf_login
	if [ -n "$logged_out" ] || ! "$CF" target -o "$cf_org" >/dev/null 2>&1; then
		[ x"$IGNORE_SSL" = x'true' ] && EXTRA_OPTS='--skip-ssl-validation'

		# We redirect stdin from /dev/null to avoid the prompt asking for a space, eg
		# Targeted org USER
		#
		# Select a space (or press enter to skip):
		# 1. SDX
		# 2. EQ
		#
		# Space>
		#
		# API endpoint:   https://api.system.[SNIP] (API version: 2.54.0)
		# We don't target at login so we can be sure we have a space
		"$CF" login -a "$cf_api_endpoint" -u "$cf_username" -p "$cf_password" $EXTRA_OPTS </dev/null
	fi

	# If the space exists, we end up just targeting it rather than creating it
	"$CF" org "$cf_org" || "$CF" create-org "$cf_space"
	"$CF" target -o "$cf_org"

	"$CF" space "$cf_space" || "$CF" create-space "$cf_space"
	"$CF" target -s "$cf_space"

	return 0
}

cf_create_service(){
	local cf_service="${1:-$CF_SERVICE}"
	local cf_service_plan="${2:-$CF_SERVICE_PLAN}"
	local cf_service_name="${3:-$CF_SERVICE_NAME}"
	local wait_for_deployment="${4:-YES}"

	[ -z "$cf_service_name" ] && return 1

	cf_logged_in || return 1

	# Check if the service has been created
	if cf_service_exists "$cf_service_name"; then
		# Check if the service is available
		cf_service_wait "$cf_service_name" || return 1
	else
		$CF create-service "$cf_service" "$cf_service_plan" "$cf_service_name"

	fi

	[ x"$wait_for_deployment" = x"NO" ] || cf_service_wait "$cf_service_name"
}

cf_service_exists(){
	local cf_service_name="${1:-$CF_SERVICE_NAME}"

	# We don't return 1 as we return 1 if the service is unavailable
	[ -z "$cf_service_name" ] && FATAL No serice name provided

	$CF service "$cf_service_name" >/dev/null 2>&1 && return 0 || return 1
}

cf_service_status(){
	local cf_service_name="${1:-$CF_SERVICE_NAME}"
	local fail_on_delete="${2:-YES}"

	local rc

	# We don't return 1 as we return 1 if the service is unavailable
	[ -z "$cf_service_name" ] && FATAL No serice name provided

	cf_service_exists "$cf_service_name" || FATAL "Service '$cf_service_name' does not exist"

	$CF service "$cf_service_name" | awk -F': ' 'BEGIN{
		rc=1
	}/^Status/{
		if($2 == "create succeeded" ){
			print $0
			rc=0
		} else if($2 == "create in progress"){
			print $0
			rc=2
		} else if($2 == "delete in progress"){
			print $0
			rc=3
		} else {
			printf("Unknown status: %s\n",$2)
			rc=1
		}
	}END{
		exit rc
	}' || rc=$?

	[ 0$rc -eq 3 ] && FATAL "Service '$cf_service_name' is being deleted"

	return ${rc:-0}
}

cf_service_wait(){
	local cf_service_name="${1:-$CF_SERVICE_NAME}"

	# Use sensible defaults
	local retries="${2:-$CF_SERVICE_RETRIES}"
	local delay="${3:-$CF_SERVICE_DELAY}"

	local failed=0

	# We don't return 1 as we return 1 if the service is unavailable
	[ -z "$cf_service_name" ] && FATAL No service name provided

	for _i in `seq 1 $retries`; do
		failed=0

		INFO "Checking service availability ($_i/$retries)"

		cf_service_status "$cf_service_name" && break

		failed=1

		if [ 0$_i -lt $retries ]; then
			INFO "Sleeping for ${delay} seconds before retrying"
			sleep ${delay}s
		fi
	done

	local total_time="`expr $_i \* $delay`"

	[ 0$failed -eq 1 ] && FATAL "Service '$cf_service_name' was not created after $total_time"

	INFO "Service '$cf_service_name' was created"
}

cf_create_service_key(){
	local cf_service="${1:-$CF_SERVICE_NAME}"
	local cf_key="$2"

	[ -z "$cf_key" ] && FATAL No service key name provided

	cf_logged_in || return 1

	cf_service_exists "$cf_service" || FATAL "Service '$cf_service' does not exist"

	if cf_service_key_exists "$cf_service" "$cf_key"; then
		INFO "Service '$cf_service' key '$cf_key' already exists"

		return 0
	fi

	$CF create-service-key "$cf_service" "$cf_key"
}

cf_create_org(){
	local cf_org="${1:-$CF_ORG}"
	local cf_space="${2:-$CF_SPACE}"

	cf_logged_in || return 1

	$CF org "$cf_org" || "$CF" create-space "$cf_org"

	cf_target "$cf_org" "$cf_space"
}

cf_create_space(){
	local cf_space="${1:-$CF_SPACE}"
	local cf_org="${2:-$CF_ORG}"

	cf_logged_in || return 1

	$CF space "$cf_space" || "$CF" create-space "$cf_space"

	cf_target "$cf_org" "$cf_space"
}

# Login (if required), delete existing application and push new application
cf_push(){
	local app_name="$1"

	# This is already specified in the manifest.yml, but as we delete it, its nice to know
	[ -z "$app_name" ] && return 1
	shift 1

	cf_logged_in || return 1

	cf_delete "$app_name"

	$CF push "$app_name" $@
}

# Stop existing application
cf_stop(){
	local app_name="$1"

	[ -n "$1" ] || return 1

	cf_logged_in || return 1

	$CF stop "$app_name"
}

# Delete existing application
cf_delete(){
	local app_name="$1"

	[ -n "$1" ] || return 1

	cf_logged_in || return 1

	$CF delete -r -f "$app_name"
}

# Target space
cf_target(){
	local cf_org="${1:-$CF_ORG}"
	local cf_space="${2:-$CF_SPACE}"

	[ -n "$1" ] || return 1

	cf_logged_in || return 1

	# We need to target the org first, otherwise when we change the org it forgets the space
	[ -n "$cf_org" -a x"$cf_org" != x"NONE" ] && "$CF" target -o  "$cf_org"
	[ -n "$cf_space" -a x"$cf_space" != x"NONE" ] && "$CF" target -s "$cf_space"
}


# Connect to Cloudfoundry and run $@ via SSH
cf_ssh(){
	local app_name="$1"

	[ -n "$1" ] || return 1
	shift 1

	local args="$@"

	cf_logged_in || return 1

	# Our quotes vanish if we call cf()
	"$CF" ssh "$app_name" -t -c "/tmp/lifecycle/launcher app '$args' ''"
}

# Generate manifest.yml, including any optional service binding
generate_manifest(){
	local name="$1"
	local memory="${2:-64M}"
	local instances="${3:-1}"

	local host_set
	local hosts_set

	# Check we have a name
	[ -z "$name" ] && return 1

	# Clear our arguments, so we can treat the remainder as services
	for _i in name memory instances; do
		[ -n "$1" ] && shift
	done

	# Allow multi-application manifests
	if [ -z "$CF_MULTIPART" -o 0"$CF_MULTIPART" -eq 1 ]; then
		cat >manifest.yml <<EOF
---
applications:
EOF
	fi

	(
		cat <<EOF
- name: $name
  memory: $memory
  instances: $instances
EOF

		if [ -n "$CF_BUILDPACK" ]; then
			echo "$CF_BUILDPACK" | grep -q ":" && CF_BUILDPACK="\"$CF_BUILDPACK\""

			# This seems to get ignored
			echo "  buildpack: $CF_BUILDPACK"
		fi


		if [ -n "$CF_NO_HEALTHCHECK" -o x"$CF_HEALTHCHECK" = x"NONE" ]; then
			echo "  health-check-type: none"
		else
			echo "  health-check-type: ${CF_HEALTHCHECK:-port}"
		fi

		if [ -n "$CF_NO_ROUTE" -o x"$CF_DOMAINS" = x"NONE" -o x"$CF_ROUTE" = x"NONE" ]; then
			echo "  no-route: true"

		elif [ -n "$CF_DOMAINS" ]; then
			echo "  routes:"
			for _r in $CF_DOMAINS; do
				echo "  - route: $_r"
			done
		fi

		if [ -n "$CF_NO_HOST" -o x"$CF_HOSTS" = x"NONE" ]; then
			echo "  no-hostname: true"

		elif [ -n "$CF_HOSTS" ]; then
			# Cloudfoundry is dumb
			# If hosts: are set, but host: is not set the following warning pops up:
			# WARNING: No manifest value for hostname. Using app name: $CF_APPNAME
			for _r in $CF_HOSTS; do
				if [ -z "$host_set" ]; then
					echo "  host: $_r"

					host_set=1
				elif [ -z "$hosts_set" ]; then
					echo "  hosts:"

					hosts_set=1
				fi

				if [ -n "$hosts_set" ]; then
					echo "  - $_r"
				fi
			done
		else
			# Provide a sensible default
			echo "  host: $name"
		fi

		if [ -n "$CF_PATH" -a x"$CF_PATH" != x"NONE" ]; then
			echo "  path: $CF_PATH"
		fi

		if [ -n "$CF_COMMAND" -a x"$CF_COMMAND" != x"NONE" ]; then
			cat <<EOF
  command: $CF_COMMAND
EOF
		fi

		if [ -n "$CF_DISK" ]; then
			echo "  disk_quota: $CF_DISK"
		fi

		if [ -n "$CF_TIMEOUT" -a x"$CF_TIMEOUT" != x"NONE" ]; then
			echo "  timeout: $CF_TIMEOUT"
		fi

		if [ -n "$1" -a x"$1" != x"NONE" ]; then
			echo "  services:"

			for _s in $@; do
				echo "  - $_s"
			done
		fi

		if [ -n "$CF_ENV_VARS" ]; then
			eval generate_manifest_envs $CF_ENV_VARS
		fi
	) >>manifest.yml
}

generate_manifest_envs(){
	[ -n "$1" ] || return 0

	echo "  env:" >>manifest.yml

	for _i in $@; do
		eval _var="\$$_i"
		cat <<EOF
    $_i: "$_var"
EOF
	done >>manifest.yml
}

# Generate Procfile
generate_procfile(){
	# $@ should be in YAML format
	local type="$1"

	[ -n "$2" ] || return 1

	shift 1

	cat >Procfile <<EOF
$type "$@"
EOF
}

generate_staticfile(){
	local type="$1"

	[ -z "$2" ] && return 1

	shift

	cat >Staticfile <<EOF
$type $@
EOF
}

# Generate application runtime version
generate_runtime(){
	[ -z "$1" ] && return 1

	cat >runtime.txt <<EOF
$@
EOF
}

# Internal for Jenkins - this can be used to store metadata (eg Git hash, build name/version/time)
generate_metadata(){
	cat >metadata.txt <<EOF
$@
EOF
}

generate_profile(){
	mkdir -p .profile.d

	cat >>.profile.d/$PROFILE <<'EOF'
# .profile
set -e

EOF
}

# Turn any internal enviromental variables into ones for Cloudfoundry
generate_env(){
	[ -n "$1" ] || return 1

	[ -d .profile.d ] || generate_profile

	(
		echo '# Global variables'
		for _v in $@; do
			eval _var="\$$_v"

			[ -n "$_var" ] && echo "export $_v='$_var'"

			unset _var
		done
	) >>.profile.d/$PROFILE_ENV
}

# Enable debugging
generate_debug_profile(){
	[ -d .profile.d ] || generate_profile

	cat >.profile.d/$PROFILE_DEBUG <<'EOF'
set -x
echo ###########
echo ENV
echo ###########
env
echo
echo
echo ###########
echo SET
echo ###########
set
echo
echo
echo ###########
echo VCAP_SERVICES
echo ###########
cat <<EOF_INNER
$VCAP_SERVICES
EOF_INNER
EOF
}

# Once running on Cloudfoundry turn the $VCAP_SERVICES JSON string into shell variables
generate_cf_vars(){
	local service="$1"
	local name="$2"
	local env_prefix="$3"

	[ -z "$3" ] && return 1
	shift 3

	[ -d .profile.d ] || generate_profile

	[ -f "$CF_VARS_GENERATOR" ] || cp "$SCRIPTS_DIR/cloudfoundry/$CF_VARS_GENERATOR" .

	# The /usr/bin/python is not fully working, so we use the python set in the environment
	# $@'s regexes are in the form of 'search:replace'
	cat >>.profile.d/$PROFILE_GENERATE_VARS  <<EOF
python "$CF_VARS_GENERATOR" "$service" "$name" "$env_prefix" $@ | sed 's/^/export /g' >>.profile.d/$PROFILE_GENERATED_VARS
EOF

	# Cloudfoundry first lists .profile.d/*.sh and then executes everything it finds.  We need to create a placeholder for our
	# generated vars, otherwise the initial list won't contain them
	[ -f .profile.d/$PROFILE_GENERATED_VARS ] || echo "# Place holder for vars generated by $PROFILE_GENERATED_VARS" >.profile.d/$PROFILE_GENERATED_VARS
}

generate_cf_local_vars(){
	local cf_service="$1"
	local cf_key="$2"
	local env_prefix="$3"

	[ -z "$3" ] && FATAL No env_prefix provided
	shift 3

	[ -d .profile.d ] || generate_profile

	if ! "$CF" service "$cf_service" 2>&1 >/dev/null; then
		INFO "Unknown service: $cf_service"

		return 1
	fi

	cf_service_key_exists "$cf_service" "$cf_key" || FATAL "Service '$cf_service' key '$cf_key' does not exist"

	# key must exist (see cf_create_service_key)
	$CF service-key "$cf_service" "$cf_key" | awk '!/^(Get.*)?$/{ if(/^No service key/) exit 1; print $0 }' | \
		 python "$SCRIPTS_DIR/cloudfoundry/$CF_LOCAL_VARS_GENERATOR" "$env_prefix" $@ | sed 's/^/export /g' >>.profile.d/$PROFILE_LOCAL_VARS
}

cf_service_key_exists(){
	local cf_service="$1"
	local cf_key="$2"

	[ -z "$cf_key" ] && FATAL Service key not provided

	# They don't give a useful exit code (rc=0)
	$CF service-key "$cf_service" "$cf_key" | grep -Eq "^No service key $cf_key found for service instance $cf_service$" && return 1

	return 0
}

update_scripts(){
	[ -z "$SCRIPTS_DIR" ] && return 1

	cd "$SCRIPTS_DIR"

	git pull -v

	cd -
}

replace_known_hosts(){
	local failed=0

	INFO It is your responsiblity to ensure the keys are correct
	INFO These are the existing keys:
	cat <"$REAL_HOME/.ssh/known_hosts"
	INFO

	# Remove any previous cruft
	find "$REAL_HOME/.ssh" -name known_hosts-\* -delete

	for _i in $@; do
		ssh-keyscan -T $SSH_KEYSCAN_TIMEOUT "$_i" >"$REAL_HOME/.ssh/known_hosts-$_i"

		# ssh-keyscan often returns an empty key when scanning Github and Bitbucket, so we need to know when things have
		# failed
		# We don't return immediately as hitting each of the endpoints tickles it just enough that the next hit will be
		# more likely to collect a working key
		#
		if [ -f "$REAL_HOME/.ssh/known_hosts-$_i" ] && grep -q "$_i" "$REAL_HOME/.ssh/known_hosts-$_i"; then
			cat "$REAL_HOME/.ssh/known_hosts-$_i"  >>"$REAL_HOME/.ssh/known_hosts-updated"
			# Ensure we have a trailing newline
			echo >>"$REAL_HOME/.ssh/known_hosts-updated"
		else
			INFO "Failed to obtain key for $_i - this is often temporary, so please retry"

			failed=1
		fi
	done

	if [ 0$failed -eq 0 ]; then
		sort -u "$REAL_HOME/.ssh/known_hosts-updated" >"$REAL_HOME/.ssh/known_hosts"
	fi

	# Remove any previous cruft
	find "$REAL_HOME/.ssh" -name known_hosts-\* -delete

	# We have failures
	[ 0$failed -ne 0 ] && return 1

	INFO These are the updated keys:
	cat <"$REAL_HOME/.ssh/known_hosts"
	INFO
}

display_ssh_pubkeys(){
	cat $REAL_HOME/.ssh/*.pub
}

install_cf(){
	# Check if we have an executable version
	[ -x "$CF" ] && return 0

	# Clear any obstructions
	[ -f "$CF" ] && rm -f "$CF"

	# Ensure our work area is clear
	[ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"

	# Creating any missing directories
	for _i in $BINARIES_DIR $DOWNLOADS_DIR $WORK_DIR; do
		[ -d "$_i" ] || mkdir -p "$_i"
	done

	# Download the archive
	curl -L -o "$DOWNLOADS_DIR/cf.tar.gz" "$CF_URL"

	INFO "Extracting $DOWNLOADS_DIR/cf.tar.gz"
	tar -C "$WORK_DIR" -zxf "$DOWNLOADS_DIR/cf.tar.gz" cf

	# Ensure things are where we expect them
	if [ ! -f "$WORK_DIR/cf" ]; then
		INFO "Unable to find $WORK_DIR/cf"
		find $WORK_DIR

		FATAL Failed to find $WORK_DIR/cf
	fi

	INFO Installing cf
	mv "$WORK_DIR/cf" "$BINARIES_DIR/cf"
}

cf_logs_clean_exit(){
	(
		cf_logs $@
	)

	# We do not care about the exit code
	return 0
}

cf_logs(){
	local application="$1"
	local recent="${2:-NO}"

	[ -z "$application" ] && FATAL No application name given

	cf_logged_in || return 1

	# Jenkins will give us a true/false
	[ x"$recent" = x"YES" -o x"$recent" = x"true" ] && local cf_log_opts="--recent"

	$CF logs $cf_log_opts  "$application"
}

configure_git(){
	local git_user="${1:-$USER}"
	local git_email="${2:-$git_user@${HOSTNAME:-localhost}}"

	if ! git config user.email >/dev/null; then
		INFO Setting Git email address as "$git_email"

		git config user.email "$git_email"
	fi

	#
	if ! git config user.name >/dev/null; then
		INFO Setting Git username as "$git_user"

		git config user.name "$git_user"
	fi

	#
	if ! git config push.default >/dev/null; then
		INFO Setting default push method

		git config push.default matching
	fi
}
