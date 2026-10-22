#!/usr/bin/env bash
# Run only against a disposable image/container, never an existing PHP service.
set -euo pipefail
image=${1:?Usage: test-php74-image.sh IMAGE}
test "$(docker image inspect "$image" --format '{{.Architecture}}')" = amd64
test "$(docker image inspect "$image" --format '{{index .Config.Labels "io.dnmp.php-security-commit"}}')" = 712e60f9edfd03f0960fc4fc3c2c375f42b90aa2
docker run --rm "$image" php -r '
if (PHP_VERSION !== "7.4.34-dev") { fwrite(STDERR, PHP_VERSION); exit(1); }
foreach (explode(",", "pdo_mysql,mysqli,redis,mbstring,gd,curl,Zend OPcache,xdebug,pcntl,bcmath,calendar,zip,mongodb,imagick") as $ext) {
    if (!extension_loaded($ext)) { fwrite(STDERR, "Missing extension: $ext\n"); exit(1); }
}
echo PHP_VERSION, " extensions OK\n";
'
docker run --rm "$image" php-fpm -t
docker run --rm "$image" composer --version

# The official 7.4 backport exits immediately on OOM, without request cleanup.
# This is a bounded behavioral regression check, not an exploit.
set +e
oom_output=$(docker run --rm --memory=128m "$image" php -n -d memory_limit=16M -r \
    'register_shutdown_function(function () { echo "UNSAFE_SHUTDOWN"; }); str_repeat("x", 32 * 1024 * 1024);' 2>&1)
oom_status=$?
set -e
printf '%s\n' "$oom_output"
test "$oom_status" -eq 1
[[ "$oom_output" == *"Allowed memory size"* ]]
[[ "$oom_output" != *"UNSAFE_SHUTDOWN"* ]]

cid=$(docker run -d --memory=256m -p 127.0.0.1::9000 "$image")
trap 'docker rm -f "$cid" >/dev/null' EXIT
docker exec "$cid" sh -c 'printf "%s" "<?php echo \"DNMP_FPM_OK\";" > /www/health.php'
port=$(docker port "$cid" 9000/tcp)
python3 - "${port##*:}" <<'PY'
import socket, struct, sys, time

def record(kind, content):
    return struct.pack("!BBHHBB", 1, kind, 1, len(content), 0, 0) + content

params = {"SCRIPT_FILENAME": "/www/health.php", "REQUEST_METHOD": "GET",
          "SERVER_PROTOCOL": "HTTP/1.1", "GATEWAY_INTERFACE": "CGI/1.1"}
encoded = b"".join(bytes((len(k), len(v))) + k.encode() + v.encode()
                   for k, v in params.items())
request = (record(1, struct.pack("!HB5x", 1, 0)) + record(4, encoded)
           + record(4, b"") + record(5, b""))
for attempt in range(30):
    try:
        with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5) as conn:
            conn.sendall(request)
            response = b""
            while True:
                part = conn.recv(65536)
                if not part:
                    break
                response += part
        if b"DNMP_FPM_OK" in response:
            print("FastCGI request OK")
            break
    except OSError:
        pass
    time.sleep(1)
else:
    raise SystemExit("PHP-FPM failed to serve the test request")
PY
