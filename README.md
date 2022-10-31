# Setup K3d/K3s for GitHub Actions

Install K3d/K3s and start a local Kubernetes cluster of a specific version.

**K8s** is Kubernetes.
**K3s** is a lightweight K8s distribution.
**K3d** is a wrapper to run K3s in Docker.

K3d/K3s are especially good for development and CI purposes, as it takes
only 20-30 seconds of time till the cluster is ready. For comparison,
Kind takes 1.5 minutes, Minikube takes 2 minutes till ready (as of Sep'2020).


## Quick start

Start with the simplest way:

```yaml
jobs:
  some-job:
    steps:
      - uses: nolar/setup-k3d-k3s@v1
```

Change versions with the verbose way:

```yaml
jobs:
  some-job:
    steps:
      - uses: nolar/setup-k3d-k3s@v1
        with:
          version: v1.21  # E.g.: v1.21, v1.21.2, v1.21.2+k3s1
          github-token: ${{ secrets.GITHUB_TOKEN }}
```


## Inputs

### `version`

**Required** version of Kubernetes and/or K3s -- either full or partial.

The following notations are supported:

* `v1.21.2+k3s1`
* `v1.21.2`
* `v1.21`
* `v1`
* `latest`

Defaults to `latest`.

Keep in mind that K3d dates back only to v1.16.
There are no 1.15 and older versions of K8s.
Besides, 1.16 and 1.17 are broken and will not be fixed
(see [#11](https://github.com/nolar/setup-k3d-k3s/issues/11)).

When the version is partial, the latest detected one will be used,
as found in [K3s releases](https://github.com/k3s-io/k3s/releases),
according to the basic semantical sorting (i.e. not by time of releasing).


### `k3d-tag`

A tag/version of K3d to use. Corresponds to GitHub tags at
https://github.com/rancher/k3d/releases. For example, `v5.0.0`.
`latest` is also accepted, but converted to an empty string
for the installation script.

By default (i.e. if no value is provided), the latest version is used.


### `k3d-name`

A name of the cluster to be created.

By default (i.e. if no value is provided), K3d/K3s define their own name.
Usually it is `k3d-k3s-default`.

Note: the name should not include the `k3d-` prefix, but must be used with it.
The `k3d-` prefix is enforced by K3d and cannot be disabled.


### `k3d-args`

Additional args to pass to K3d.
See `k3d cluster create --help` for available flags.


### `github-token`

A token for GitHub API, which is used to avoid rate limiting.

The API is used to fetch the releases from the K3s repository.

By default, or if it is empty, then the API is accessed anonymously,
which implies the limit of approximately 60 requests / 1 hour / 1 worker.

Usage:

```yaml
with:
  github-token: ${{ secrets.GITHUB_TOKEN }}
```


### `skip-creation`

Whether to return from the action as soon as possible
without the cluster creation (the cluster readiness is also skipped).
This can be useful to only install the tools for manual cluster creation,
or to parse the available versions and return them as the action's outputs.

By default (`false`), the cluster is created.


### `skip-readiness`

Whether to return from the action as soon as possible,
possibly providing a cluster that is only partially ready.

By default (`false`), the readiness is awaited by checking for some preselected
resources to appear (e.g., for a service account named "default").


## Outputs

### `k3d-version`

The specific K3d version that was detected and used. E.g. `v5.0.0`.


### `k3s-version`

The specific K3s version that was detected and used. E.g. `v1.21.2+k3s1`.


### `k8s-version`

The specific K8s version that was detected and used. E.g. `v1.21.2`.


## Examples

With the latest version of K3d/K3s/K8s:

```yaml
steps:
  - uses: nolar/setup-k3d-k3s@v1
```

With the specific minor version of K8s, which implies the latest micro version
of K8s and the latest possible version of K3s:

```yaml
steps:
  - uses: nolar/setup-k3d-k3s@v1
    with:
      version: v1.21
```

With the very specific version of K3s:

```yaml
steps:
  - uses: nolar/setup-k3d-k3s@v1
    with:
      version: v1.21.2+k3s1
```

The partial versions enable the build matrices with only the essential
information in them, which in turn, makes it easier to configure GitHub
branch protection checks while the actual versions of tools are upgraded:

```yaml
jobs:
  some-job:
    strategy:
      fail-fast: false
      matrix:
        k8s: [ v1.21, v1.20, v1.19, v1.18 ]
    name: K8s ${{ matrix.k8s }}
    runs-on: ubuntu-22.04
    steps:
      - uses: nolar/setup-k3d-k3s@v1
        with:
          version: ${{ matrix.k8s }}
```

Multiple clusters in one job are possible, as long as there is enough memory
(note: `k3d-` prefix is enforced by K3d):

```yaml
jobs:
  some-job:
    name: Multi-cluster
    runs-on: ubuntu-22.04
    steps:
      - uses: nolar/setup-k3d-k3s@v1
        with:
          version: v1.20
          k3d-name: 1-20
      - uses: nolar/setup-k3d-k3s@v1
        with:
          version: v1.21
          k3d-name: 1-21
      - run: kubectl version --context k3d-1-20 
      - run: kubectl version --context k3d-1-21 
```

Custom version of K3d can be used, if needed:

```yaml
jobs:
  some-job:
    name: Custom K3d version
    runs-on: ubuntu-22.04
    steps:
      - uses: nolar/setup-k3d-k3s@v1
        with:
          k3d-tag: v4.4.8
      - run: k3d --version
```

Custom args can be passed to K3d (and through it, to K3s & K8s):

```yaml
jobs:
  some-job:
    name: Custom args
    runs-on: ubuntu-22.04
    steps:
      - uses: nolar/setup-k3d-k3s@v1
        with:
          k3d-args: --servers 2 --no-lb
      - run: kubectl get nodes  # there must be two of them
```

For real-life examples, see:

* https://github.com/nolar/kopf/actions (all "K3s…" jobs).
