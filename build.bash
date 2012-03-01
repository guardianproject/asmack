#!/bin/bash

DEPS="ant git javac patch svn tar"

echo "## Step 00: initialize"
(
  if ! [ -d build ]; then
    mkdir build
    mkdir build/src
    mkdir build/src/trunk
  fi
)

command_exists () {
  type -P "$1" &>/dev/null || { echo "!!! Missing dependency "$1"" >&2; exit 1; }
}

checkdeps() {
  for cmd in $DEPS ; do
    command_exists ${cmd} ;
  done
}

makesum() {
  find . -name .git -prune -o -name .svn -prune -o -type f -print0 | sort -z | xargs -0 -n 10 sha256sum > ../sums-${1}
  cd ..
  if [ -z "$GET_TIP" ]; then
    if [ -n "${sums[${1}]}" ]; then
      echo "${sums[${1}]}  sums-${1}" | sha256sum -c
    else
      echo "no sum for ${1}"
    fi
  fi
  sha256sum sums-${1} > sum-${1}
}

svnfetch() {
(
  cd src
  if ! [ -f "${2}/.svn/entries" ]; then
    mkdir "${2}"
    cd "${2}"
    svn co --non-interactive --trust-server-cert "${1}" "."
  else
    cd "${2}"
    svn cleanup
  fi
  if [ -z "$GET_TIP" -a -n "${revs[${2}]}" ]; then
    svn update -r "${revs[${2}]}"
  else
    svn update
  fi
  revision=`svn info | grep '^Revision:' | cut -f2 -d' '`
  makesum ${2}
  read sum ignore < sum-${2}
  rm sum-${2}
  echo "${2} $revision $sum" >> ../build-revs.new
)
}

gitfetch() {
(
  cd src
  if ! [ -f "${2}/.git/config" ]; then
    git clone "${1}" "${2}"
  else
    cd "${2}"
    git fetch
  fi

  if [ -z "$GET_TIP" -a -n "${revs[${2}]}" ]; then
    git checkout -q "${revs[${2}]}"
  else
    git checkout master
  fi
  revision=`git show --pretty=format:%H`
  makesum ${2}
  read sum ignore < sum-${2}
  rm sum-${2}
  echo "${2} $revision $sum" >> ../build-revs.new
)
}

fetchall() {
  echo -n > build-revs.new
#  gitfetch "git://github.com/rtreffer/smack.git" "smack"
  svnfetch "http://svn.igniterealtime.org/svn/repos/smack/trunk" "smack"
  svnfetch "http://svn.apache.org/repos/asf/qpid/trunk/qpid/java/management/common/src/main/" "qpid"
  svnfetch "http://svn.apache.org/repos/asf/harmony/enhanced/java/trunk/classlib/modules/auth/src/main/java/common/" "harmony"
  svnfetch "https://dnsjava.svn.sourceforge.net/svnroot/dnsjava/trunk" "dnsjava"
#  svnfetch "https://kenai.com/svn/jbosh~main/trunk/jbosh/src/main/java" "jbosh"
  gitfetch "git://kenai.com/jbosh~origin" "jbosh"
}

readrevs() {
  while read repo revision hash; do
    revs[$repo]=$revision
    sums[$repo]=$hash
  done < build-revs
}

copyfolder() {
(
  (
    cd "${1}"
    tar -cSsp --exclude-vcs "${3}"
  ) | (
    cd "${2}"
    tar -xSsp
  )
)
}

buildsrc() {
  echo "## Step 20: creating build/src"
  rm -rf build/src
  mkdir build/src
  mkdir build/src/trunk
  copyfolder "src/smack/source/" "build/src/trunk" "."
  copyfolder "src/qpid/java" "build/src/trunk" "org/apache/qpid/management/common/sasl"
  copyfolder "src/novell-openldap-jldap" "build/src/trunk" "."
  copyfolder "src/dnsjava"  "build/src/trunk" "org"
  copyfolder "src/harmony" "build/src/trunk" "."
  copyfolder "src/custom" "build/src/trunk" "."
  copyfolder "src/jbosh/src/main/java" "build/src/trunk" "."
}

patchsrc() {
  echo "## Step 21: patch build/src"
  (
    cd build/src/trunk/
    for PATCH in `(cd "../../../${1}" ; find -maxdepth 1 -type f)|sort` ; do
      if echo $PATCH | grep '\.sh$'; then
        if [ -f "../../../${1}/$PATCH" ]; then "../../../${1}/$PATCH" || exit 1 ; fi
      fi
      if echo $PATCH | grep '\.patch$'; then
        if [ -f "../../../${1}/$PATCH" ]; then patch -p0 < "../../../${1}/$PATCH" || exit 1 ; fi
      fi
    done
  )
}

build() {
  echo "## Step 30: compile"
  ant -Dbuild.all=true
}

buildcustom() {
  for dir in `find patch -maxdepth 1 -mindepth 1 -type d`; do
    buildsrc
    patchsrc "patch"
    patchsrc "${dir}"
    ant -Djar.suffix=`echo ${dir}|sed 's:patch/:-:'`
  done
}

usage() {
  echo "$0 [-t] [-f]"
  echo "   -t: use the tip of each pulled repository instead of the revisions specified in build-revs"
  echo "   -f: skip repository fetch"

  exit 1;
}

declare -A sums
declare -A revs

while getopts "tf" options; do
  case $options in
    t  ) GET_TIP="yes"; shift;;

    f  ) SKIP_FETCH="yes"; shift;;

    \? ) usage;;

    *  ) usage;;
  esac
done

if [ $# -ne 0 ]; then 
  usage
fi

readrevs
checkdeps
if [ -z "$SKIP_FETCH" ]; then
  fetchall
fi
buildsrc
patchsrc "patch"
build
buildcustom

if which advzip; then
  find build/*.jar -exec advzip -z4 '{}' ';'
  find build/*.zip -exec advzip -z4 '{}' ';'
fi
