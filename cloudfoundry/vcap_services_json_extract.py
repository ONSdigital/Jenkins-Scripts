#!/usr/bin/python
#
# VCAP_SERVICES='{"mlab":[{
#   "credentials": {
#     "uri": "mongodb://CloudFoundry_sejgt5b8_fj46bm22_7i3d74hu:SVi8WIBfb_k6r0oaiDZKAevQspMUz6KM@ds041486.mlab.com:41486/CloudFoundry_sejgt5b8_fj46bm22"
#   },
#   "syslog_drain_url": null,
#   "volume_mounts": [
#   ],
#   "label": "mlab",
#   "provider": "null",
#   "plan": "sandbox",
#   "name": "Test-Mongo",
#   "tags": [
#   ]
# }]}'
#

import json
import os
import re
import sys

if len(sys.argv) < 4:
	sys.stderr.write('Incorrect number of arguments\n')
	sys.stderr.write('%s service name env_prefix [search1:replace1 .. searchN:replaceN]\n' % sys.argv[0])
	sys.exit(1)

# Assume we have found nothing
found		= 0

# ARGV
provider	= sys.argv[1]
name		= sys.argv[2]
env_prefix	= sys.argv[3]
regexes		= sys.argv[4:]

# Do we have the correct env set?
if not(os.getenv('VCAP_SERVICES')):
	sys.stderr.write('No JSON provided, set VCAP_SERVICES\n')
	sys.exit(1)

# Can we load it?
try:
	json_doc	= json.loads(os.getenv('VCAP_SERVICES'))
except:
	sys.stderr.write('Unable to load JSON from $VCAP_SERVICES\n')
	sys.exit(1)

# Does it look semi-valid?
if not(provider in json_doc.keys()):
	sys.stderr.write('%s does not exist in JSON\n' % provider)
	sys.exit(1)

# Does it look more valid?
if type(json_doc[provider]) != list:
	sys.stderr.write('JSON[%s] does not contain any services\n' % provider)
	sys.exit(1)

for service in json_doc[provider]:
	# Does it contain our requested service?
	if not('credentials' in service.keys()) or not('name' in service.keys()) or service['name'] != name:
		continue

	# Found it
	found	= 1

	# Flatten the JSON into shell key=value pairs
	for credential_key in service['credentials'].keys():
		key	= credential_key.upper()

		# Any transformations to apply?
		for regex in regexes:
			(search,replace) = regex.split(':');

			key	= re.sub(search, replace, key)

		# Urgh, give me Perl
		json_check = re.compile('^[\{\[]')

		# No simple way to check if a string is JSON or not
		if re.search('^[\{\[]',json.dumps(service['credentials'][credential_key])):
			# We may end up having more JSON, so we need to avoid print u'JSON_STRING'
			value	= json.dumps(service['credentials'][credential_key])
		else:
			value	= service['credentials'][credential_key]

		# Give 'em the key='value'
		print("%s_%s='%s'" % (env_prefix, key, value))

# Did we find anything?
if not(found):
	sys.stderr.write('Unable to find %s service named %s\n' % (service, name))
	sys.exit(1)
