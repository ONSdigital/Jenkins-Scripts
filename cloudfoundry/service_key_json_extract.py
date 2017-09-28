#!/usr/bin/python
# {
#   "uri": "mongodb://CloudFoundry_sejgt5b8_fj46bm22_7i3d74hu:SVi8WIBfb_k6r0oaiDZKAevQspMUz6KM@ds041486.mlab.com:41486/CloudFoundry_sejgt5b8_fj46bm22",
#   "username": "fail",
#   "passwpord": "foo"
# }


import json
import re
import sys

if len(sys.argv) < 2:
	sys.stderr.write('Incorrect number of arguments\n')
	sys.stderr.write('%s env_prefix [search1:replace1 .. searchN:replaceN]\n' % sys.argv[0])
	sys.exit(1)

# Assume we have found nothing
found		= 0

# ARGV
env_prefix	= sys.argv[1]
regexes		= sys.argv[2:]

sys.stderr.write('Reading from stdin\n')

# Attempt to read any input
stdin_json	= sys.stdin.read()

if not(stdin_json):
	sys.stderr.write('No JSON provided on stdin\n')
	sys.exit(1)

# Can we load it?
try:
	json_doc	= json.loads(stdin_json)
except:
	sys.stderr.write('Unable to load JSON from stdin\n')
	sys.exit(1)

# Flatten the JSON into shell key=value pairs
for credential_key in json_doc.keys():
	key	= credential_key.upper()

	found	= 1

	# Any transformations to apply?
	for regex in regexes:
		(search,replace) = regex.split(':');

		key	= re.sub(search, replace, key)

	# No simple way to check if a string is JSON or not
	if re.search('^[\{\[]',json.dumps(json_doc[credential_key])):
		# We may end up having more JSON, so we need to avoid printing u'JSON_STRING'
		value	= json.dumps(json_doc[credential_key])
	else:
		value	= json_doc[credential_key]

	# Give 'em the key='value'
	print("%s_%s='%s'" % (env_prefix, key, value))

# Did we find anything?
if not(found):
	sys.stderr.write('Nothing found within the JSON\n')
	sys.exit(1)
