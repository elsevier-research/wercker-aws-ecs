#!/bin/bash
set +e
set -o noglob


#
# Set Colors
#

bold=$(tput bold)
underline=$(tput sgr 0 1)
reset=$(tput sgr0)

red=$(tput setaf 1)
green=$(tput setaf 76)
white=$(tput setaf 7)
tan=$(tput setaf 202)
blue=$(tput setaf 25)

#
# Headers and Logging
#

underline() { printf "${underline}${bold}%s${reset}\n" "$@"
}
h1() { printf "\n${underline}${bold}${blue}%s${reset}\n" "$@"
}
h2() { printf "\n${underline}${bold}${white}%s${reset}\n" "$@"
}
debug() { printf "${white}%s${reset}\n" "$@"
}
info() { printf "${white}➜ %s${reset}\n" "$@"
}
success() { printf "${green}✔ %s${reset}\n" "$@"
}
error() { printf "${red}✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}➜ %s${reset}\n" "$@"
}
bold() { printf "${bold}%s${reset}\n" "$@"
}
note() { printf "\n${underline}${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$@"
}


type_exists() {
  if [ $(type -P $1) ]; then
    return 0
  fi
  return 1
}

jsonValue() {
  key=$1
  num=$2
  awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$key'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}


# Check variables
if [ -z "$WERCKER_AWS_ECS_KEY" ]; then
  error "Please set the 'key' variable"
  exit 1
fi

if [ -z "$WERCKER_AWS_ECS_SECRET" ]; then
  error "Please set the 'secret' variable"
  exit 1
fi

if [ -z "$WERCKER_AWS_ECS_CLUSTER_NAME" ]; then
  error "Please set the 'cluster-name' variable"
  exit 1
fi

if [ -z "$WERCKER_AWS_ECS_SERVICE_NAME" ]; then
  error "Please set the 'service-name' variable"
  exit 1
fi

if [ -z "$WERCKER_AWS_ECS_TASK_DEFINITION_NAME" ]; then
  error "Please set the 'task-definition-name' variable"
  exit 1
fi

if [ -z "$WERCKER_AWS_ECS_TASK_DEFINITION_FILE" ]; then
  error "Please set the 'task-definition-file' variable"
  exit 1
fi

# ----- Install AWS Cli -----
# see documentation http://docs.aws.amazon.com/cli/latest/userguide/installing.html
# ---------------------------

# Check AWS is installed
if ! type_exists 'aws'; then
  h1 "Installing AWS CLI"
  INSTALL_AWSCLI="sudo pip install awscli"
  info "$INSTALL_AWSCLI"
  INSTALL_AWSCLI_OUTPUT=$($INSTALL_AWSCLI 2>&1)
  if [ $? -ne 0 ]; then
    warn "$INSTALL_AWSCLI_OUTPUT"
    exit 1
  fi
  success "Installing AWS CLI (`aws --version`) succeeded"
fi

# ----- Install jq -----
# see documentation http://docs.aws.amazon.com/cli/latest/userguide/installing.html
# ---------------------------

# Check jq is installed
if ! type_exists 'jq'; then
  h1 "Installing jq"
  INSTALL_JQ="sudo apt-get install -y jq"
  info "$INSTALL_JQ"
  INSTALL_JQ_OUTPUT=$($INSTALL_JQ 2>&1)
  if [ $? -ne 0 ]; then
    warn "$INSTALL_JQ_OUTPUT"
    exit 1
  fi
  success "Installing jq (`jq --version`) succeeded"
fi

# ----- Configure -----
# see documentation
#    http://docs.aws.amazon.com/cli/latest/reference/configure/index.html
# ----------------------
set -e

h1 "Step 1: Configuring AWS"

h2 "Configuring AWS Access Key ID"
CONFIGURE_KEY_OUTPUT=$(aws configure set aws_access_key_id $WERCKER_AWS_ECS_KEY 2>&1)
success "Configuring AWS Access Key ID succeeded"

h2 "Configuring AWS Secret Access Key"
CONFIGURE_SECRET_OUTPUT=$(aws configure set aws_secret_access_key $WERCKER_AWS_ECS_SECRET 2>&1)
success "Configuring AWS Secret Access Key succeeded"

if [ -n "$WERCKER_AWS_ECS_REGION" ]; then
  h2 "Configuring AWS default region"
  CONFIGURE_REGION_OUTPUT=$(aws configure set default.region $WERCKER_AWS_ECS_REGION 2>&1)
  success "Configuring AWS default region succeeded"
fi

set +e

# ----- AWS ECS CLI -----
# see documentation
#    http://docs.aws.amazon.com/cli/latest/reference/ecs/index.html
# ----------------------

h1 "Step 2: Check ECS Cluster"
h2 "Checking ECS cluster '$WERCKER_AWS_ECS_CLUSTER_NAME' exists"

CLUSTER_EXISTS="aws ecs describe-clusters --clusters $WERCKER_AWS_ECS_CLUSTER_NAME"
info "$CLUSTER_EXISTS"
CLUSTER_EXISTS_OUTPUT=$($CLUSTER_EXISTS 2>&1)

CLUSTER_EXISTS_GREP="echo $CLUSTER_EXISTS_OUTPUT | grep MISSING"
info "$CLUSTER_EXISTS_GREP"
CLUSTER_EXISTS_GREP_OUTPUT=$($CLUSTER_EXISTS_GREP 2>&1)

if [ $? -eq 0 ]; then
  error "Cluster '$WERCKER_AWS_ECS_CLUSTER_NAME' missing"
  exit 1

h1 "Step 3: Check ECS Service"
h2 "Checking ECS service '$WERCKER_AWS_ECS_SERVICE_NAME' exists"

SERVICE_EXISTS="aws ecs describe-services --cluster $WERCKER_AWS_ECS_CLUSTER_NAME --services $WERCKER_AWS_ECS_SERVICE_NAME"
info "$SERVICE_EXISTS"
SERVICE_EXISTS_OUTPUT=$($SERVICE_EXISTS 2>&1)

SERVICE_EXISTS_GREP="echo $SERVICE_EXISTS_OUTPUT | grep MISSING"
info "$SERVICE_EXISTS_GREP"
SERVICE_EXISTS_GREP_OUTPUT=$($SERVICE_EXISTS_GREP 2>&1)

if [ $? -eq 0 ]; then
  info "Service '$WERCKER_AWS_ECS_SERVICE_NAME' missing"
  exit 1

h1 "Step 4: Create New Task Definition Revision"
h2 "Creating ECS task definition revision"

REGISTER_TASK_DEFINITION="aws ecs register-task-definition --family $WERCKER_AWS_ECS_TASK_DEFINITION_NAME --cli-input-json file://$WERCKER_AWS_ECS_TASK_DEFINITION_FILE"
info "$REGISTER_TASK_DEFINITION"
REGISTER_TASK_DEFINITION_OUTPUT=$($REGISTER_TASK_DEFINITION 2>&1)

h1 "Step 5: Scale Down ECS Service"
h2 "Scaling down ECS service"

SERVICE_COUNT_OUTPUT=$($SERVICE_EXISTS | jq '.services[0].desiredCount')
SERVICE_DESIRED_COUNT=$(($SERVICE_COUNT_OUTPUT-1))
UPDATE_SERVICE_COUNT="aws ecs update-service --cluster $WERCKER_AWS_ECS_CLUSTER_NAME --service $WERCKER_AWS_ECS_SERVICE_NAME --desired-count $SERVICE_DESIRED_COUNT"
info "$UPDATE_SERVICE_COUNT"
UPDATE_SERVICE_COUNT_OUTPUT=$($UPDATE_SERVICE_COUNT 2>&1)

h1 "Step 6: Update ECS Service"
h2 "Updating ECS service"

UPDATE_SERVICE_TASK_DEFINITION="aws ecs update-service --cluster $WERCKER_AWS_ECS_CLUSTER_NAME --service $WERCKER_AWS_ECS_SERVICE_NAME --task-definition $WERCKER_AWS_ECS_TASK_DEFINITION_NAME"
info "$UPDATE_SERVICE_TASK_DEFINITION"
UPDATE_SERVICE_TASK_DEFINITION_OUTPUT=$($UPDATE_SERVICE_TASK_DEFINITION 2>&1)

set -e
