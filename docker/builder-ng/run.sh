#!/bin/bash -e

# Break taken between runs, in seconds.
DOCKER_BUILD_PAUSE=${DOCKER_BUILD_PAUSE:-300}

# A timeout is only needed for unattended builds, so we set this
# here instead of forcing it on everyone in the Makefile or even
# by giving the lisp variable a non-nil default value.
LISP_CONFIG="(setq package-build-timeout-secs 600)"

MELPA_REPO=/mnt/store/melpa
cd "${MELPA_REPO}"

BUILD_STATUS_FILE="${MELPA_REPO}/html/build-status.json"

export INSIDE_DOCKER=true

git config --global safe.directory "*"

if [ -z "$INHIBIT_MELPA_PULL" ]
then
    echo ">>> Pulling MELPA repository"
    MELPA_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    git fetch origin
    git reset --hard "origin/${MELPA_BRANCH}"
    git pull origin "${MELPA_BRANCH}"
    echo
fi

record_build_status() {
    echo "Recording build status in $BUILD_STATUS_FILE"
    cat <<EOF | tee $BUILD_STATUS_FILE
{
  "started": $BUILD_STARTED,
  "completed": ${BUILD_COMPLETED-null},
  "duration": ${BUILD_DURATION-null},
  "next": ${BUILD_NEXT-null}
}
EOF
}

function build_all {
    local pkgdir
    pkgdir=$(make get-pkgdir)
    [ -e "$pkgdir/errors.log" ] &&
        mv "$pkgdir/errors.log" "$pkgdir/errors-previous.log"
    export LANG=en_US.UTF-8
    make -k -j8 build || true
    make archive-contents json
}

# Indicate that the build is in progress
BUILD_DURATION=$(jq ".duration" ${BUILD_STATUS_FILE} || true)
BUILD_STARTED=$(date "+%s")
record_build_status

# echo ">>> Starting UNSTABLE build"
# export MELPA_CHANNEL=unstable
# export BUILD_CONFIG="$LISP_CONFIG"
# build_all

# echo ">>> Starting STABLE build"
# export MELPA_CHANNEL=stable
# export BUILD_CONFIG="(progn $LISP_CONFIG\
#   (setq package-build-fetch-function 'ignore))"
# build_all

echo ">>> Starting SNAPSHOT build"
export MELPA_CHANNEL=snapshot
export BUILD_CONFIG="(progn $LISP_CONFIG\
  (setq package-build-fetch-function 'ignore))"
build_all

echo ">>> Starting RELEASE build"
export MELPA_CHANNEL=release
export BUILD_CONFIG="(progn $LISP_CONFIG\
  (setq package-build-fetch-function 'ignore))"
build_all

# Indicate that the build has completed
BUILD_COMPLETED=$(date "+%s")
BUILD_DURATION=$((BUILD_COMPLETED - BUILD_STARTED))
BUILD_NEXT=$((BUILD_COMPLETED + DOCKER_BUILD_PAUSE))
record_build_status

if [ ! "$DOCKER_BUILD_PAUSE" = 0 ]
then
    echo "Sleeping for $DOCKER_BUILD_PAUSE seconds before next build"
    sleep $DOCKER_BUILD_PAUSE
fi
