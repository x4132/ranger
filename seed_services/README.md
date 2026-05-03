# seed_services

Out-of-band deploy tool that pushes A/D services onto a live Ranger range.
Lives outside the Terraform graph — services are pulled, built, and started
*after* `terraform apply` has provisioned the infra. Re-run any time you add
a service or change a Dockerfile; each step is idempotent.

## Layout

```
seed_services/
├── README.md
├── services.yaml          # placeholder for per-service overrides
├── seed.py                # CLI entry point
└── lib/
    ├── tf.py              # `terraform output -json` reader
    ├── service.py         # discover + parse FAUST-style metadata.yml
    ├── ssh.py             # ssh/scp via the admin bastion
    ├── build.py           # tar + S3 upload
    ├── vulnbox.py         # docker compose install on each vulnbox
    ├── checker.py         # checker tree + deps on the checker host
    └── db.py              # Django Service row upsert via the gameserver
```

Each service is a directory under `../services/` with a `metadata.yml`
(FAUST CTF format). seed_services uses the metadata to pick up the slug,
checker script path, and Debian/pip checker deps.

## Usage

Prereqs: `terraform apply` succeeded, `admin_key.pem` is at the repo root,
local has `aws` and `ssh` on `$PATH`.

```bash
# What will be deployed
python3 seed_services/seed.py --list

# Build tarballs + upload to S3
python3 seed_services/seed.py --upload

# Push to every vulnbox (docker compose up -d --build)
python3 seed_services/seed.py --vulnboxes

# Install checker scripts on the checker host
python3 seed_services/seed.py --checker

# Register services in the gameserver Django DB
python3 seed_services/seed.py --db

# All of the above
python3 seed_services/seed.py --all

# Limit any of the above to one service
python3 seed_services/seed.py --all --service asm_chat
```

## Caveats

- **Native services aren't auto-deployed.** Services without a top-level
  `docker-compose.yml` (e.g. `veighty-machinery`, `ghost`) skip the vulnbox
  step with a warning. The FAUST install pattern (`make install DESTDIR=/`,
  `faustctf.target`, `docker-compose@.service` templates) hasn't been
  recreated here — for now, those services need a manual install.

- **Checker step stages files only.** It pulls each service's `checker/`
  tree onto the checker host and installs its declared deps, but does *not*
  configure `ctf-checker@<slug>.service` units yet. That step depends on
  installing the upstream `ctf-gameserver-checker` Debian package on the
  checker host, which is queued behind a separate task. You can run the
  checker scripts by hand for testing in the meantime
  (`/opt/checkers/<slug>/<checker_script>`).

- **`docker compose pull` failures are tolerated** because most FAUST
  services reference images at `faust.cs.fau.de:5000/...` that we can't
  reach from the public internet. The subsequent `docker compose up -d
  --build` pulls or builds whatever's missing locally; if a service needs an
  image that's neither buildable nor publicly available, deploy will fail
  with a clear docker error.
