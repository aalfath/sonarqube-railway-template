# SonarQube on Railway

Railway template for [SonarQube Community Build](https://www.sonarsource.com/open-source-editions/sonarqube-community-edition/), the self-hosted static code analysis server from SonarSource.

## What it deploys

| Service | Source | Notes |
|---|---|---|
| `SonarQube` | this repo (`Dockerfile`) | `sonarqube:26.11.0.134175-community`, pinned by digest. Public HTTPS domain, volume at `/sonarqube` |
| `Postgres` | Railway PostgreSQL | SonarQube's database |

The wrapper (`start.sh`) does three things on top of the official image:

1. **No default login.** SonarQube creates `admin` / `admin` on first start. On the first boot the wrapper starts SonarQube on `127.0.0.1` only, changes the admin password to `SONAR_ADMIN_PASSWORD`, stops it, and only then starts it on the public port. The public URL never accepts `admin` / `admin`.
2. **Persistent data.** Elasticsearch indexes (`SONAR_PATH_DATA`) and plugins installed from the Marketplace live on the Railway volume. Projects, issues and settings live in Postgres.
3. **Railway-friendly start.** It listens on `PORT`, fixes the volume's ownership, runs SonarQube as the image's `sonarqube` user, forwards stop signals, and exits non-zero if SonarQube stops unexpectedly so Railway restarts it.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `SONAR_ADMIN_PASSWORD` | `Sq1-${{secret(32)}}` | Password for the `admin` user, applied on first boot. Read it from the service's Variables tab. SonarQube needs 12+ characters with upper case, lower case, a digit and a special character |
| `SONAR_JDBC_URL` | `jdbc:postgresql://${{Postgres.PGHOST}}:${{Postgres.PGPORT}}/${{Postgres.PGDATABASE}}` | Database connection |
| `SONAR_JDBC_USERNAME` | `${{Postgres.PGUSER}}` | Database user |
| `SONAR_JDBC_PASSWORD` | `${{Postgres.PGPASSWORD}}` | Database password |
| `PORT` | `9000` | Port SonarQube listens on |

`SONAR_ADMIN_PASSWORD` is only used while the admin account still has the default password. After that, change the password in SonarQube (My Account → Security); the variable is not re-applied.

Any other SonarQube setting can be set as an environment variable, for example `SONAR_CORE_SERVERBASEURL=https://your-domain` (see [SonarQube system properties](https://docs.sonarsource.com/sonarqube-community-build/server-installation/system-properties/)).

## Scanning a project

1. Log in as `admin` with `SONAR_ADMIN_PASSWORD`.
2. Create a project and a token (My Account → Security).
3. Run a scanner against the public URL, for example:
   ```sh
   docker run --rm -v "$PWD:/usr/src" -e SONAR_HOST_URL=https://YOUR-DOMAIN -e SONAR_TOKEN=YOUR-TOKEN \
     sonarsource/sonar-scanner-cli -Dsonar.projectKey=my-project
   ```

## Resources

SonarQube runs three JVMs (web server, compute engine and Elasticsearch). Plan for at least 2 GB of RAM; 4 GB is comfortable for larger projects. The first boot creates the database schema and takes one to two minutes.

## Updates

The SonarQube version is pinned in `Dockerfile`. When a new version is merged to `main`, Railway shows an "update available" notice on projects deployed from this template, and you choose when to apply it. SonarQube migrates its database on start; read `CHANGELOG.md` and back up the Postgres database before you apply a major upgrade.

## Local test

```sh
docker build -t sonarqube-railway .
```
Run it with a PostgreSQL database and the variables above, with a volume mounted at `/sonarqube`.
