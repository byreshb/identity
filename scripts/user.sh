#!/usr/bin/env bash
# Easy user on/off-boarding for the shared identity pool.
# Uses the default AWS profile. Pool id is read from terraform output, or pass POOL_ID.
#
# Usage:
#   scripts/user.sh invite  <email>                 # create user + email a temp password
#   scripts/user.sh grant   <email> <app>           # allow access to app (pulse|nudge|stowage)
#   scripts/user.sh revoke  <email> <app>           # remove access to an app
#   scripts/user.sh apps    <email>                 # list which apps a user can access
#   scripts/user.sh list                            # list all users
#   scripts/user.sh disable <email>                 # block sign-in (reversible)
#   scripts/user.sh enable  <email>                 # re-enable sign-in
#   scripts/user.sh delete  <email>                 # remove the user entirely
set -euo pipefail

POOL_ID="${POOL_ID:-$(terraform -chdir="$(dirname "$0")/../terraform" output -raw user_pool_id 2>/dev/null || true)}"
if [[ -z "${POOL_ID:-}" ]]; then
  echo "POOL_ID not set and 'terraform output user_pool_id' failed. Deploy the stack first, or export POOL_ID." >&2
  exit 1
fi

cmd="${1:-}"; shift || true
case "$cmd" in
  invite)
    email="$1"
    aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" --username "$email" \
      --user-attributes Name=email,Value="$email" Name=email_verified,Value=true \
      --desired-delivery-mediums EMAIL
    echo "Invited $email (temporary password emailed)."
    ;;
  grant)  aws cognito-idp admin-add-user-to-group      --user-pool-id "$POOL_ID" --username "$1" --group-name "app:$2"; echo "Granted $1 -> $2";;
  revoke) aws cognito-idp admin-remove-user-from-group --user-pool-id "$POOL_ID" --username "$1" --group-name "app:$2"; echo "Revoked $1 -> $2";;
  apps)   aws cognito-idp admin-list-groups-for-user   --user-pool-id "$POOL_ID" --username "$1" --query 'Groups[].GroupName' --output text;;
  list)   aws cognito-idp list-users                   --user-pool-id "$POOL_ID" --query 'Users[].Username' --output text;;
  disable) aws cognito-idp admin-disable-user          --user-pool-id "$POOL_ID" --username "$1"; echo "Disabled $1";;
  enable)  aws cognito-idp admin-enable-user           --user-pool-id "$POOL_ID" --username "$1"; echo "Enabled $1";;
  delete)  aws cognito-idp admin-delete-user           --user-pool-id "$POOL_ID" --username "$1"; echo "Deleted $1";;
  *) echo "Unknown command: '$cmd'. Run with no valid command to see usage above." >&2; sed -n '2,20p' "$0"; exit 1;;
esac
