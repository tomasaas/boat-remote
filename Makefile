# The VPS between the PC and the boat. Run on the VPS (Debian/Ubuntu): make install
# The Pi connects out to here with WireGuard (tunnel: VPS 10.88.0.1, Pi 10.88.0.2), and Caddy
# asks for a password and forwards everything to app.py on the Pi. See README.md.
# Another domain: make install DOMAIN=<domain> (remembered in .domain).
LOGIN = boat
DOMAIN ?= $(or $(shell cat .domain 2>/dev/null),boat.tomasa.cloud)
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
	    $(SUDO) ufw allow 80/tcp && $(SUDO) ufw allow 443/tcp && $(SUDO) ufw allow 51820/udp; fi
	$(MAKE) --no-print-directory password
	@echo "Done. Next: run 'make pi' and put the output on the Pi (see README.md)."

# The Pi's WireGuard config, with the Pi's private key. Goes in /etc/wireguard/boat.conf on the Pi.
pi: $(KEYS)
	@ip="$(IP)"; test -n "$$ip" || { echo "Could not find this VPS's public IP. Use: make pi IP=<ip>" >&2; exit 1; }; \
	sed -e "s|@PI_KEY@|$$(cat keys/pi.key)|" -e "s|@VPS_PUB@|$$(cat keys/vps.pub)|" -e "s|@IP@|$$ip|" wg-pi.conf

# Asks for a new password (twice) and reloads Caddy. Also used to change the domain:
# make password DOMAIN=<domain>
password: | /usr/bin/caddy
	@echo "$(DOMAIN)" > .domain
	@hash=$$(caddy hash-password) && \
	sed -e "s|@SITE@|$(or $(DOMAIN),:80)|" -e "s|@LOGIN@|$(LOGIN)|" -e "s|@HASH@|$$hash|" Caddyfile \
	    | $(SUDO) tee /etc/caddy/Caddyfile >/dev/null && \
	$(SUDO) systemctl reload-or-restart caddy && \
	echo "Password set. Open $(if $(DOMAIN),https://$(DOMAIN),http://<vps-ip>) and log in as '$(LOGIN)'."

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

/usr/bin/caddy:
	$(MAKE) --no-print-directory caddy

# The newest Caddy .deb from GitHub (the one in Debian/Ubuntu is too old for this Caddyfile,
# and Caddy's apt repo on Cloudsmith answers 402). Run again to update Caddy.
caddy:
	url=$$(curl -fsSL https://api.github.com/repos/caddyserver/caddy/releases/latest \
	    | grep -o "https://[^\"]*_linux_$$(dpkg --print-architecture)\.deb" | head -1) && \
	test -n "$$url" && curl -fsSL -o /tmp/caddy.deb "$$url" && \
	$(SUDO) apt-get install -y /tmp/caddy.deb && rm -f /tmp/caddy.deb

uninstall:
	-$(SUDO) systemctl disable --now wg-quick@boat caddy
	$(SUDO) rm -rf /etc/wireguard/boat.conf /var/www/boat

.PHONY: install pi password status caddy uninstall
