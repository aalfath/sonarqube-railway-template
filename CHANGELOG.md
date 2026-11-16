# Changelog

## 26.11.0.134175 (2026-11-16)

- First release: SonarQube Community Build 26.11.0.134175 (`sonarqube:26.11.0.134175-community@sha256:65541accbdb92e27fe770fc6ba99988a3dd5a0c71ffafd67f88abfad366996fa`) with Railway PostgreSQL.
- The first boot replaces the default `admin` / `admin` login with `SONAR_ADMIN_PASSWORD` before the public port opens.
- Data and Marketplace plugins persist on the volume at `/sonarqube`.
