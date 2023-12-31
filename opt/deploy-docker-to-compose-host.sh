#!/bin/bash

echo "[>] Starting deployment"

echo "  [+] Validating required environment variables"
if [[ -z "$DEPLOY_SSH_HOST" ]]; then
	echo "  [!] Missing the required $DEPLOY_SSH_HOST variable!"
	exit 1
fi

echo "  [+] Prepare environment variables..."
DEPLOY_DOCKER_DIR=${DEPLOY_DOCKER_DIR:-"/02_docker"}
DEPLOY_DOCKER_DIR=${DEPLOY_DOCKER_DIR%/}
DEPLOY_DOCKER_LOGIN_SCRIPT=${DEPLOY_DOCKER_LOGIN_SCRIPT:-"/opt/docker-login.sh"}
DEPLOY_PROJECT_ENV=${DEPLOY_PROJECT_ENV:-"prod"}
DEPLOY_PROJECT_NAME=${DEPLOY_PROJECT_NAME:-"${GITHUB_REPOSITORY}-${DEPLOY_PROJECT_ENV}"}
DEPLOY_SSH_USER=${DEPLOY_SSH_USER:-"deployment"}
DEPLOY_SSH_PORT=${DEPLOY_SSH_PORT:-"22"}
DEPLOY_SSH_FINGERPRINT=${DEPLOY_SSH_FINGERPRINT:-""}
DEPLOY_SSH_KEY=${DEPLOY_SSH_KEY:-""}
DEPLOY_ADDITIONAL_FILES=${DEPLOY_ADDITIONAL_FILES:-""}
DEPLOY_ARCHIVE_NAME=${DEPLOY_ARCHIVE_NAME:-"${GITHUB_SHA}.${GITHUB_RUN_ID}.zip"}
DEPLOY_SERVER_ENV_FILE=${DEPLOY_SERVER_ENV_FILE:-""}
DEPLOY_DOCKER_COMPOSE_OPTIONS=${DEPLOY_DOCKER_COMPOSE_OPTIONS:-""}
DEPLOY_SSH_USE_CLOUDFLARED=${DEPLOY_SSH_USE_CLOUDFLARED:-"false"}

echo "  [+] Applying defaults for github inputs..."
if [ $DEPLOY_PROJECT_NAME == '${GITHUB_REPOSITORY}/${project-env}' ]; then
  DEPLOY_PROJECT_NAME="$GITHUB_REPOSITORY-$DEPLOY_PROJECT_ENV"
fi
if [ $DEPLOY_ARCHIVE_NAME == '${GITHUB_SHA}.${GITHUB_RUN_ID}.zip' ]; then
  DEPLOY_ARCHIVE_NAME="${GITHUB_SHA}.${GITHUB_RUN_ID}.zip"
fi

# Create the .env file
echo "  [+] Creating .env file"
/opt/makeProdEnv.sh ${DEPLOY_PROJECT_ENV}

# Add required files to zip
echo "  [+] Packing zip"
zip "$DEPLOY_ARCHIVE_NAME" .env

if [ -f "docker-compose.${DEPLOY_PROJECT_ENV}.yml" ]; then
  rm -rf docker-compose.yml
  cp "docker-compose.${DEPLOY_PROJECT_ENV}.yml" docker-compose.yml
fi
if [ -f "docker-compose.yml" ]; then
  zip "$DEPLOY_ARCHIVE_NAME" docker-compose.yml
  else
    echo "  [!] Missing a docker-compose.yml file in the repository!"
    exit 1
fi

# Add additional files to the zip
if [ ! -z "${DEPLOY_ADDITIONAL_FILES}" ]; then
  for i in ${DEPLOY_ADDITIONAL_FILES//,/ }
  do
      zip "${DEPLOY_ARCHIVE_NAME}" "$i"
      echo "      -> $i"
  done
fi

mkdir -p $HOME/.ssh
chmod 700 $HOME/.ssh
mkdir -p ~/.ssh
chmod 700 ~/.ssh

SSH_OPTIONS=(-o "ConnectTimeout=10")
SCP_OPTIONS=(-o "ConnectTimeout=10")

# Creating cloudflared configuration
if [ "${DEPLOY_SSH_USE_CLOUDFLARED}" == "true" ]; then
  echo "  [+] Configuring SSH to use cloudflared tunnel..."
  SSH_OPTIONS+=( -o "ProxyCommand=cloudflared access ssh --hostname $DEPLOY_SSH_HOST" -o "StrictHostKeyChecking=no" )
  SCP_OPTIONS+=( -o "ProxyCommand=cloudflared access ssh --hostname $DEPLOY_SSH_HOST" -o "StrictHostKeyChecking=no" )
else
  SSH_OPTIONS+=(-p "$DEPLOY_SSH_PORT")
  SSH_OPTIONS+=(-P "$DEPLOY_SSH_PORT")
fi

if [ ! -z "${DEPLOY_SSH_FINGERPRINT}" ]; then
  echo "  [+] Will use provided ssh fingerprint..."
  echo ${DEPLOY_SSH_FINGERPRINT} >> $HOME/.ssh/known_hosts
  echo ${DEPLOY_SSH_FINGERPRINT} >> ~/.ssh/known_hosts
else
  if [ "${DEPLOY_SSH_USE_CLOUDFLARED}" != "true" ]; then
    echo "  [+] Gathering ssh fingerprint..."
    ssh-keyscan -p $DEPLOY_SSH_PORT $DEPLOY_SSH_HOST >> $HOME/.ssh/known_hosts
    ssh-keyscan -p $DEPLOY_SSH_PORT $DEPLOY_SSH_HOST >> ~/.ssh/known_hosts
  fi
fi

if [ ! -z "${DEPLOY_SSH_KEY}" ]; then
  echo "  [+] Will use provided ssh key (Note: The value MUST be base64 encoded!)..."
  (umask 077 ; echo ${DEPLOY_SSH_KEY} | base64 --decode > $HOME/.ssh/id_rsa_custom)
  SSH_OPTIONS+=( -i "$HOME/.ssh/id_rsa_custom" )
  SCP_OPTIONS+=( -i "$HOME/.ssh/id_rsa_custom" )
fi

SCRIPT_BEFORE="echo ''"

if [ ! -z "${DEPLOY_BEFORE_SCRIPT}" ]; then
  echo "  [+] Will run custom script before deployment..."
  SCRIPT_BEFORE="
  ${DEPLOY_BEFORE_SCRIPT}" || exit 1
fi

echo "  [+] Preparing deployment folder ($DEPLOY_SSH_USER) on $DEPLOY_SSH_HOST:$DEPLOY_SSH_PORT"
ssh "${SSH_OPTIONS[@]}" $DEPLOY_SSH_USER@$DEPLOY_SSH_HOST "
  mkdir -p $DEPLOY_DOCKER_DIR
  cd $DEPLOY_DOCKER_DIR
  if [ -d $DEPLOY_PROJECT_NAME ]; then
    cd $DEPLOY_PROJECT_NAME
    ${SCRIPT_BEFORE}
    cd ..
  fi
  rm -rf $DEPLOY_PROJECT_NAME
  mkdir -p $DEPLOY_PROJECT_NAME
"
if ! [ "$?" -eq "0" ]; then
	echo "  [!] Failed preparing deployment folder"
	exit 1
fi

echo "  [+] Copy archive to deployment folder"
scp "${SCP_OPTIONS[@]}" "$DEPLOY_ARCHIVE_NAME" $DEPLOY_SSH_USER@$DEPLOY_SSH_HOST:"$DEPLOY_DOCKER_DIR/$DEPLOY_PROJECT_NAME"
if ! [ "$?" -eq "0" ]; then
	echo "  [!] Failed to copy the archive"
	exit 1
fi

SCRIPT_BEFORE_LOGIN="echo ''"
SCRIPT_BEFORE_PULL="echo ''"
SCRIPT_AFTER_PULL="echo ''"
SCRIPT_AFTER_UP="echo ''"

if [ ! -z "$DEPLOY_SERVER_ENV_FILE" ]; then
  echo "  [+] Will attach contents of $DEPLOY_SERVER_ENV_FILE to $DEPLOY_DOCKER_DIR/$DEPLOY_PROJECT_NAME/.env..."
  SCRIPT_BEFORE_LOGIN="
cat $DEPLOY_SERVER_ENV_FILE >> $DEPLOY_DOCKER_DIR/$DEPLOY_PROJECT_NAME/.env" || exit 1
fi

if [ ! -z "${DEPLOY_BEFORE_LOGIN_SCRIPT}" ]; then
  echo "  [+] Will run custom script before login..."
  SCRIPT_BEFORE_LOGIN="
  $SCRIPT_BEFORE_LOGIN
  ${DEPLOY_BEFORE_LOGIN_SCRIPT}" || exit 1
fi

if [ ! -z "${DEPLOY_BEFORE_PULL_SCRIPT}" ]; then
  echo "  [+] Will run custom script before pull..."
  SCRIPT_BEFORE_PULL="
  ${DEPLOY_BEFORE_PULL_SCRIPT}" || exit 1
fi

if [ ! -z "${DEPLOY_AFTER_PULL_SCRIPT}" ]; then
  echo "  [+] Will run custom script after pull..."
  SCRIPT_AFTER_PULL="
  ${DEPLOY_AFTER_PULL_SCRIPT}" || exit 1
fi

if [ ! -z "${DEPLOY_AFTER_SCRIPT}" ]; then
  echo "  [+] Will run custom script after up..."
  SCRIPT_AFTER_UP="
  ${DEPLOY_AFTER_SCRIPT}" || exit 1
fi

if [ ! -z "$DEPLOY_DOCKER_COMPOSE_OPTIONS" ]; then
  echo "  [+] Will use custom docker-compose options: $DEPLOY_DOCKER_COMPOSE_OPTIONS"
  $DEPLOY_DOCKER_COMPOSE_OPTIONS = " $DEPLOY_DOCKER_COMPOSE_OPTIONS"
fi

echo "  [+] Unpacking and pulling deployment"
ssh "${SSH_OPTIONS[@]}" $DEPLOY_SSH_USER@$DEPLOY_SSH_HOST "
  cd $DEPLOY_DOCKER_DIR/$DEPLOY_PROJECT_NAME || exit 1
  unzip -o $DEPLOY_ARCHIVE_NAME || exit 1
  rm -rf $DEPLOY_ARCHIVE_NAME || exit 1
  ${SCRIPT_BEFORE_LOGIN}
  (test -x $DEPLOY_DOCKER_LOGIN_SCRIPT && $DEPLOY_DOCKER_LOGIN_SCRIPT)
  ${SCRIPT_BEFORE_PULL}
  docker-compose${DEPLOY_DOCKER_COMPOSE_OPTIONS} pull || exit 1
  ${SCRIPT_AFTER_PULL}
  docker-compose${DEPLOY_DOCKER_COMPOSE_OPTIONS} up -d || exit 1
  ${SCRIPT_AFTER_UP}
"
ECD=$?
if ! [ "$ECD" -eq "0" ]; then
	echo "  [!] Failed to unpack, pull or deploy"
	exit 1
fi

echo "[>] Deployment done."
