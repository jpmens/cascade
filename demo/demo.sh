# Sane environment.
set -euxo pipefail
cd /srv/cascade

# Stop Cascade if it is already running.
sudo systemctl stop cascaded
sudo systemctl stop kmip2pkcs11-cascaded

# Copy over all static files.
cp -r $HOME/cascade/demo/* ./

# Build and copy over all binaries.
for dir in cascade dnst kmip2pkcs11; do
  pushd "$HOME/$dir" >/dev/null
  cargo build --message-format json --release
  popd >/dev/null
done | jq -r '.executable|strings' | xargs cp -t /srv/cascade/bin
export PATH="/srv/cascade/bin:${PATH}"

# Correct ownership.
sudo chown -R cascade:cascade /srv/cascade
sudo chmod -R g+w /srv/cascade

# Wipe all existing Cascade state.
rm -rf cascade/{keys,kmip,zone-state,state.db}

# Start Cascade.
sudo systemctl start cascaded
sudo systemctl start kmip2pkcs11-cascaded
sleep 5

# Check the logs.
sudo systemctl status cascaded
tail cascade/log
sleep 3

# Check on SoftHSM keys.
SOFTHSM2_CONF=/srv/cascade/softhsm/softhsm2.conf softhsm2-util --show-slots; sleep 5

# Check 'kmip2pkcs11'.
cat kmip2pkcs11/config.toml; sleep 1

# Add SoftHSM via 'kmip2pkcs11'.
cascade hsm add \
  --username "Cascade token 1" --password "verysecurepin" \
  --insecure --port 1060 softhsm 127.0.0.1
sleep 3

# Show 'cascade.nlnetlabs.nl'.
cat cascade/zones/cascade.nlnetlabs.nl.zone; sleep 5

# Show the 'hsm' policy.
cat cascade/policies/cascade.toml; sleep 5

# Add the zone.
cascade zone add --policy cascade \
  --source /srv/cascade/cascade/zones/cascade.nlnetlabs.nl.zone \
  --import-ksk-kmip softhsm 1B938AF32D4CD4AD7EFC4532F54828FBC38B5781_pub 1B938AF32D4CD4AD7EFC4532F54828FBC38B5781_priv 13 257 \
  --import-zsk-kmip softhsm 2AF59DCEEBEF088702837E66613F875F5026D5A9_pub 2AF59DCEEBEF088702837E66613F875F5026D5A9_priv 13 256 \
  cascade.nlnetlabs.nl 
sleep 5

# Watch Cascade do stuff.
sudo systemctl status cascaded; sleep 5

# Check on the zone.
cascade zone list
cascade zone status cascade.nlnetlabs.nl

# Oh no!  We have a problem!
# Restore the missing AAAA record.
cat <<'EOF' >cascade/zones/cascade.nlnetlabs.nl.zone
$ORIGIN cascade.nlnetlabs.nl.
$TTL 240
@	IN  SOA rusty.nlnetlabs.nl. hostmaster.nlnetlabs.nl. 4 28800 7200 604800 240

@	IN  NS  rusty.nlnetlabs.nl.
@	IN  TXT "Stichting NLnet Labs Cascade DNSSEC signer zone"

; rusty public interface
@	IN  A   185.49.141.18
@	IN  AAAA 2a04:b900:0:100::18
EOF

# Carry on.
cascade zone reload cascade.nlnetlabs.nl
sleep 5
cascade zone status cascade.nlnetlabs.nl


