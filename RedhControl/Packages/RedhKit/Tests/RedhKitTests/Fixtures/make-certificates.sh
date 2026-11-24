#!/bin/sh
# Makes the certificates of the trust tests, in DER:
#   root.der           a root CA, like the homelab's ACME CA (and root.pem, the same in PEM)
#   leaf.der           rapi.lab.internal, signed by root
#   stranger-root.der  another root CA
#   stranger-leaf.der  rapi.lab.internal again, signed by stranger-root
#   box.der            self-signed, like a FRITZ!Box's certificate
# The leaves are valid from 2026-10-01 to 2027-10-01; the tests evaluate them
# on 2027-01-01. Only the certificates are kept, the keys are thrown away.
set -eu
cd "$(dirname "$0")"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

key() {
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$work/$1.key"
}

# root NAME COMMON-NAME
root() {
    key "$1"
    openssl req -x509 -new -key "$work/$1.key" -subj "/CN=$2" -sha256 \
        -not_before 20260101000000Z -not_after 20460101000000Z \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -outform DER -out "$1.der"
}

# leaf NAME ISSUER DNS-NAME
leaf() {
    key "$1"
    openssl req -new -key "$work/$1.key" -subj "/CN=$3" -out "$work/$1.csr"
    printf '%s\n' "basicConstraints=critical,CA:FALSE" "keyUsage=critical,digitalSignature" \
        "extendedKeyUsage=serverAuth" "subjectAltName=DNS:$3" > "$work/$1.ext"
    openssl x509 -req -in "$work/$1.csr" -CA "$2.der" -CAkey "$work/$2.key" -sha256 \
        -set_serial "0x$(openssl rand -hex 8)" \
        -not_before 20261001000000Z -not_after 20271001000000Z \
        -extfile "$work/$1.ext" -outform DER -out "$1.der"
}

root root "RedhKit Test Root"
openssl x509 -inform DER -in root.der -out root.pem
leaf leaf root rapi.lab.internal
root stranger-root "RedhKit Stranger Root"
leaf stranger-leaf stranger-root rapi.lab.internal

key box
openssl req -x509 -new -key "$work/box.key" -subj "/CN=fritz.box" -sha256 \
    -not_before 20260101000000Z -not_after 20460101000000Z \
    -addext "subjectAltName=DNS:fritz.box,DNS:www.fritz.box,IP:192.168.178.1" \
    -outform DER -out box.der
