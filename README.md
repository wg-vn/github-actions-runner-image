# github-actions-runner-image

An Ubuntu 26.04 act runner image with `mysql-server` and the `gh` CLI
preinstalled, for running workflows locally with
[act](https://github.com/wg-vn/github-actions-runner) that expect a
GitHub-hosted `ubuntu-latest` runner's preinstalled MySQL service and GitHub
CLI.

`catthehacker/ubuntu` publishes no 26.04 image, so the Dockerfile runs its
`act` recipe (`linux/ubuntu/scripts/act.sh` from
[catthehacker/docker_images](https://github.com/catthehacker/docker_images),
pinned by `CATTHEHACKER_REF`) on `buildpack-deps:26.04`, then sets the ENV
that catthehacker's build derives from `/etc/environment`. Two lines of
`act.sh` are patched for 26.04: `apt-key` no longer exists in apt 3, and
Microsoft signs its 26.04 package repo with `microsoft-2025.asc`.

`act`'s default images are deliberately minimal and don't include MySQL or
`gh`. This image adds them via `apt-get install mysql-server gh` (MySQL 8.4,
the same Ubuntu package the GitHub-hosted 26.04 image ships; `gh` from
GitHub's own apt repo, since Ubuntu's lags far behind), so workflow
steps that manage MySQL with `systemctl` (start/stop, tuning, etc.) or call
`gh` work the same way they do on a real GitHub-hosted runner.

`mysql-server`'s postinstall script initializes `/var/lib/mysql` and enables
`mysql.service` at build time, but doesn't start it — the base image's
`policy-rc.d` blocks that, exactly as it would in any other Docker build.

## Usage

Requires the `--systemd` flag added in
[wg-vn/github-actions-runner](https://github.com/wg-vn/github-actions-runner),
since `mysql.service` needs a real init system (PID 1) to manage, not act's
default `tail -f /dev/null` container.

```
act -j my-job --systemd -P ubuntu-latest=ghcr.io/wg-vn/github-actions-runner-image:latest
```

If the job's steps only ever reach MySQL via `127.0.0.1` from within the same
job container (no `services:` container, no external port needed), also pass
`--network bridge` instead of the default `--network host` — otherwise the
job container's `mysqld` binds the *host's* port 3306 directly and collides
with any MySQL already running there (e.g. a local dev stack).

## Building

```
docker build -t ghcr.io/wg-vn/github-actions-runner-image:latest \
  -t ghcr.io/wg-vn/github-actions-runner-image:act-latest-mysql .
docker push ghcr.io/wg-vn/github-actions-runner-image:latest
docker push ghcr.io/wg-vn/github-actions-runner-image:act-latest-mysql
```
