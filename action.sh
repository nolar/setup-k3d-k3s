#!/bin/bash
set -eu
#set -x # for debugging

: ${GITHUB_API_URL:=https://api.github.com}
: ${VERSION:=latest}
: ${REPO:=rancher/k3s}

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  authz=("-H" "Authorization: Bearer ${GITHUB_TOKEN}")
else
  authz=()
fi

# Fetch all K3s versions usable for the specified partial version.
# Even if the version is specific and complete, assume it is possibly partial.
url="${GITHUB_API_URL}/repos/${REPO}/releases?per_page=999"
curl --silent --fail --location "${authz[@]}" "$url" | \
  jq '.[] | select(.prerelease==false) | .tag_name' >/tmp/versions.txt

echo "::group::All available K3s versions (unsorted)"
cat /tmp/versions.txt
echo "::endgroup::"

# Sort the versions numerically, not lexographically:
# 0. Preserve the original name of the version.
# 1. Split the version nmame ("v1.19.4+k3s1") into parts (["1", "19", "4", "1"]).
# 2. Convert parts to numbers when possible ([1, 19, 4, 1]).
# 3. Sort numerically instead of lexographically.
# 4. Restore the original name of each version.
jq --slurp '
  [ .[]
    | { original: .,
        numeric:
          .
          | ltrimstr("v")
          | split("(-|\\.|\\+k3s)"; "")
          | [ .[] | (tonumber? // .) ]
      }
  ]
  | sort_by(.numeric)
  | reverse
  | .[]
    | .original
  ' </tmp/versions.txt >/tmp/sorted.txt

echo "::group::All available K3s versions (newest on top)"
cat /tmp/sorted.txt
echo "::endgroup::"

# The "latest" version is not directly exposed, but we hard-code its meaning.
if [[ "${VERSION}" == "latest" ]]; then
  VERSION=$(head -n 1 /tmp/sorted.txt | jq -r)
fi

# The select only those versions that match the requested one.
# Do not rely on the parsed forms of the versions -- they may miss some parts.
# Rely only on the actual name of the version.
# TODO: LATER: Handle release candidates: v1.18.2-rc3+k3s1 must be before v1.18.2+k3s1.
jq --slurp --arg version "${VERSION}" '
  .[]
  | select((.|startswith($version + ".")) or
           (.|startswith($version + "-")) or
           (.|startswith($version + "+")) or
           (.==$version))
  ' </tmp/sorted.txt >/tmp/matching.txt

echo "::group::All matching K3s versions (newest on top)"
cat /tmp/matching.txt
echo "::endgroup::"

# Validate that we could identify the version (even a very specific one).
if [[ ! -s /tmp/matching.txt ]]; then
  echo "::error::No matching K3s versions were found."
  exit 1
fi

# Get the best possible (i.e. the latest) version of K3s/K8s.
K3S=$(head -n 1 /tmp/matching.txt | jq -r)
K8S=${K3S%%+*}

# Communicate back to GitHub Actions.
echo "::set-output name=k3s-version::${K3S}"
echo "::set-output name=k8s-version::${K8S}"

# Install K3d and start a K3s cluster. It takes 20 seconds usually.
# Name & args can be empty or multi-value. For this, they are not quoted.
curl --silent --fail https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash
k3d cluster create ${K3D_NAME:-} --wait --image=rancher/k3s:"${K3S//+/-}" ${K3D_ARGS:-}

# Sometimes, the service account is not created immediately. Nice trick, but no:
# we need to wait until the cluster is fully ready before starting the tests.
if [[ -z "${SKIP_READINESS}" ]]; then
  echo "::group::Waiting for cluster readiness"
  while ! kubectl get serviceaccount default >/dev/null; do sleep 1; done
  echo "::endgroup::"
else
  echo "Skipping the readiness wait. The cluster can be not fully ready yet."
fi
