#!/bin/bash

# some required and extra packages:
#   make gcc pesign nss-tools efivar
# (or also efitools for alternatively using cert-to-efi-sig-list)

# abort on first fail
set -e

# paths
KCARE_CONTRIB_PATH="kernelcare-contrib"
KCARE_CERT_LEGACY="$KCARE_CONTRIB_PATH/kernelcare_pub.der"
KCARE_CERT_LONGTERM="$KCARE_CONTRIB_PATH/kernelcare_pub_longterm_2032.der"

# cert owner GUIDs
KCARE_CERT_LEGACY_UUID="73c0f53d-7043-43dd-9455-e73ee1a10c32"
KCARE_CERT_LONGTERM_UUID="f77d6619-1cc1-471b-ba03-efbae888d268"

# build outputs
BUILD_DIR="kernelcare-build"
BUILD_NAME="shim_certificate_kernelcare_`uname -m`"
BINARY="$BUILD_DIR/$BUILD_NAME.efi"
LOG="$BUILD_DIR/$BUILD_NAME.log"

export PYTHONPATH="$KCARE_CONTRIB_PATH/edk2-pytool-extensions"
IMAGE_VALIDATION_TOOL="python -m edk2toolext.image_validation"

# cleanup
make clean
rm -rf *.efi *.esl $BUILD_DIR
mkdir -p $BUILD_DIR

# trace and log every command from here
exec > "$LOG" 2>&1
set -x

# convert x509 format to an EFI Signature List format, concatenate certs
#
# Note: place LONGTERM as the 1st one so the shim binaries which lack
#  2daf1db (multiple ESLs in one .db section) or
#  ea0f9df (broken multiple shim_certificate*.efi files, fixed in 470a8cd)
# will be able to use it even after LEGACY one expires. shim <16.1 is able
# to import only 1st cert.
efisecdb -a -g $KCARE_CERT_LONGTERM_UUID -c $KCARE_CERT_LONGTERM -o 01.esl
efisecdb -a -g $KCARE_CERT_LEGACY_UUID -c $KCARE_CERT_LEGACY -o 02.esl
cat 01.esl 02.esl > db.esl

# - log used toolchain;
# - build;
# - validate as per KernelCare Security Assessment (2025).
yum list | grep -e ^gcc.`uname -m` -e ^binutils.`uname -m`
make update all
mv certwrapper.efi $BINARY
# set and verify IMAGE_DLLCHARACTERISTICS_NX_COMPAT for binaries
$IMAGE_VALIDATION_TOOL --set-nx-compat -i $BINARY
$IMAGE_VALIDATION_TOOL -p APP -i $BINARY
# --get-nx-compat exits with the flag VALUE (1 = set, 0 = not set), not a
# success code - just proceed.
$IMAGE_VALIDATION_TOOL --get-nx-compat -i $BINARY || true

## optional: test before providing to MS for signing
##
# efikeygen -d /etc/pki/pesign --ca --self-sign --nickname='kcare-uefi-test' --common-name="CN=kcare-uefi-test" --serial=00
## export pub cert
# certutil -L -d /etc/pki/pesign -n kcare-uefi-test -o kcare-uefi-test.der -r
## copy to EFI folder so it will be available within UEFI
# cp kcare-uefi-test.der /boot/efi/EFI/
## sign and test certwrapper
# pesign -i certwrapper.efi -o /boot/efi/EFI/rocky/shim_certificate.efi -c kcare-uefi-test -s
##
## reboot, enable SecureBoot, enroll DB key
## in OVMF use:
##   Device Manager ->
##    Secure Boot Configuration ->
##     Secure Boot Mode (Custom) ->
##      Custom Secure Boot Options ->
##       DB Options ->
##        Enroll Signature Using File
## Don't forget to verify if SB is enabled, e.g. via 'mokutil --sb-state'
## Verify that all keys are imported via certwrapper and listed after reboot:
##   mokutil --list-enrolled | egrep -i 'SHA1|Issuer'
