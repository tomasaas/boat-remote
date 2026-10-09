# The VPS between the PC and the boat. Run on the VPS (Debian/Ubuntu): make install
# The Pi connects out to here with WireGuard (tunnel: VPS 10.88.0.1, Pi 10.88.0.2), and Caddy
# on port 80 asks for a password and forwards everything to app.py on the Pi. See README.md.
LOGIN = boat
IP ?= $(shell curl -4 -fsS --max-time 5 https://api.ipify.org)
SUDO = $(if $(filter 0,$(shell id -u)),,sudo)
KEYS = keys/vps.key keys/vps.pub keys/pi.key keys/pi.pub

install: $(KEYS) | /usr/bin/caddy
	sed -e "s|@VPS_KEY@|$$(cat keys/vps.key)|" -e "s|@PI_PUB@|$$(cat keys/pi.pub)|" wg-vps.conf \
	    | $(SUDO) tee /etc/wireguard/boat.conf >/dev/null
	$(SUDO) chmod 600 /etc/wireguard/boat.conf
	$(SUDO) systemctl enable wg-quick@boat
	$(SUDO) systemctl restart wg-quick@boat
	$(SUDO) install -D -m 644 offline.html /var/www/boat/offline.html
	if command -v ufw >/dev/null && $(SUDO) ufw status | grep -q "Status: active"; then \
	    $(SUDO) ufw allow 80/tcp && $(SUDO) ufw allow 51820/udp; fi
	$(MAKE) --no-print-directory password
	@echo "Done. Next: run 'make pi' and put the output on the Pi (see README.md)."

# The Pi's WireGuard config, with the Pi's private key. Goes in /etc/wireguard/boat.conf on the Pi.
pi: $(KEYS)
	@ip="$(IP)"; test -n "$$ip" || { echo "Could not find this VPS's public IP. Use: make pi IP=<ip>" >&2; exit 1; }; \
	sed -e "s|@PI_KEY@|$$(cat keys/pi.key)|" -e "s|@VPS_PUB@|$$(cat keys/vps.pub)|" -e "s|@IP@|$$ip|" wg-pi.conf

# Asks for a new password (twice) and reloads Caddy.
password: | /usr/bin/caddy
	@hash=$$(caddy hash-password) && \
	sed -e "s|@LOGIN@|$(LOGIN)|" -e "s|@HASH@|$$hash|" Caddyfile | $(SUDO) tee /etc/caddy/Caddyfile >/dev/null && \
	$(SUDO) systemctl reload-or-restart caddy && \
	echo "Password set. Log in as '$(LOGIN)'."

status:
	-$(SUDO) wg show boat
	@if curl -fs --max-time 3 -o /dev/null http://10.88.0.2:8000/; then echo "app.py on the boat answers"; \
	else echo "app.py on the boat does not answer"; fi

keys/%.key: | /usr/bin/wg
	mkdir -p keys
	umask 077 && wg genkey > $@

keys/%.pub: keys/%.key
	wg pubkey < $< > $@

/usr/bin/wg:
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y wireguard-tools

# Caddy from its own apt repo: the one in Debian/Ubuntu is too old for this Caddyfile.
/usr/bin/caddy:
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y curl gnupg
	curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
	    | $(SUDO) gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
	curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
	    | $(SUDO) tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
	$(SUDO) chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y caddy

uninstall:
	-$(SUDO) systemctl disable --now wg-quick@boat caddy
	$(SUDO) rm -rf /etc/wireguard/boat.conf /var/www/boat

.PHONY: install pi password status uninstall
