# SonarQube Community Build, pinned by version and digest.
# Update: bump the tag and digest together, then add a CHANGELOG.md entry.
FROM sonarqube:26.11.0.134175-community@sha256:65541accbdb92e27fe770fc6ba99988a3dd5a0c71ffafd67f88abfad366996fa

# The wrapper starts as root so it can fix the ownership of the Railway volume,
# then runs SonarQube as the image's own `sonarqube` user (Elasticsearch refuses root).
USER root
COPY --chmod=0755 start.sh /usr/local/bin/railway-start.sh

ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
