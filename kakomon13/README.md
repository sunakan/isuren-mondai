# KAKOMON13 AMI recipe

This target packages the ISUCON13 Go Application and benchmark for Ubuntu 26.04
arm64. Managed code is derived from official commit
`8f6afdc3603f0c661368de4659a7240862f59623`; binary image fixtures, SQL, and
initial data are not tracked by Git. Provisioning retrieves required paths from
the exact official commit and verifies the committed file manifest. The
frontend is built outside the image with Node 24.19.0 and Yarn 3.2.2: Vite
writes `upstream/isucon13/frontend/dist/`, while release files are assembled in
the ignored `kakomon13/dist/` directory and distributed through an exact-tagged
GitHub Release.

## AMI build

The normal build command loads the reviewed Ubuntu 26.04 arm64 source AMI and
the exact frontend Release tag/SHA-256 from
`kakomon13/scripts/ami-inputs.env`; no environment-variable export is needed.
When promoting a new source image or frontend Release, update that text file
after the external identity has been reviewed and published.

## Frontend Release

Push an exact KAKOMON13 frontend tag to build and publish the Release in GitHub
Actions:

```shell
git tag -m "v1.0.3" kakomon13-frontend-v1.0.3 && git push origin kakomon13-frontend-v1.0.3
```

The workflow fetches the non-managed image assets from the exact official
commit inside its runner; no local artifact upload is required.

The Release contains `kakomon13-frontend.tar.gz`, its outer SHA-256 file, and
the frontend file manifest. The archive digest is recorded in
`kakomon13/scripts/ami-inputs.env` for the AMI build.

## Hostname and external-media boundary

The recipe-owned zone is `u.isuren.internal`; its canonical Application target
is `pipe.u.isuren.internal`. PowerDNS, nginx, TLS SANs, Application cookies,
frontend API selection, and benchmark DNS/target constants use that contract.

`media.xiii.isucon.dev` remains an enumerated external media origin. The
official repository does not contain the HLS origin served by that host, and
the benchmark validates its URL values rather than making it a recipe service.
The static contract rejects new occurrences outside the six reviewed files.

## Topologies and gates

| topology | nodes | purpose | repository status |
| --- | --- | --- | --- |
| debug compact | Web + Bench on one VM | dirty iteration only | not an AMI gate |
| standalone | Web 1 + dedicated Bench 1 | normal/failure/reset/recovery/reboot acceptance | `not-run` |
| canonical/product | Web 3 + dedicated Bench 1 | Portal/provider product path | outside this repository slice |

The common image contains the Application services and a benchmark binary but
no role assignment. A later provider finalizer selects the role. TLS server
key/certificate and runtime address are generated after clone/fresh boot and
are absent from the sealed image. The self-signed certificate is only a public
practice fixture; a standalone Bench node must receive the Web trust anchor
through its separately approved finalizer. It is not an mTLS or Portal key.

The installed home layout follows the official `/home/isucon` structure with
the account name translated to `/home/isuren`: Application files live below
`webapp/`, the runtime environment is rendered as `env.sh` on every fresh boot,
and the license and benchmark executable live at the home root. Intentional
differences are the repository-wide mise runtime under `.local/`, the
architecture-neutral benchmark name `bench`, and removal of build-only
`isucon13/`, `go/`, and staging trees from the sealed image. Runtime data and
image fixtures are fetched inside the image build and installed where the
official Application expects them, but remain outside Git.

The official empty `.ssh/` directory, plaintext login password, xbuild
wrappers, and `local/golang/` tree are intentionally not reproduced. Access is
owned by SSM/provider finalizers, and mise replaces xbuild while preserving the
contestant-owned runtime boundary. Passwordless sudo is retained, matching the
official contestant user contract.

The benchmark binary accepts, for example:

```text
/home/isuren/bench run --target https://pipe.u.isuren.internal \
  --nameserver WEB_PRIVATE_IP --webapp WEB_PRIVATE_IP --dns-port 53 \
  --enable-ssl --result-path /tmp/result.json
```

The authoritative JSON includes `pass`, `score`, `messages`, `language`, and
`resolved_count`. A valid benchmark failure may still exit zero; consumers must
read `pass`, not infer success from the process status alone.

All external gates (`orb-recipe`, Golden, standalone, AMI build/fresh boot, and
product) remain `not-run` in this repository-only implementation.
