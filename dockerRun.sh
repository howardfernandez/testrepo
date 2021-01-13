#!/usr/bin/env bash

set -e

show_help() {
    echo "Run jenkins docker image."
    echo "Options:"
    echo "  -h / -?:            Show this help"
    echo "  -d:                 Run container as daemon"
    echo "  -e local|test|prod: Run in local (docker), test, or prod environment"
}

OPTIND=1
DAEMON=0
while getopts "h?de:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    e)
        environment=$OPTARG
        ;;
    d)
        DAEMON=1
        ;;
    esac
done
shift $((OPTIND-1))

if [ -z "$environment" ]; then
    show_help
    exit 1
fi

if [ "$environment" == "local" ]; then
    export JENKINS_ROOT_URL="http://localhost:8080"
    export JENKINS_SERVER_ROLE="dev" #dev/test/prod
    export JENKINS_HOME="${HOME}/jenkins_home"
    # On local machine, use a tmp dir to simulate EFS
    export JENKINS_EFS="${HOME}/tmp/jenkins_efs"
    mkdir -p ${JENKINS_EFS}
    export JENKINS_IS_PROD="false"
    export JAVA_MEM_OPTS="-Xmx2g -Xms1g"
fi
if [ "$environment" == "test" ]; then
    export JENKINS_ROOT_URL="https://jenkins-test.ci.swift-nav.com"
    export JENKINS_SERVER_ROLE="test" #dev/test/prod
    export JENKINS_HOME="/mnt/jenkins_home"
    export JENKINS_EFS="/mnt/efs"
    export JENKINS_IS_PROD="false"
    export JAVA_MEM_OPTS="-Xmx4g -Xms2g"
fi
if [ "$environment" == "prod" ]; then
    export JENKINS_ROOT_URL="https://jenkins.ci.swift-nav.com"
    export JENKINS_SERVER_ROLE="prod" #dev/test/prod
    export JENKINS_HOME="/mnt/jenkins_home"
    export JENKINS_EFS="/mnt/efs"
    export JENKINS_IS_PROD="true"
    export JAVA_MEM_OPTS="-Xmx12g -Xms6g"
fi

[ ! -z "$JENKINS_ROOT_URL" ] || (echo "Environment $environment not supported."; exit 1)

export JENKINS_ADMIN_EMAIL="klaus@swift-nav.com"
export JENKINS_SLAVE_AGENT_PORT=50000

# Change the dir name separator for multiple workspaces from @ to _, since some
# build tools had issues with the '@' in a file path.
# Set heap size to 1/4 the actual RAM, and min heap size to half of that
# (see https://support.cloudbees.com/hc/en-us/articles/204859670-Java-Heap-settings-best-practice).
#
# See JENKINS-48300 for the durable task timeout.
export JAVA_OPTS="${JAVA_MEM_OPTS} -Dhudson.slaves.WorkspaceList=_ -Dorg.jenkinsci.plugins.durabletask.BourneShellScript.HEARTBEAT_CHECK_INTERVAL=86400"

echo -n "Check if AWS cli is installed - should be >= 1.15 - "
aws --version || (echo 'aws command not found; install aws-cli'; exit 1)
echo -n "Check if jq is installed - "
jq --version || (echo 'jq command not found; install via "brew install jq"'; exit 1)

REGION="--region us-west-2"
# Remember to add any new env var to docker-compose so that they get passed into container
export JENKINS_ADMIN_EMAIL="klaus@swift-nav.com"

mkdir -p ${JENKINS_HOME}/init.groovy.d/
#cp init/* ${JENKINS_HOME}/init.groovy.d/
cp ci/config/*.xml ${JENKINS_HOME}/

## Comment out while these are empty (used to include role-specific plugin configs)
#cp ci/config/${JENKINS_SERVER_ROLE}/*.xml ${JENKINS_HOME}/

chmod ugo+rwx ${JENKINS_HOME}/init.groovy.d

mkdir -p secrets
echo "931498312035-a62nus30e643eferrfu7k0noaqt2dlpc.apps.googleusercontent.com" > secrets/googleauthid.txt

case $environment in
  test)
    echo "3cn0brq32hrtu267pmqlb0vvcd" > secrets/aws_cognito_client_id.txt
    aws secretsmanager get-secret-value ${REGION} --secret-id aws-cognito-client-secret | jq -r .SecretString | jq -r .aws_cognito_client_secret > secrets/aws_cognito_client_secret.txt
    ;;
  prod)
    echo "o7s2rv5akjktj90hc7hgla30c" > secrets/aws_cognito_client_id.txt
    aws secretsmanager get-secret-value ${REGION} --secret-id aws-cognito-client-secret-prod | jq -r .SecretString | jq -r .aws_cognito_client_secret > secrets/aws_cognito_client_secret.txt
    ;;
  *)
    echo -n "unknown environment"
    ;;
esac


# Make script fail when we're not logged into aws
set -o pipefail
aws secretsmanager get-secret-value ${REGION} --secret-id googleauthclientsecret | jq -r .SecretString | jq -r .googleauthclientsecret > secrets/googleauthsecret.txt
aws secretsmanager get-secret-value ${REGION} --secret-id github-swiftnavsvcjenkins | jq -r .SecretString | jq -r .swiftnav_svc_jenkins  > secrets/githubaccesstoken.txt
aws secretsmanager get-secret-value ${REGION} --secret-id aws-ecr-access | jq -r .SecretString | jq -r .aws_ecr_access_key_id  > secrets/ecr_access_key_id.txt
aws secretsmanager get-secret-value ${REGION} --secret-id aws-ecr-access | jq -r .SecretString | jq -r .aws_ecr_secret_access_key  > secrets/ecr_secret_access_key.txt
aws secretsmanager get-secret-value ${REGION} --secret-id aws-travis-access | jq -r .SecretString | jq -r .aws_travis_access_key_id  > secrets/travis_access_key_id.txt
aws secretsmanager get-secret-value ${REGION} --secret-id aws-travis-access | jq -r .SecretString | jq -r .aws_travis_secret_access_key  > secrets/travis_secret_access_key.txt
aws secretsmanager get-secret-value ${REGION} --secret-id aws-flex-s3 | jq -r .SecretString | jq -r .aws_access_key_id  > secrets/flex_s3_access_key_id.txt
aws secretsmanager get-secret-value ${REGION} --secret-id aws-flex-s3 | jq -r .SecretString | jq -r .aws_secret_access_key  > secrets/flex_s3_secret_access_key.txt
aws secretsmanager get-secret-value ${REGION} --secret-id jenkins-node-key-1line | jq -r .SecretString | jq -r .private_key | tr '#' '\n' > secrets/jenkins_node_key.txt
aws secretsmanager get-secret-value ${REGION} --secret-id github-crl-key-1line | jq -r .SecretString | jq -r .privateKey | tr '#' '\n' > secrets/crl_github_ssh_key.txt
# Token to use in scripts like release.hs
aws secretsmanager get-secret-value ${REGION} --secret-id slack_token | jq -r .SecretString | jq -r .token > secrets/slack_token.txt
# Token to use for Jenkins/Slack integration
aws secretsmanager get-secret-value ${REGION} --secret-id slack_token | jq -r .SecretString | jq -r .token_jenkins > secrets/slack_jenkins_token.txt
# Secret string used for signature sent by Github webhooks
aws secretsmanager get-secret-value ${REGION} --secret-id github-webhook | jq -r .SecretString | jq -r .secret > secrets/github_webhook_trigger.txt
# Password for user 'ci' in Artifactory
aws secretsmanager get-secret-value ${REGION} --secret-id artifactory | jq -r .SecretString | jq -r .ci_password > secrets/artifactory_password.txt
# API key for Artifactory
aws secretsmanager get-secret-value ${REGION} --secret-id artifactory | jq -r .SecretString | jq -r .api_key > secrets/artifactory_api_key.txt
# Dockerhub login
aws secretsmanager get-secret-value ${REGION} --secret-id dockerhub | jq -r .SecretString | jq -r .swiftnav > secrets/dockerhub_password.txt

# File secrets need to be injected in base64.
aws secretsmanager get-secret-value ${REGION} --secret-id packer-ami-private-key | jq -r .SecretString | base64 > secrets/packer_ami_private_key.txt

# InfraDev PostgreSQL db passwords for terraform
aws secretsmanager get-secret-value ${REGION} --secret-id roost-db | jq -r .SecretString | jq -r .roost_db_pw_prod > secrets/roost_db_pw_prod.txt
aws secretsmanager get-secret-value ${REGION} --secret-id roost-db | jq -r .SecretString | jq -r .roost_db_pw_staging > secrets/roost_db_pw_staging.txt

# Github App
aws secretsmanager get-secret-value ${REGION} --secret-id github-app-swiftnav-test | jq -r .SecretString > secrets/github_app_swiftnav_jenkins_test.txt
aws secretsmanager get-secret-value ${REGION} --secret-id github-app-swiftnav | jq -r .SecretString > secrets/github_app_swiftnav_jenkins.txt

if [ $DAEMON -eq 1 ]; then
    docker-compose up -d
else
    docker-compose up
fi
