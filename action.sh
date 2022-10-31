#!/bin/bash
set -eu

: ${GITHUB_API_URL:=https://api.github.com}
: ${VERSION:=latest}
: ${REPO:=k3s-io/k3s}

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  authz=("-H" "Authorization: Bearer ${GITHUB_TOKEN}")
else
  authz=()
fi

# Fetch all K3s versions usable for the specified partial version.
# Even if the version is specific and complete, assume it is possibly partial.
# 2-3 pages are enough to reach v0 while not depleting the GitHub API limits.
versions=""
for page in 1 2 ; do
  url="${GITHUB_API_URL}/repos/${REPO}/releases?per_page=999&page=${page}"
  releases=$(curl --silent --fail --location "${authz[@]-}" "$url")
  versions+=$(jq <<< "$releases" '.[] | select(.prerelease==false) | .tag_name')
  versions+=$'\n'
done
versions_sorted=$(sort <<< "$versions" --field-separator=- --key=1,1rV --key=2,2rV)

echo "::group::All available K3s versions (newest on top)"
echo "$versions_sorted"
echo "::endgroup::"

# The "latest" version is not directly exposed, but we hard-code its meaning.
if [[ "${VERSION}" == "latest" ]]; then
  VERSION=$(jq --slurp <<< "$versions_sorted" --raw-output '.[0]')
fi

# The select only those versions that match the requested one.
# Do not rely on the parsed forms of the versions -- they may miss some parts.
# Rely only on the actual name of the version.
# TODO: LATER: Handle release candidates: v1.18.2-rc3+k3s1 must be before v1.18.2+k3s1.
versions_matching=$(jq --slurp <<< "$versions_sorted" --arg version "${VERSION}" '
  .[]
  | select((.|startswith($version + ".")) or
           (.|startswith($version + "-")) or
           (.|startswith($version + "+")) or
           (.==$version))
  ')

echo "::group::All matching K3s versions (newest on top)"
echo "$versions_matching"
echo "::endgroup::"

# Validate that we could identify the version (even a very specific one).
if [[ -z "$versions_matching" ]]; then
  echo "::error::No matching K3s versions were found."
  exit 1
fi

# Get the best possible (i.e. the latest) version of K3s/K8s.
K3S=$(jq --slurp <<< "$versions_matching" --raw-output '.[0]')
K8S=${K3S%%+*}

# Install K3d and start a K3s cluster. It takes 20 seconds usually.
# Name & args can be empty or multi-value. For this, they are not quoted.
if [[ "${K3D_TAG:-}" == "latest" ]]; then
  K3D_TAG=""
fi
curl --silent --fail https://raw.githubusercontent.com/rancher/k3d/main/install.sh \
  | TAG=${K3D_TAG:-} bash
k3d --version
K3D=$(k3d --version | grep -Po 'k3d version \K(v[\S]+)' || true )

# Communicate back to GitHub Actions.
echo "Detected k3d-version::${K3D}"
echo "Detected k3s-version::${K3S}"
echo "Detected k8s-version::${K8S}"
echo "k3d-version=${K3D}" >> $GITHUB_OUTPUT
echo "k3s-version=${K3S}" >> $GITHUB_OUTPUT
echo "k8s-version=${K8S}" >> $GITHUB_OUTPUT

# Start a cluster. It takes 20 seconds usually.
if [[ -z "${SKIP_CREATION}" ]]; then
  k3d cluster create ${K3D_NAME:-} --wait --image=rancher/k3s:"${K3S//+/-}" ${K3D_ARGS:-}
else
  echo "Skipping the cluster creation. The cluster can be not fully ready yet."
fi

# Sometimes, the service account is not created immediately. Nice trick, but no:
# we need to wait until the cluster is fully ready before starting the tests.
if [[ -z "${SKIP_CREATION}" && -z "${SKIP_READINESS}" ]]; then
  echo "::group::Waiting for cluster readiness"
  while ! kubectl get serviceaccount default >/dev/null; do sleep 1; done
  echo "::endgroup::"
else
  echo "Skipping the readiness wait. The cluster can be not fully ready yet."
fi
