#!/bin/bash

BRANCH=$(git rev-parse --abbrev-ref HEAD)
REGEX="^(main|dev|(wip|feat|tests|(bug|hot)fix)(\/[a-zA-Z0-9]+([-_][a-zA-Z0-9]+)*){1,2}|release\/[0-9]+(\.[0-9]+)*(-(alpha|beta|rc)[0-9]*)?)$"

if ! [[ $BRANCH =~ $REGEX ]]; then
  echo "Your commit was rejected due to branching name"
  echo "Please rename your branch with $REGEX syntax"
  exit 1
fi
