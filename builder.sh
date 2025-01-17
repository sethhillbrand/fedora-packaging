#!/bin/sh

set -e
set -x

# Clone or fetch updates for one git repo.
get_one () {
	local WHAT="$1"
	local WHERE="$2"
	local TAG="$3"

	if [ -d "build/${WHAT}" ]; then
		(
		cd "build/${WHAT}"
		git fetch origin
		git reset --hard origin/master
		git checkout "${TAG}" || git checkout HEAD
		)
	else 
		(
		cd build
		git clone "${WHERE}/${WHAT}"
		cd "${WHAT}"
		git checkout "${TAG}" || git checkout HEAD
		)
	fi
}

# Get the number of revisions in a repo.  A nice sequential number.
get_rev_count () {
	(
	cd "$1"
	printf "r%s" "$(git rev-list --count HEAD)"
	)
}

# Get the SHA of the HEAD commit in a repo.
get_last_rev () {
	(
	cd "$1"
	printf "%s" "$(git rev-parse --short=8 HEAD)"
	)
}

# Create a tar-ball from a specific commit in a repo.
make_tar () {
	local WHAT="$1"
	local FULL_VERSION="$2"
	local TAG="$3"
	(
	cd "build/${WHAT}"
	set +x
	echo "Creating ${WHAT}-${FULL_VERSION}.tar.gz from ${TAG}..."
	set -x
	git archive --format=tar.gz --prefix="${WHAT}-${FULL_VERSION}/" "${TAG}" > \
		"../rpmbuild/SOURCES/${WHAT}-${FULL_VERSION}.tar.gz" ||
	git archive --format=tar.gz --prefix="${WHAT}-${FULL_VERSION}/" HEAD > \
		"../rpmbuild/SOURCES/${WHAT}-${FULL_VERSION}.tar.gz"
	)
}

show_help () {
	set +x
	echo "$0 [-c COPR_ID] [-m MOCK_TARGET] [-t TAG] [-h]" >&2
	echo "" >&2
	echo "  -h shows this help message." >&2
	echo "  -c COPR_ID performs a remote COPR build using the specified ID." >&2
	echo "  -m MOCK_TARGET performs a local MOCK build for the specified target." >&2
	echo "  -r RELEASE is only used when building a non-rc build via a tag.  It" >&2
	echo "     defaults to \"1\".  Typical usage would be -t 5.0.0 -r 3 in" >&2
	echo "     order to indicate that this is the 3rd iteration of the 5.0.0" >&2
	echo "     build." >&2
	echo "  -t TAG builds a \"release\" build of the specific tag.  If no tag" >&2
	echo "     is specified, a \"debug\" build of the HEAD will be built." >&2
	echo "" >&2
	echo "If neither -c nor -m is specified, then no build will be done, but" >&2
	echo "the SRPM will still be prepared, and can be used to manually kick off" >&2
	echo "a build at a later time." >&2
	echo "" >&2
	echo "example: $0 -c your_copr_id/kicad" >&2
	echo "example: $0 -m fedora-30-x86_64" >&2
	set -x
}

# Start of main shell script.
COPR_ID=
MOCK_TARGET=
TAG=HEAD
RELEASE=1
while getopts ":hc:m:r:t:" opt; do
	case "$opt" in
		h)
			show_help
			exit 1
			;;
		c)
			COPR_ID="${OPTARG}"
			;;
		m)
			MOCK_TARGET="${OPTARG}"
			;;
		r)
			RELEASE="${OPTARG}"
			;;
		t)
			TAG="${OPTARG}"
			;;
		\?)
			set +x
			echo "Invalid option: -${OPTARG}" >&2
			set -x
			show_help
			exit 1
			;;
		:)
			set +x
			echo "Option -${OPTARG} requires an argument." >&2
			set -x
			show_help
			exit 1
			;;
	esac
done

# Prepare directories.
[ -d build ] || mkdir build
rm -fr build/rpmbuild
mkdir -p build/rpmbuild/{SPECS,SOURCES}

# Get/update the source repos.
get_one "kicad"			"https://git.launchpad.net"	"${TAG}"
get_one "kicad-i18n"		"https://github.com/KiCad"	"${TAG}"
get_one "kicad-doc"		"https://github.com/KiCad"	"${TAG}"
get_one "kicad-templates"	"https://github.com/KiCad"	"${TAG}"
get_one "kicad-symbols"		"https://github.com/KiCad"	"${TAG}"
get_one "kicad-footprints"	"https://github.com/KiCad"	"${TAG}"
get_one "kicad-packages3D"	"https://github.com/KiCad"	"${TAG}"

# If our caller provided a tag, we use it for all repos.
#
# If no tag was specified, we use the latest revisions of all repos and we
# synthesize a version string.
if [ "${TAG}" != "HEAD" ]; then
	# Building for release via a tag.
	FULL_VERSION="${TAG}"

	# The tag will be something like 5.0.0-rc1 or 5.0.0.
	#
	# If it is like 5.0.0-rc1 then we need to split it into a version
	# and suffix because spec files don't allow a "-" in the "Version:"
	# line.
	#
	# If it is like 5.0.0 then there is nothing to split.
	case "${TAG}" in
		*-*)
			# Split the tag.
			VERSION="${TAG%%-*}"
			RELEASE="${TAG##*-}"

			# Create the spec file.
			sed \
				-e "s/@EPOCH@/1/" \
				-e "s/@BUILD_TYPE@/Release/" \
				-e "s/@VERSION@/${VERSION}/" \
				-e "s/@RELEASE@/${RELEASE}/" \
				-e "s/@FULL_VERSION@/${FULL_VERSION}/" \
				-e "/@VERSION_EXTRA@/d" \
				kicad.spec.template > build/rpmbuild/SPECS/kicad.spec
			;;
		*)
			# Nothing to split.  Just create the spec file.
			sed \
				-e "s/@EPOCH@/1/" \
				-e "s/@BUILD_TYPE@/Release/" \
				-e "s/@VERSION@/${FULL_VERSION}/" \
				-e "s/@RELEASE@/${RELEASE}/" \
				-e "s/@FULL_VERSION@/${FULL_VERSION}/" \
				-e "/@VERSION_EXTRA@/d" \
				kicad.spec.template > build/rpmbuild/SPECS/kicad.spec
			;;
	esac
else
	# Building for debug without a tag.  Synthesize a version string
	COUNT="$(get_rev_count 'build/kicad')"
	SHA="$(get_last_rev 'build/kicad')"
	FULL_VERSION="${COUNT}-${SHA}"

	# Create the spec file.
	sed \
		-e "s/@EPOCH@/100/" \
		-e "s/@BUILD_TYPE@/Debug/" \
		-e "s/@VERSION@/${COUNT}/" \
		-e "s/@RELEASE@/${SHA}/" \
		-e "s/@FULL_VERSION@/${FULL_VERSION}/" \
		-e "s/@VERSION_EXTRA@/-DKICAD_VERSION_EXTRA=${FULL_VERSION}/" \
		kicad.spec.template > build/rpmbuild/SPECS/kicad.spec
fi

# Create tar-balls for each component of the build.
make_tar "kicad"		"${FULL_VERSION}"	"${TAG}"
make_tar "kicad-i18n"		"${FULL_VERSION}"	"${TAG}"
make_tar "kicad-doc"		"${FULL_VERSION}"	"${TAG}"
make_tar "kicad-templates"	"${FULL_VERSION}"	"${TAG}"
make_tar "kicad-symbols"	"${FULL_VERSION}"	"${TAG}"
make_tar "kicad-footprints"	"${FULL_VERSION}"	"${TAG}"
make_tar "kicad-packages3D"	"${FULL_VERSION}"	"${TAG}"

# Now that we have the components, we can generate an SRPM file.
set +x
echo "Generating SRPM" >&2
set -x
RPMBUILD=build/rpmbuild
rpmbuild --define "_topdir ${RPMBUILD}" -bs "${RPMBUILD}/SPECS/kicad.spec"

# Get the name of the SRPM file.  We have to fill in the "dist" field.
SRPM=$(find build/rpmbuild/SRPMS -name "kicad-${FULL_VERSION}*.src.rpm")
set +x
echo "Prepared ${SRPM}"
set -x

# Do a local mock build.
if [ -n "${MOCK_TARGET}" ]; then
	set +x
	echo "Starting the local mock build."
	set -x
	mock -r "${MOCK_TARGET}" --rebuild "${SRPM}"
fi

# Do a remote copr build.
if [ -n "${COPR_ID}" ]; then
	set +x
	STATUS_LOCATION=$(echo ${COPR_ID} | sed -e 's/@/g\//')
	echo "Starting the remote copr build.  Check the status of the build here:"
	echo "https://copr.fedoraproject.org/coprs/${STATUS_LOCATION}/builds/"
	set -x
	copr-cli build "${COPR_ID}" "${SRPM}"
fi

exit 0
