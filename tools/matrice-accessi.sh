#!/usr/bin/env bash
#
# Matrice degli accessi di BcOk: verifica, SENZA credenziali, che ogni punto di ingresso
# risponda come previsto a un visitatore non loggato.
#
# Uso:
#   tools/matrice-accessi.sh [--pausa <secondi>] [--insecure] <url-del-sito>
#   tools/matrice-accessi.sh --pausa 0 https://bcok.local
#   tools/matrice-accessi.sh https://bcok.it
#
# Esce con 0 se tutti i controlli passano, con 1 se almeno uno fallisce.
# Fa solo GET, più una POST innocua su xmlrpc.php: non crea, modifica o cancella nulla.
#
# In produzione Wordfence può bloccare l'IP che fa molte richieste di fila: lasciare la pausa
# predefinita (1 secondo) e, se serve, mettere in whitelist temporanea l'IP da cui si lancia.
#
# Contesto: Ottomedia/pandora-meta#11 (rimozione di Ultimate Member) e #12.

set -u

# Route REST aperte ai non loggati in disable-json-api (ruolo "none").
# Da tenere allineate alla configurazione di produzione.
ROUTE_REST_APERTE=(
	"/booking/v2/stripe-webhook"
	"/booking/v2/stripe-verify-payment"
	"/pandora/v1/notifiche/sns"
)

# Codici d'errore di chi blocca la REST ai non loggati.
CODICI_REST_BLOCCO='rest_cannot_access|rest_unauthorized|restx_logged_out|rest_api_guard_unauthorized'

PAUSA=1
CURL_EXTRA=()
BASE=""

while [ $# -gt 0 ]; do
	case "$1" in
		--pausa) PAUSA="$2"; shift 2 ;;
		--insecure) CURL_EXTRA+=("-k"); shift ;;
		-h|--help) sed -n '2,17p' "$0"; exit 0 ;;
		*) BASE="${1%/}"; shift ;;
	esac
done

if [ -z "$BASE" ]; then
	echo "Uso: $0 [--pausa <secondi>] [--insecure] <url-del-sito>" >&2
	exit 2
fi

LOGIN="$BASE/wp-login.php"
TMP_BODY="$(mktemp)"
trap 'rm -f "$TMP_BODY"' EXIT

OK=0
KO=0
INFO=0

# Esegue la richiesta. Imposta STATUS e LOCATION; il corpo finisce in $TMP_BODY.
# Argomenti: metodo, percorso, [dati POST].
richiesta() {
	local metodo="$1" percorso="$2" dati="${3:-}"
	local args=(-s -o "$TMP_BODY" -m 20 -w '%{http_code} %{redirect_url}' -X "$metodo" "${CURL_EXTRA[@]}")
	if [ -n "$dati" ]; then
		args+=(-H 'Content-Type: text/xml' --data "$dati")
	fi
	local out
	out="$(curl "${args[@]}" "$BASE$percorso")"
	STATUS="${out%% *}"
	LOCATION="${out#* }"
	[ "$LOCATION" = "$STATUS" ] && LOCATION=""
	sleep "$PAUSA"
}

esito() {
	# Argomenti: stato (OK|KO|INFO), richiesta, attesa, ottenuta.
	local stato="$1" cosa="$2" attesa="$3" ottenuta="$4"
	case "$stato" in
		OK) OK=$((OK + 1)) ;;
		KO) KO=$((KO + 1)) ;;
		INFO) INFO=$((INFO + 1)) ;;
	esac
	printf '%-4s  %-58s  atteso: %-40s  ottenuto: %s\n' "$stato" "$cosa" "$attesa" "$ottenuta"
}

# 302 verso la pagina di login del core.
verso_login() {
	local percorso="$1"
	richiesta GET "$percorso"
	if [ "$STATUS" = "302" ] && [[ "$LOCATION" == "$LOGIN"* ]]; then
		esito OK "GET $percorso" "302 -> wp-login.php" "$STATUS ${LOCATION:0:80}"
	else
		esito KO "GET $percorso" "302 -> wp-login.php" "$STATUS ${LOCATION:0:80}"
	fi
}

# 302 verso un URL che inizia con il prefisso dato.
verso() {
	local percorso="$1" prefisso="$2" descrizione="$3"
	richiesta GET "$percorso"
	if [[ "$STATUS" == 30[12] ]] && [[ "$LOCATION" == "$prefisso"* ]]; then
		esito OK "GET $percorso" "$descrizione" "$STATUS ${LOCATION:0:80}"
	else
		esito KO "GET $percorso" "$descrizione" "$STATUS ${LOCATION:0:80}"
	fi
}

# Seguendo i redirect (al massimo 5, così un loop fallisce) si arriva alla pagina di login del core.
verso_login_finale() {
	local percorso="$1"
	local out
	out="$(curl -s -o /dev/null -m 20 -L --max-redirs 5 -w '%{http_code} %{num_redirects} %{url_effective}' "${CURL_EXTRA[@]}" "$BASE$percorso")"
	sleep "$PAUSA"
	local codice="${out%% *}" resto="${out#* }"
	local salti="${resto%% *}" finale="${resto#* }"
	if [ "$codice" = "200" ] && [[ "$finale" == "$LOGIN"* ]]; then
		esito OK "GET $percorso" "-> ... -> wp-login.php (200)" "$salti redirect, ${finale:0:70}"
	else
		esito KO "GET $percorso" "-> ... -> wp-login.php (200)" "$codice dopo $salti redirect, ${finale:0:70}"
	fi
}

# Codice di stato tra quelli ammessi (separati da |), senza redirect.
stato() {
	local percorso="$1" ammessi="$2"
	richiesta GET "$percorso"
	if [[ "|$ammessi|" == *"|$STATUS|"* ]]; then
		esito OK "GET $percorso" "$ammessi" "$STATUS ${LOCATION:0:80}"
	else
		esito KO "GET $percorso" "$ammessi" "$STATUS ${LOCATION:0:80}"
	fi
}

# REST chiusa ai non loggati: 401 con un codice di blocco.
rest_chiusa() {
	local percorso="$1"
	richiesta GET "$percorso"
	if [ "$STATUS" = "401" ] && grep -Eq "\"code\":\"($CODICI_REST_BLOCCO)\"" "$TMP_BODY"; then
		esito OK "GET $percorso" "401 bloccata" "$STATUS"
	else
		esito KO "GET $percorso" "401 bloccata" "$STATUS $(head -c 80 "$TMP_BODY")"
	fi
}

# REST aperta di proposito: la risposta non deve venire da chi blocca i non loggati.
# Va bene la risposta del gestore della route (es. errore di parametri o metodo non previsto).
rest_aperta() {
	local percorso="$1"
	richiesta GET "/wp-json$percorso"
	local codice
	codice="$(grep -Eo '"code":"[^"]*"' "$TMP_BODY" | head -1)"
	if grep -Eq "\"code\":\"($CODICI_REST_BLOCCO)\"" "$TMP_BODY" || [[ "$STATUS" == 30[12] ]]; then
		esito KO "GET /wp-json$percorso" "non bloccata" "$STATUS $codice"
	else
		esito OK "GET /wp-json$percorso" "non bloccata" "$STATUS $codice"
	fi
}

echo "Matrice degli accessi da non loggato: $BASE"
echo

echo "== Frontend: tutto porta al login"
verso_login "/"
verso_login "/aziende/"
verso_login "/richieste/"
verso_login "/sedi/"
verso_login "/aziende/feed/"
verso_login "/utilizzi/?export=pdf"
verso_login "/utilizzi/?export=xlsx"
verso_login "/?s=test"
verso_login "/author/admin/"

# /?author=N non deve rivelare lo username con un redirect verso /author/<username>/.
richiesta GET "/?author=1"
if [ "$STATUS" = "302" ] && [[ "$LOCATION" == "$LOGIN"* ]] && [[ "$LOCATION" != *"%2Fauthor%2F"* ]]; then
	esito OK "GET /?author=1" "302 -> wp-login.php, senza username" "$STATUS ${LOCATION:0:80}"
else
	esito KO "GET /?author=1" "302 -> wp-login.php, senza username" "$STATUS ${LOCATION:0:80}"
fi

richiesta GET "/wp-sitemap.xml"
if [ "$STATUS" = "404" ] || { [ "$STATUS" = "302" ] && [[ "$LOCATION" == "$LOGIN"* ]]; }; then
	esito OK "GET /wp-sitemap.xml" "302 -> wp-login.php oppure 404" "$STATUS ${LOCATION:0:80}"
else
	esito KO "GET /wp-sitemap.xml" "302 -> wp-login.php oppure 404" "$STATUS ${LOCATION:0:80}"
fi

# robots.txt: lo genera WordPress (200) oppure il web server non lo trova (404). Non deve portare al login.
stato "/robots.txt" "200|404"

echo
echo "== Vecchi URL di Ultimate Member"
verso "/login/" "$LOGIN" "302 -> wp-login.php"
verso "/password-reset/" "$LOGIN?action=lostpassword" "302 -> lostpassword"
verso "/nuova-password/" "$LOGIN?action=lostpassword" "302 -> lostpassword"
verso "/logout/" "$LOGIN" "302 -> wp-login.php"
for p in /account/ /user/ /user/qualcuno/ /elenco-operatori/ /attivazione/; do
	verso_login_finale "$p"
done

echo
echo "== Pagine di login del core"
stato "/wp-login.php" "200"
stato "/wp-login.php?action=lostpassword" "200"
verso "/wp-login.php?action=register" "$LOGIN?registration=disabled" "302 -> registrazione disabilitata"

echo
echo "== wp-admin e AJAX"
verso "/wp-admin/" "$LOGIN" "302 -> wp-login.php"
richiesta GET "/wp-admin/admin-ajax.php"
if [ "$STATUS" = "400" ] && [ "$(cat "$TMP_BODY")" = "0" ]; then
	esito OK "GET /wp-admin/admin-ajax.php" "400, corpo 0" "$STATUS"
else
	esito KO "GET /wp-admin/admin-ajax.php" "400, corpo 0" "$STATUS $(head -c 40 "$TMP_BODY")"
fi

echo
echo "== REST API"
rest_chiusa "/wp-json/"
rest_chiusa "/wp-json/wp/v2/users"
rest_chiusa "/wp-json/wp/v2/aziende"
rest_chiusa "/?rest_route=/wp/v2/users"
for r in "${ROUTE_REST_APERTE[@]}"; do
	rest_aperta "$r"
done

echo
echo "== Feed iCal (servito da pandora-planning prima del controllo d'accesso, protetto dal token)"
richiesta GET "/ical/999999999/token-non-valido/"
if [[ "|400|403|404|" == *"|$STATUS|"* ]]; then
	esito OK "GET /ical/<sede inesistente>/<token>/" "400|403|404, nessun redirect" "$STATUS"
else
	esito KO "GET /ical/<sede inesistente>/<token>/" "400|403|404, nessun redirect" "$STATUS ${LOCATION:0:80}"
fi

echo
echo "== XML-RPC (informativo finché non si decide se spegnerlo: pandora-meta#11, Fase 1 punto 4)"
richiesta POST "/xmlrpc.php" '<?xml version="1.0"?><methodCall><methodName>wp.getUsersBlogs</methodName><params><param><value><string>utente-inesistente</string></value></param><param><value><string>password-finta</string></value></param></params></methodCall>'
esito INFO "POST /xmlrpc.php wp.getUsersBlogs (credenziali finte)" "da decidere" "$STATUS $(grep -Eo '<string>[^<]{0,60}' "$TMP_BODY" | head -1 | sed 's/<string>//')"

echo
echo "== File e cartelle serviti dal web server"
richiesta GET "/wp-content/debug.log"
if [ "$STATUS" = "200" ]; then
	esito KO "GET /wp-content/debug.log" "non scaricabile" "$STATUS"
else
	esito OK "GET /wp-content/debug.log" "non scaricabile" "$STATUS"
fi

richiesta GET "/wp-content/uploads/"
if grep -qi "Index of" "$TMP_BODY"; then
	esito KO "GET /wp-content/uploads/" "nessun elenco dei file" "$STATUS elenco visibile"
else
	esito OK "GET /wp-content/uploads/" "nessun elenco dei file" "$STATUS"
fi

richiesta GET "/wp-content/plugins/pandora-crm/uacrm.php"
if grep -Eqi "fatal error|stack trace|wp-content/plugins|[a-z]:\\\\|/home/|/var/www" "$TMP_BODY"; then
	esito KO "GET /wp-content/plugins/pandora-crm/uacrm.php" "nessun contenuto, nessun percorso" "$STATUS espone dettagli"
else
	esito OK "GET /wp-content/plugins/pandora-crm/uacrm.php" "nessun contenuto, nessun percorso" "$STATUS"
fi

echo
echo "Esito: $OK ok, $KO falliti, $INFO informativi"
[ "$KO" -eq 0 ]
