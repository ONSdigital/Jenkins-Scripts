#!/bin/sh

# https://www.rabbitmq.com/shovel-dynamic.html
#PUT /api/parameters/shovel/%2f/my-shovel
#{"value":{"src-uri":  "amqp://",              "src-queue":  "my-queue",
#          "dest-uri": "amqp://remote-server", "dest-queue": "another-queue"}}

set -e

SHOVEL_NAME="$1"
RABBITMQ_API_URL="$2"
SRC_URI="$3"
SRC_QUEUE="$4"
DST_URI="$5"
DST_QUEUE="$6"
VHOST="${7:-%2f}"

[ -z "$DST_QUEUE" ] && exit 1

# RABBITMQ_API_URL is terminated by /
curl -vX PUT -H 'Content-Type: application/json' -d @- "${RABBITMQ_API_URL}parameters/shovel/$VHOST/$SHOVEL_NAME" <<EOF
{
	"value": {
		"src-uri":	"$SRC_URI",
		"src-queue":	"$SRC_QUEUE",
		"dest-uri":	"$DST_URI",
		"dest-queue":	"$DST_QUEUE"
	}
}
EOF

