# boat-remote

VPS-en som lar PC-en og båten møtes på internett. Pi-en på båten kobler seg ut til VPS-en med **WireGuard** og holder tunnelen åpen. PC-en åpner **http://\<vps-ip\>** i nettleseren, skriver passord, og **Caddy** sender alt videre gjennom tunnelen til `app.py` på Pi-en ([boat](https://github.com/tomasaas/boat)). Du får samme GUI som hjemme: styring, konfigurasjon og kobling.

```
PC (nettleser) ──HTTP + passord──▶ VPS: Caddy :80 ──WireGuard──▶ Pi: app.py :8000
                                        ▲
                          Pi-en kobler seg ut hit (UDP 51820)
```

Både PC-en og Pi-en kobler seg *ut* til VPS-en, så verken 4G-ruteren eller hjemmenettet trenger åpne porter. WireGuard tåler at 4G-adressen skifter.

## Oppsett

**1. VPS-en** (Debian eller Ubuntu). Åpne **80/tcp** og **51820/udp** i leverandørens brannmur hvis den har en (`ufw` på selve VPS-en ordnes automatisk).

```
sudo apt install -y git make
git clone https://github.com/tomasaas/boat-remote && cd boat-remote
make install      # installerer WireGuard og Caddy, lager nøkler og spør om passord
make pi           # skriver ut WireGuard-oppsettet til Pi-en
```

**2. Pi-en.** Lim inn det `make pi` skrev ut:

```
sudo apt install -y wireguard-tools
sudo nano /etc/wireguard/boat.conf           # lim inn, lagre
sudo systemctl enable --now wg-quick@boat    # starter tunnelen nå og ved hver oppstart
ping 10.88.0.1                               # svar = tunnelen er oppe
```

Ingenting i `boat` må endres: `app.py` lytter allerede på alle nettverkskort, også tunnelen.

**3. PC-en.** Åpne **http://\<vps-ip\>**. Brukernavn `boat`, passordet fra `make install`. Er båten ikke tilkoblet, vises en side som prøver igjen hvert 5. sekund.

## Kommandoer (på VPS-en)

| | |
|---|---|
| `make install` | Installerer og starter alt. Trygt å kjøre igjen; nøklene beholdes. |
| `make pi` | WireGuard-oppsett for Pi-en. Inneholder Pi-ens private nøkkel. `make pi IP=<vps-ip>` hvis IP-en ikke finnes automatisk. |
| `make password` | Nytt passord. |
| `make status` | Tunnelen (`latest handshake`) og om `app.py` på båten svarer. |
| `make uninstall` | Stopper tunnelen og Caddy. |

**SSH til Pi-en fra hvor som helst**, f.eks. for `git pull`: `ssh -J <bruker>@<vps-ip> <pi-bruker>@10.88.0.2`

## Filer

| Fil | Hva |
|---|---|
| `Makefile` | Installerer, lager nøkler og fyller inn malene under. |
| `Caddyfile` | Caddy: passord, videresending til `10.88.0.2:8000`, og `offline.html` når båten ikke svarer. |
| `wg-vps.conf` | WireGuard på VPS-en (`/etc/wireguard/boat.conf`). VPS-en er `10.88.0.1`. |
| `wg-pi.conf` | Mal for WireGuard på Pi-en, fylles ut av `make pi`. Pi-en er `10.88.0.2`. |
| `offline.html` | Vises når båten ikke svarer. |
| `keys/` | WireGuard-nøklene. Lages av `make install` og ligger ikke i git. Sletter du mappa, lages nye nøkler, og Pi-en må få ny `make pi`. |

## Sikkerhet

- **Passordet** sjekkes av Caddy før noe slipper gjennom. Uten HTTPS sendes passordet, video og styring **ukryptert** mellom PC-en og VPS-en, så unngå åpne wifi-nett. Mellom VPS-en og Pi-en er alt kryptert av WireGuard.
- **HTTPS senere:** pek et domene mot VPS-en, bytt `:80` med domenenavnet øverst i `Caddyfile`, åpne 443/tcp og kjør `make password`. Caddy henter sertifikat selv.
- `app.py` har ingen innlogging. Gjennom tunnelen er det bare VPS-en som når den.
- Mister båten 4G, stopper motorene etter 0,5 s (watchdogen i `app.py`).

## Feilsøking

- **`make status` viser ingen eller gammel `latest handshake`** (over ca. 2 min): Pi-en når ikke VPS-en. Sjekk 4G, `sudo systemctl status wg-quick@boat` på Pi-en, og at 51820/udp er åpen hos VPS-leverandøren.
- **Handshake OK, men `app.py` svarer ikke:** `journalctl -u boat -f` på Pi-en.
- **http://\<vps-ip\> svarer ikke i det hele tatt:** 80/tcp hos VPS-leverandøren, og `systemctl status caddy`.
- **`wg-quick@boat` feiler på VPS-en:** VPS-en må være en vanlig KVM-maskin; noen billige containere (OpenVZ/LXC) støtter ikke WireGuard.
