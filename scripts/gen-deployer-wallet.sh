#!/usr/bin/env bash
# Generates the ASML-X deployer wallet as an encrypted JSON keystore.
# Keys live OUTSIDE the repo, in WSL home, never in OneDrive, never in git.
# Prints ONLY the public address. Never prints the private key or the password.
set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"

KEYDIR="$HOME/.asml-keys"
PASSFILE="$KEYDIR/keystore.pass"
RAWOUT="$KEYDIR/.newwallet.tmp"

mkdir -p "$KEYDIR"
chmod 700 "$KEYDIR"

if [ ! -f "$PASSFILE" ]; then
  head -c 48 /dev/urandom | base64 | tr -d '\n=+/' > "$PASSFILE"
  chmod 600 "$PASSFILE"
fi

if ls "$KEYDIR"/asml-deployer* >/dev/null 2>&1; then
  echo "STATUS: keystore already exists, not regenerating"
else
  # --unsafe-password is required here: without the flag, cast falls back to a
  # hidden TTY prompt and hangs forever under a non-interactive shell. The env
  # var alone does not suppress the prompt.
  cast wallet new "$KEYDIR" asml-deployer \
    --unsafe-password "$(cat "$PASSFILE")" > "$RAWOUT" 2>&1 < /dev/null
  chmod 600 "$RAWOUT"
  echo "STATUS: keystore created"
fi

KEYFILE="$(ls "$KEYDIR"/asml-deployer* | head -1)"
chmod 600 "$KEYFILE"

ADDR="$(cast wallet address --keystore "$KEYFILE" \
  --unsafe-password "$(cat "$PASSFILE")" 2>/dev/null < /dev/null || true)"
if [ -z "$ADDR" ]; then
  ADDR="$(grep -o '0x[0-9a-fA-F]\{40\}' "$RAWOUT" | head -1)"
fi

# Destroy the raw generation output so no secret lingers on disk.
if [ -f "$RAWOUT" ]; then
  shred -u "$RAWOUT" 2>/dev/null || rm -f "$RAWOUT"
fi

echo "KEYDIR: $KEYDIR"
echo "KEYFILE: $KEYFILE"
echo "PUBLIC_ADDRESS: $ADDR"
echo "PERMS: $(stat -c '%a %n' "$KEYDIR") | $(stat -c '%a %n' "$KEYFILE") | $(stat -c '%a %n' "$PASSFILE")"
