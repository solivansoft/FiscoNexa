#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
versao=${1:?Uso: package-linux.sh versao}
[[ "$versao" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,60}$ ]] || exit 2
[[ $(uname -m) = x86_64 ]] || exit 2
. /etc/os-release
[[ "$ID:$VERSION_ID" = ubuntu:24.04 ]] || { echo 'Empacote no Ubuntu 24.04.' >&2; exit 1; }
destino="dist/fisconexa-$versao"
[[ ! -e "$destino" ]] || { echo 'Versao ja empacotada.' >&2; exit 1; }
test -f bin/linux64/FiscoNexa.Api
test -f bin/linux64/FiscoNexa.Worker
mkdir -p "$destino/lib/ossl-modules" "$destino/licenses"
cp bin/linux64/FiscoNexa.Api bin/linux64/FiscoNexa.Worker "$destino/"
cp -r bin/linux64/Schemas "$destino/"
mkdir -p "$destino/deploy"
cp deploy/*.sh deploy/*.example deploy/README.md "$destino/deploy/"
cp -r deploy/systemd "$destino/deploy/"
printf '%s\n' "$versao" > "$destino/VERSION"
for lib in libpq.so libssl.so libcrypto.so libxml2.so libxmlsec1.so libxmlsec1-openssl.so libxslt.so libexslt.so libz.so; do
  cp -L "/usr/lib/x86_64-linux-gnu/$lib" "$destino/lib/$lib"
done
cp /usr/lib/x86_64-linux-gnu/ossl-modules/legacy.so "$destino/lib/ossl-modules/"
# Fecha dependencias transitivas; glibc/loader permanecem parte do Ubuntu alvo.
for rodada in 1 2 3 4; do
  while IFS= read -r lib; do
    base=$(basename "$lib")
    case "$base" in libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|ld-linux*) continue;; esac
    [[ -f "$destino/lib/$base" ]] || cp -L "$lib" "$destino/lib/$base"
    pacote=$(dpkg-query -S "$(readlink -f "$lib")" 2>/dev/null | head -1 | cut -d: -f1 || true)
    if [[ -n "$pacote" && -f "/usr/share/doc/$pacote/copyright" ]]; then
      cp "/usr/share/doc/$pacote/copyright" "$destino/licenses/$pacote.txt"
    fi
  done < <(ldd "$destino"/FiscoNexa.* "$destino"/lib/*.so* "$destino"/lib/ossl-modules/*.so | awk '/=> \// {print $3}' | sort -u)
done
chmod +x "$destino"/FiscoNexa.* "$destino"/deploy/*.sh
LD_LIBRARY_PATH="$PWD/$destino/lib" ldd "$destino"/FiscoNexa.* "$destino"/lib/*.so* > "$destino/DEPENDENCIAS.txt"
! grep -q 'not found' "$destino/DEPENDENCIAS.txt"
(cd "$destino" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
tar -czf "$destino.tar.gz" -C dist "fisconexa-$versao"
sha256sum "$destino.tar.gz"
