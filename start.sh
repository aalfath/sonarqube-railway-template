#!/bin/bash
# Railway wrapper for SonarQube Community Build.
#  - keeps data (Elasticsearch indexes) and installed plugins on one volume
#  - on first boot, replaces the default admin/admin login with SONAR_ADMIN_PASSWORD
#    while SonarQube listens on localhost only, so the public URL never offers admin/admin
#  - then runs SonarQube on $PORT
set -euo pipefail

SQ_HOME=/opt/sonarqube
PERSIST_DIR="${SONAR_PERSIST_DIR:-/sonarqube}"
PORT="${PORT:-9000}"
MARKER="$PERSIST_DIR/.admin-password-initialized"

log() { echo "[railway-start] $*"; }

# --- volume layout ----------------------------------------------------------
mkdir -p "$PERSIST_DIR/data" "$PERSIST_DIR/plugins" "$PERSIST_DIR/downloads"
export SONAR_PATH_DATA="$PERSIST_DIR/data"
# Plugins installed from the Marketplace are downloaded to extensions/downloads and moved to
# extensions/plugins on restart; keep both on the volume.
for d in plugins downloads; do
  if [ ! -L "$SQ_HOME/extensions/$d" ]; then
    if [ -d "$SQ_HOME/extensions/$d" ]; then cp -an "$SQ_HOME/extensions/$d/." "$PERSIST_DIR/$d/" 2>/dev/null || true; fi
    rm -rf "$SQ_HOME/extensions/$d"
    ln -s "$PERSIST_DIR/$d" "$SQ_HOME/extensions/$d"
  fi
done
chown -R sonarqube:root "$PERSIST_DIR" "$SQ_HOME/extensions" "$SQ_HOME/logs" "$SQ_HOME/temp"
chmod 0770 "$PERSIST_DIR"

# The embedded Elasticsearch enforces vm.max_map_count >= 262144. Railway hosts differ (65530 on
# some), and a container can't raise it, so fall back to non-mmap index storage when it's too low.
max_map_count="$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)"
if [ "$max_map_count" -lt 262144 ]; then
  log "vm.max_map_count is $max_map_count (< 262144): starting Elasticsearch with node.store.allow_mmap=false."
  export SONAR_SEARCH_JAVAADDITIONALOPTS="${SONAR_SEARCH_JAVAADDITIONALOPTS:+$SONAR_SEARCH_JAVAADDITIONALOPTS }-Dnode.store.allow_mmap=false"
fi

if [ -z "${SONAR_JDBC_URL:-}" ]; then
  log "SONAR_JDBC_URL is not set. This template expects a PostgreSQL database; refusing to start on the embedded H2 test database."
  exit 1
fi

# Note: stop the background instance with SIGTERM. Bash starts background jobs with SIGINT
# ignored, so the JVM would never see a SIGINT.
run_sonarqube() {
  cd "$SQ_HOME"
  # exec, so the background job's PID is the SonarQube JVM itself (signals reach it).
  exec setpriv --reuid=sonarqube --regid=root --clear-groups -- \
    env HOME="$SQ_HOME" /opt/java/openjdk/bin/java -jar lib/sonarqube.jar -Dsonar.log.console=true "$@"
}

# Stop the localhost-only instance and wait until its web and search child processes are gone,
# so the public start doesn't hit "Address already in use".
stop_bootstrap() {
  kill -TERM "$SQ_PID" 2>/dev/null || true
  wait "$SQ_PID" 2>/dev/null || true
  for i in $(seq 1 60); do
    pgrep -u sonarqube >/dev/null || return 0
    sleep 2
  done
  log "Leftover SonarQube processes after 120 s; killing them."
  pkill -KILL -u sonarqube || true
  sleep 2
}

# --- first boot: replace the default admin password -------------------------
if [ ! -f "$MARKER" ]; then
  log "First boot: starting SonarQube on 127.0.0.1 only to set the admin password."
  SONAR_WEB_HOST=127.0.0.1 SONAR_WEB_PORT=9000 run_sonarqube &
  SQ_PID=$!
  base="http://127.0.0.1:9000"
  for i in $(seq 1 360); do
    if ! kill -0 "$SQ_PID" 2>/dev/null; then log "SonarQube exited during first boot."; wait "$SQ_PID" || true; exit 1; fi
    status="$(curl -fsS "$base/api/system/status" 2>/dev/null || true)"
    case "$status" in *'"status":"UP"'*) break ;; esac
    sleep 5
  done
  case "${status:-}" in *'"status":"UP"'*) ;; *) log "SonarQube did not reach UP in 30 minutes."; stop_bootstrap; exit 1 ;; esac

  if curl -fsS -u admin:admin "$base/api/authentication/validate" | grep -q '"valid":true'; then
    if [ -z "${SONAR_ADMIN_PASSWORD:-}" ]; then
      log "The admin account still has the default password and SONAR_ADMIN_PASSWORD is empty. Set SONAR_ADMIN_PASSWORD and redeploy."
      stop_bootstrap; exit 1
    fi
    code="$(curl -sS -o /tmp/chpw.out -w '%{http_code}' -u admin:admin -X POST "$base/api/users/change_password" \
      --data-urlencode login=admin --data-urlencode previousPassword=admin --data-urlencode "password=$SONAR_ADMIN_PASSWORD")"
    if [ "$code" != "204" ] && [ "$code" != "200" ]; then
      log "Changing the admin password failed (HTTP $code): $(cat /tmp/chpw.out)"
      log "SonarQube needs at least 12 characters with upper case, lower case, a digit and a special character."
      stop_bootstrap; exit 1
    fi
    rm -f /tmp/chpw.out
    if ! curl -fsS -u "admin:$SONAR_ADMIN_PASSWORD" "$base/api/authentication/validate" | grep -q '"valid":true'; then
      log "The new admin password does not validate."; stop_bootstrap; exit 1
    fi
    log "Admin password set from SONAR_ADMIN_PASSWORD."
  else
    log "The admin account no longer uses the default password; leaving it unchanged."
  fi
  touch "$MARKER"; chown sonarqube:root "$MARKER"
  log "Stopping the localhost-only instance, then starting on the public port."
  stop_bootstrap
fi

# --- normal start -----------------------------------------------------------
export SONAR_WEB_HOST="${SONAR_WEB_HOST:-0.0.0.0}"
export SONAR_WEB_PORT="$PORT"
log "Starting SonarQube on port $PORT."
run_sonarqube &
SQ_PID=$!
STOPPING=0
trap 'STOPPING=1; kill -TERM "$SQ_PID" 2>/dev/null || true' TERM INT
wait "$SQ_PID" || true
wait "$SQ_PID" 2>/dev/null || true
if [ "$STOPPING" = 1 ]; then exit 0; fi
# SonarQube exits 0 even when it fails to start; report a failure so Railway restarts it.
log "SonarQube stopped unexpectedly."
exit 1
