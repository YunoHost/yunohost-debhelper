#!/usr/bin/env bash
#==========================================================================
#
#   Copyright (c) 2015 Julien Malik (julien.malik@paraiso.me)
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#          http://www.apache.org/licenses/LICENSE-2.0.txt
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#==========================================================================*/

function get_this_dir {
  # inspired from http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
  local SOURCE="${BASH_SOURCE[0]}"
  
  # resolve $SOURCE until the file is no longer a symlink
  while [ -h "$SOURCE" ]; do 
    local DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    local SOURCE="$(readlink "$SOURCE")"
    # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  
  THIS_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
}

function usage {
  echo "Usage : $0 <version>"
  exit 1
}

function info {
  local Red='\033[0;31m'
  local Green='\033[0;32m'
  local ColorReset='\033[0m'
  echo -e "[${Green}info${ColorReset}] $1"
}

function error {
  local Red='\033[0;31m'
  local Green='\033[0;32m'
  local ColorReset='\033[0m'
  echo -e "[${Red}error${ColorReset}] $1"
}

function check_args {
  local ARGV=("$@")
  local ARGC=("$#")

  if [ "$ARGC" -ne 1 ]; then
    error "Wrong number of arguments"
    usage
  fi
  
  NEW_VERSION=$1
}

function check_tools_availability {
  # TODO version checking ?
  
  which git-dch > /dev/null || (error "You need to install git-dch (apt-get install git-buildpackage)"; exit 1)
  info "Checking for git-dch... ok"
  
  python -c 'import apt' > /dev/null || (error "You need to install python-apt (apt-get install python-apt)"; exit 1)
  info "Checking for python-apt... ok"

  which dpkg-parsechangelog > /dev/null || (error "You need to install dpkg-parsechangelog (apt-get install dpkg-dev)" ; exit 1)
  info "Checking for dpkg-parsechangelog... ok"
}

function check_yunobump_uptodate {
  get_this_dir
  info "yuno-debhelper : yunobump is located at $THIS_DIR"
  info "yuno-debhelper : Fetching $THIS_DIR remotes to see if it is up-to-date"

  pushd $THIS_DIR > /dev/null
  # cf http://stackoverflow.com/questions/3258243/git-check-if-pull-needed/
  info "Running 'git remote update'"
  git remote update
  local LOCAL=$(git rev-parse @{0})
  local REMOTE=$(git rev-parse @{u})
  local BASE=$(git merge-base @ @{u})

  if [ "$LOCAL" = "$REMOTE" ]; then
      info "yuno-debhelper : Up-to-date"
  elif [ "$LOCAL" = "$BASE" ]; then
      error "yuno-debhelper : Need to pull"
      # TODO : exit if we're here ?
  elif [ "$REMOTE" = "$BASE" ]; then
      error "yuno-debhelper : Need to push"
  else
      error "yuno-debhelper : Diverged"
  fi
  popd > /dev/null
}

function check_working_dir_clean {
  
  git rev-parse --is-inside-work-tree > /dev/null 2>&1
  if [ "$?" -eq "0" ]; then
    info "Checking that we are in a git work-tree... ok"
  else
    error "This is not a git work-tree... Are you lost ?"
    exit 1
  fi

  local git_status="`git status -unormal 2>&1`"
  if [[ "$git_status" =~ nothing\ to\ commit ]]; then
    # clean working dir
    info "Working dir is clean"
  else
    error "Working dir is not clean. aborting..."
    exit 1
  fi
  
  if [ ! -d "debian" ]; then
    error "There is no 'debian' subdir here. Are you lost ?"
    exit 1 
  fi
}

function check_branch {
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  info "Current branch is $BRANCH"
  if [ "$BRANCH" != "test" ] && [ "$BRANCH" != "stable" ]; then
    error "yunobump is meant to work with branch 'test' or 'stable' only"
    exit 1
  fi
}

function check_workingdir_uptodate {
  # cf http://stackoverflow.com/questions/3258243/git-check-if-pull-needed/
  info "Running 'git remote update'"
  git remote update
  local LOCAL=$(git rev-parse @{0})
  local REMOTE=$(git rev-parse @{u})
  local BASE=$(git merge-base @ @{u})

  if [ "$LOCAL" = "$REMOTE" ]; then
      info "local branch is up-to-date with remote tracking branch"
  elif [ "$LOCAL" = "$BASE" ]; then
      error "local branch is late. need to pull remote tracking branch"
      # TODO : add an option to override this ?
      exit 1
  elif [ "$REMOTE" = "$BASE" ]; then
      info "local branch is ahead of remote tracking branch. need to push"
  else
      error "local and remote branches diverged. check your history !"
      # TODO : add an option to override this ?
      exit 1
  fi
}

function check_version_validity {
  local LATEST_VERSION=$(dpkg-parsechangelog --format dpkg | grep "^Version:" | cut -d ' ' -f 2)
  info "Current changelog version is $LATEST_VERSION"
  info "Requesting bump to version $NEW_VERSION"

  # Check that requested new version > last version
  if [ $(python -c "import apt,sys; print int(apt.VersionCompare('$LATEST_VERSION', '$NEW_VERSION') >= 0)") -ne "0" ]; then
    error "Requested new version ($NEW_VERSION) is less than or equal to current changelog version ($LATEST_VERSION)"
    exit 1
  fi
  
  # Check that there is no existing tag with this version (for example from another branch)
  
}

function update_changelog {
  info "Running git-dch"
  git dch --new-version $NEW_VERSION --ignore-branch --release --distribution=test --force-distribution --urgency=low --git-author --spawn-editor=always --debian-tag="$BRANCH/%(version)s"
  if [ "$?" != 0 ] ; then
    error "Failed to update debian/changelog"
    exit 1
  fi

  info "Committing changelog"
  # TODO : ask confirmation before continuing ?
  git add debian/changelog
  git commit -m "Update changelog for $NEW_VERSION release"
  if [ "$?" != 0 ] ; then
    error "Failed to commit debian/changelog"
    exit 1
  fi

  info "Applying tag $BRANCH/$NEW_VERSION"
  git tag $BRANCH/$NEW_VERSION
  if [ "$?" != 0 ] ; then
    error "Failed to tag $NEW_VERSION"
    exit 1
  fi
}

function show_diff_to_push {
  local LOCAL=$(git rev-parse @{0})
  local REMOTE=$(git rev-parse @{u})
  
  info "The following commits need to be pushed :"
  git log --oneline --decorate $REMOTE..$LOCAL

  info "You can push them now with : \"git push --tags $(git config branch.$BRANCH.remote) $BRANCH:$BRANCH\""
}

check_args "$@"
check_tools_availability
check_working_dir_clean
check_yunobump_uptodate
check_branch
check_workingdir_uptodate
check_version_validity
update_changelog
show_diff_to_push
