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

# Check python is installed
if ! type_exists 'python2.7'; then
  error "Please install python 2.7"
  exit 1
fi

# Check pip is installed
if ! type_exists 'pip'; then
  curl --silent --show-error --retry 5 https://bootstrap.pypa.io/get-pip.py | sudo python2.7
fi

# Install python dependencies
INSTALL_DEPENDENCIES=$(pip install --upgrade boto3 2>&1)
if [ $? -ne 0 ]; then
  error "Unable to install dependencies"
  warn "$INSTALL_DEPENDENCIES"
  exit 1
fi

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


python main.py \
  --key "$WERCKER_AWS_ECS_KEY" \
  --secret "$WERCKER_AWS_ECS_SECRET" \
  --region "${WERCKER_AWS_ECS_REGION:-us-east-1}" \
  --cluster-name "$WERCKER_AWS_ECS_CLUSTER_NAME" \
  --service-name "$WERCKER_AWS_ECS_SERVICE_NAME" \
  --task-definition-name "$WERCKER_AWS_ECS_TASK_DEFINITION_NAME" \
  --task-definition-file "$WERCKER_AWS_ECS_TASK_DEFINITION_FILE"
