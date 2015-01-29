#!/bin/bash
# File: deis-backup.sh
# Author: Ian Blenke
# License: Apache License, Version 2.0

# Error out whenever something returns a non-zero errno
set -eo pipefail

# http://docs.deis.io/en/latest/managing_deis/backing_up_data/

[ -n "$AWS_ACCESS_KEY_ID" ] || (
  echo "Need actual AWS S3 environment variable defined: AWS_ACCESS_KEY_ID"
  false
)
[ -n "$AWS_SECRET_ACCESS_KEY" ] || (
  echo "Need actual AWS S3 environment variable defined: AWS_SECRET_ACCESS_KEY"
  false
)
[ -n "$AWS_BACKUP_BUCKET" ] || {
  echo "Need AWS_BACKUP_BUCKET defined"
  false
}
[ -n "$DEIS_DOMAIN" ] || {
  echo "Need DEIS_DOMAIN defined that you are using for your wildcard DNS for DEIS"
  false
}
[ -n "$HOST" ] || {
  echo "Need HOST of container defined"
  false
}

# configure etcd
ETCD_PORT=${ETCD_PORT:-4001}
ETCD="$HOST:$ETCD_PORT"
ETCD_TTL=${ETCD_TTL:-10}

# wait for etcd to be available
until etcdctl --no-sync -C $ETCD ls >/dev/null 2>&1; do
  echo "runner: waiting for etcd at $ETCD..."
  sleep $(($ETCD_TTL/2))  # sleep for half the TTL
done

# Define this if you are worried about SSLed access to both Deis and AWS
USE_HTTPS="${USE_HTTPS:-False}"

DEIS_CONFIG_FILE=${DEIS_CONFIG_FILE:-~/.s3cfg.deis}
AWS_CONFIG_FILE=${AWS_CONFIG_FILE:-~/.s3cfg.aws}

CEPH_ACCESS_KEY_ID="$(etcdctl -C ${ETCD} get deis/store/gateway/accessKey)"
CEPH_SECRET_ACCESS_KEY="$(etcdctl -C ${ETCD} get deis/store/gateway/secretKey)"
DATABASE_BUCKET_NAME="$(etcdctl -C ${ETCD} get /deis/database/bucketName)"
REGISTRY_BUCKET_NAME="$(etcdctl -C ${ETCD} get /deis/registry/bucketName)"
DATABASE_BUCKET_NAME="${DATABASE_BUCKET_NAME:-db_wal}"
REGISTRY_BUCKET_NAME="${REGISTRY_BUCKET_NAME:-registry}"

# Generate the config we will use for AWS access
[ -f "${AWS_CONFIG_FILE}" ] || cat <<EOF > "${AWS_CONFIG_FILE}"
[default]
access_key = ${AWS_ACCESS_KEY_ID}
access_token =
add_encoding_exts =
add_headers =
bucket_location = US
cache_file =
cloudfront_host = cloudfront.amazonaws.com
default_mime_type = binary/octet-stream
delay_updates = False
delete_after = False
delete_after_fetch = False
delete_removed = False
dry_run = False
enable_multipart = True
encoding = ANSI_X3.4-1968
encrypt = False
expiry_date =
expiry_days =
expiry_prefix =
follow_symlinks = False
force = False
get_continue = False
gpg_command = /usr/bin/gpg
gpg_decrypt = %(gpg_command)s -d --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_encrypt = %(gpg_command)s -c --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_passphrase =
guess_mime_type = True
host_base = s3.amazonaws.com
host_bucket = %(bucket)s.s3.amazonaws.com
human_readable_sizes = False
ignore_failed_copy = False
invalidate_default_index_on_cf = False
invalidate_default_index_root_on_cf = True
invalidate_on_cf = False
list_md5 = False
log_target_prefix =
max_delete = -1
mime_type =
multipart_chunk_size_mb = 15
preserve_attrs = True
progress_meter = True
proxy_host =
proxy_port = 0
put_continue = False
recursive = False
recv_chunk = 4096
reduced_redundancy = False
restore_days = 1
secret_key = ${AWS_SECRET_ACCESS_KEY}
send_chunk = 4096
server_side_encryption = True
simpledb_host = sdb.amazonaws.com
skip_existing = False
socket_timeout = 300
urlencoding_mode = normal
use_https = ${USE_HTTPS}
use_mime_magic = True
use_path_mode = False
verbosity = WARNING
website_endpoint = http://%(bucket)s.s3-website-%(location)s.amazonaws.com/
website_error =
website_index = index.html
EOF

# Generate the config we will use for Deis access
[ -f "${DEIS_CONFIG_FILE}" ] || cat <<EOF > "${DEIS_CONFIG_FILE}"
[default]
access_key = ${CEPH_ACCESS_KEY_ID}
access_token =
add_encoding_exts =
add_headers =
bucket_location = US
cache_file =
cloudfront_host = cloudfront.amazonaws.com
default_mime_type = binary/octet-stream
delay_updates = False
delete_after = False
delete_after_fetch = False
delete_removed = False
dry_run = False
enable_multipart = True
encoding = UTF-8
encrypt = False
expiry_date =
expiry_days =
expiry_prefix =
follow_symlinks = False
force = False
get_continue = False
gpg_command = /usr/bin/gpg
gpg_decrypt = %(gpg_command)s -d --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_encrypt = %(gpg_command)s -c --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_passphrase =
guess_mime_type = True
host_base = deis-store.${DEIS_DOMAIN}
host_bucket = deis-store.${DEIS_DOMAIN}/%(bucket)
human_readable_sizes = False
ignore_failed_copy = False
invalidate_default_index_on_cf = False
invalidate_default_index_root_on_cf = True
invalidate_on_cf = False
list_md5 = False
log_target_prefix =
max_delete = -1
mime_type =
multipart_chunk_size_mb = 15
preserve_attrs = True
progress_meter = True
proxy_host =
proxy_port = 0
put_continue = False
recursive = False
recv_chunk = 4096
reduced_redundancy = False
restore_days = 1
secret_key = ${CEPH_SECRET_ACCESS_KEY}
send_chunk = 4096
server_side_encryption = False
simpledb_host = sdb.amazonaws.com
skip_existing = False
socket_timeout = 300
urlencoding_mode = normal
use_https = ${USE_HTTPS}
use_mime_magic = True
use_path_mode = True
verbosity = WARNING
website_endpoint = http://%(bucket)s.s3-website-%(location)s.amazonaws.com/
website_error =
website_index = index.html
EOF

set -x

# Copy the deis db_wal bucket locally
mkdir -p "${DATABASE_BUCKET_NAME}/"
s3cmd -c "${DEIS_CONFIG_FILE}" sync "s3://${DATABASE_BUCKET_NAME}/" "${DATABASE_BUCKET_NAME}"/

# Copy the local db_wal bucket to AWS
s3cmd -c "${AWS_CONFIG_FILE}" sync "${DATABASE_BUCKET_NAME}"/ "s3://${AWS_BACKUP_BUCKET}/deis/"

# Copy the deis registry bucket locally
mkdir -p "${REGISTRY_BUCKET_NAME}/"
s3cmd -c "${DEIS_CONFIG_FILE}" sync "s3://${REGISTRY_BUCKET_NAME}/" "${REGISTRY_BUCKET_NAME}"/

# Copy the local registry bucket to AWS
s3cmd -c "${AWS_CONFIG_FILE}" sync "${REGISTRY_BUCKET_NAME}"/ "s3://${AWS_BACKUP_BUCKET}/deis/"