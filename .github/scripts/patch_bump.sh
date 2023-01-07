#!/bin/bash

set -e

SEMVER=$1
VERSION_FILE=$2

arrSEMVER=(${SEMVER//./ })
NEW_SEMVER="${arrSEMVER[0]}.${arrSEMVER[1]}.$((arrSEMVER[2]+1))"

echo "Updating ${VERSION_FILE} to ${NEW_SEMVER}"
sed -i "s/VERSION = '.*'/VERSION = '${NEW_SEMVER}'/" ${VERSION_FILE}

: ${COMMIT_PREFIX:="chore: "}
git commit -m "${COMMIT_PREFIX}patch-bump to ${NEW_SEMVER}" ${VERSION_FILE}

if [ -z "${GITHUB_USER_NAME} "]; then
  git config user.name "${GITHUB_USER_NAME}"
  git config user.email "<>"
fi
git push