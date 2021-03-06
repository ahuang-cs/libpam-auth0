#!/bin/bash --noprofile

# NOTE: this script is for demonetisation only. vulnerable to script injection. use `pam.js` instead

declare log_file="${LOG_FILE:-/var/log/auth0-pam.sh.log}"

exec &> >(tee -a "${log_file}")
set -e
set -u
set -f
set -o pipefail

#set -x

## see `/_pam_types.h`
declare -r -i PAM_SUCCESS=0
declare -r -i PAM_SERVICE_ERR=3
declare -r -i PAM_SYSTEM_ERR=4
declare -r -i PAM_AUTH_ERR=7
declare -r -i PAM_AUTHINFO_UNAVAIL=9
declare -r -i PAM_NO_MODULE_DATA=18

declare -r config_file="${CONFIG_FILE:-/etc/auth0.conf}"

declare -i CONNECTION_TIMEOUT=50
declare -i MAX_TIMEOUT=60
declare DEBUG='1'

function error() {
    echo "ERROR: $(date) ${1}" && exit ${2}
}

function debug() {
    echo "DEBUG: $(date) ${1}"
}

### check PAM type
[[ -z ${PAM_TYPE+x} ]] && error "undefined PAM_TYPE" ${PAM_SYSTEM_ERR}
#debug "PAM_TYPE: ${PAM_TYPE}"

[[ ${PAM_TYPE} == "account" || ${PAM_TYPE} == "session" ]] &&  exit ${PAM_SUCCESS}
[[ ${PAM_TYPE} != "auth" ]] && error "PAM_TYPE not supported: ${PAM_TYPE}" ${PAM_SERVICE_ERR}

[[ -z ${PAM_USER+x} ]] && error "undefined PAM_USER" ${PAM_SYSTEM_ERR}
[[ ${PAM_USER} == "" ]] && error "empty PAM_USER." ${PAM_NO_MODULE_DATA}

# The password comes in through stdin
read PAM_PASSWORD || true
[[ -z ${PAM_PASSWORD+x} ]] && error "empty password. missing expose_authto." ${PAM_NO_MODULE_DATA}
#debug "User: ${PAM_USER@Q}; Type: ${PAM_TYPE}"

### load config
[[ ! -f ${config_file} ]] && error "config file missing: ${config_file}" ${PAM_SERVICE_ERR}
source ${config_file}

[[ -z ${AUTH0_DOMAIN+x} ]] && error "AUTH0_DOMAIN undefined" ${PAM_SERVICE_ERR}
[[ -z ${AUTH0_CLIENT_ID+x} ]] && error "AUTH0_CLIENT_ID undefined" ${PAM_SERVICE_ERR}

declare grant_type='password'
declare realm=''

[[ -n "${AUTH0_CONNECTION+x}" ]] && {
    grant_type='http://auth0.com/oauth/grant-type/password-realm';
    realm="\"realm\": \"${AUTH0_CONNECTION}\","
}

[[ -n "${AUTH0_CLIENT_SECRET}" ]] && secret="\"client_secret\": \"${AUTH0_CLIENT_SECRET}\","

declare -i -r http_code=$(
    printf "{\"grant_type\":\"%s\",%s\"client_id\":\"%s\",%s\"username\":\"%s\",\"scope\":\"none\",\"password\":\"%s\"}" \
    "${grant_type}" "${realm:- }" "${AUTH0_CLIENT_ID}" "${secret:- }" "${PAM_USER}" "${PAM_PASSWORD}" | \
    /usr/bin/curl -s -o /dev/null -w "%{http_code}" -X POST -H 'content-type: application/json' \
        -m ${MAX_TIMEOUT} \
        --connect-timeout ${CONNECTION_TIMEOUT} \
        --url https://${AUTH0_DOMAIN}/oauth/token \
        -d @-)

[[ -z ${http_code+x} ]] && error "undefined http_code" ${PAM_SYSTEM_ERR}

debug "domain: ${AUTH0_DOMAIN}, user: ${PAM_USER}, http_code: ${http_code}"

[[ ${http_code} == 200 ]] && exit ${PAM_SUCCESS}
[[ ${http_code} -gt 200 &&  ${http_code} -lt 500 ]] && exit ${PAM_AUTH_ERR}
[[ ${http_code} -ge 500 ]] && exit ${PAM_SYSTEM_ERR}

## todo: handle MFA

exit ${PAM_SYSTEM_ERR}
