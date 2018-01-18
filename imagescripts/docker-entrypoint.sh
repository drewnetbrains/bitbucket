#!/bin/bash
#
# A helper script for ENTRYPOINT.
#
# If first CMD argument is 'bitbucket', then the script will start bitbucket
# If CMD argument is overriden and not 'bitbucket', then the user wants to run
# his own process.

set -e

[[ ${DEBUG} == true ]] && set -x

function updateBitbucketProperties() {
  local propertyfile=$1
  local propertyname=$2
  local propertyvalue=$3
  set +e
  grep -q "${propertyname}=" ${propertyfile}
  if [ $? -eq 0 ]; then
    set -e
    if [[ $propertyvalue == /* ]]; then
      sed -i "s/\(${propertyname/./\\.}=\).*\$/\1\\${propertyvalue}/" ${propertyfile}
    else
      sed -i "s/\(${propertyname/./\\.}=\).*\$/\1${propertyvalue}/" ${propertyfile}
    fi
  else
    set -e
    echo "${propertyname}=${propertyvalue}" >> ${propertyfile}
  fi
}

function processBitbucketProxySettings() {
  if [ -n "${BITBUCKET_CONTEXT_PATH}" ] || [ -n "${BITBUCKET_PROXY_NAME}" ] || [ -n "${BITBUCKET_PROXY_PORT}" ] || [ -n "${BITBUCKET_DELAYED_START}" ] || [ -n "${BITBUCKET_CROWD_SSO}" ] ; then
    if [ ! -f ${BITBUCKET_HOME}/bitbucket.properties ]; then
      touch ${BITBUCKET_HOME}/bitbucket.properties
    fi
  fi

  if [ -n "${BITBUCKET_CONTEXT_PATH}" ]; then
    updateBitbucketProperties ${BITBUCKET_HOME}/bitbucket.properties "server.context-path" ${BITBUCKET_CONTEXT_PATH}
  fi

  if [ -n "${BITBUCKET_PROXY_NAME}" ]; then
    updateBitbucketProperties ${BITBUCKET_HOME}/bitbucket.properties "server.proxy-name" ${BITBUCKET_PROXY_NAME}
  fi

  if [ -n "${BITBUCKET_PROXY_PORT}" ]; then
    updateBitbucketProperties ${BITBUCKET_HOME}/bitbucket.properties "server.proxy-port" ${BITBUCKET_PROXY_PORT}
  fi

  if [ -n "${BITBUCKET_PROXY_SCHEME}" ]; then
    if [ "${BITBUCKET_PROXY_SCHEME}" = 'https' ]; then
      local secure="true"
      updateBitbucketProperties ${BITBUCKET_HOME}/bitbucket.properties "server.secure" ${secure}
      updateBitbucketProperties ${BITBUCKET_HOME}/bitbucket.properties "server.scheme" ${BITBUCKET_PROXY_SCHEME}
    else
      local secure="false"
      updateBitbucketProperties ${BITBUCKET_HOME}/bitbucket.properties "server.secure" ${secure}
      updateBitbucketProperties ${BITBUCKET_HOME}/bitbucket.properties "server.scheme" ${BITBUCKET_PROXY_SCHEME}
    fi
  fi

  if [ -n "${BITBUCKET_CROWD_SSO}" ] ; then
    updateBitbucketProperties ${BITBUCKET_HOME}/bitbucket.properties "plugin.auth-crowd.sso.enabled" ${BITBUCKET_CROWD_SSO}
  fi
}

if [ -n "${BITBUCKET_DELAYED_START}" ]; then
  sleep ${BITBUCKET_DELAYED_START}
fi

# Download Atlassian required config files from s3
/usr/bin/aws s3 cp s3://fathom-atlassian-ecs/BITBUCKET/${BITBUCKET_CONFIG} ${BITBUCKET_HOME}
/usr/bin/tar -xzf ${BITBUCKET_CONFIG} -C ${BITBUCKET_HOME}

# Pull Atlassian secrets from parameter store
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWSREGION=${AZ::-1}

DATABASE_ENDPOINT=$(aws ssm get-parameters --names "${ENVIRONMENT}.atlassian.rds.db_host" --region ${AWSREGION} --with-decryption --query Parameters[0].Value --output text)
DATABASE_USER=$(aws ssm get-parameters --names "${ENVIRONMENT}.atlassian.rds.db_user" --region ${AWSREGION} --with-decryption --query Parameters[0].Value --output text)
DATABASE_PASSWORD=$(aws ssm get-parameters --names "${ENVIRONMENT}.atlassian.rds.password" --region ${AWSREGION} --with-decryption --query Parameters[0].Value --output text)
DATABASE_NAME=${DATABASE_NAME}

/bin/sed -i -e "s/DATABASE_ENDPOINT/$DATABASE_ENDPOINT/" \
            -e "s/DATABASE_USER/$DATABASE_USER/" \
            -e "s/DATABASE_PASSWORD/$DATABASE_PASSWORD/" \
            -e "s/DATABASE_NAME/$DATABASE_NAME/" shared/bitbucket.properties

/bin/rm -rf ${BITBUCKET_CONFIG}
# End of aws section

processBitbucketProxySettings

# If there is a 'ssh' directory, copy it to /home/bitbucket/.ssh
if [ -d /var/atlassian/bitbucket/ssh ]; then
  mkdir -p /home/bitbucket/.ssh
  cp -R /var/atlassian/bitbucket/ssh/* /home/bitbucket/.ssh
  chmod -R 700 /home/bitbucket/.ssh
fi

if [ "$1" = 'bitbucket' ] || [ "${1:0:1}" = '-' ]; then
  umask 0027
  exec ${BITBUCKET_INSTALL}/bin/start-bitbucket.sh --no-search -fg
else
  exec "$@"
fi
