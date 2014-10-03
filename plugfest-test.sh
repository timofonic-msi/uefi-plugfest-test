#!/bin/bash

# Help
if [ -n "$1" ]; then
        RESULT=$(echo $1 | grep "help")
        if [ -n "$RESULT" ]; then
		echo "Usage:"
		echo "  plugfest-test.sh OPTIONS [ARGS...]"
		echo
		echo "Options:"
	 	echo "  --help			Show help"
		echo "  --revoke-mok			Revoke testing MOK from MOKlist to reset for next time testing"
		exit 0
	fi
fi

# check need root 
if [ $UID != 0 ]; then
	echo Testing suite must be run as root >&2
	exit 0
fi

# check efivarfs should available
if [ ! -d /sys/firmware/efi/efivars ]; then
	echo "/sys/firmware/efi/efivars/ doesn't exist."	
	echo "Please enable EFI variable filesystem due to this testing suite need it!"	
	exit 0
fi


# create folder of test result
TEST_RESULT="test-result"

if [ ! -f $TEST_RESULT ]; then  
	mkdir $TEST_RESULT 2> /dev/null
fi

SYSTEM_MANUFACTURER=$(dmidecode -s system-manufacturer)
SYSTEM_PRODUCT_NAME=$(dmidecode -s system-product-name)
BIOS_VENDOR=$(dmidecode -s bios-vendor)
BIOS_VERSION=$(dmidecode -s bios-version)
DATE=$(date +%F)

cd $TEST_RESULT
DIRNAME=$SYSTEM_MANUFACTURER"_"$SYSTEM_PRODUCT_NAME"_"$BIOS_VENDOR"_"$BIOS_VERSION"_"$DATE
LOGDIRNAME=${DIRNAME// /-}
mkdir $LOGDIRNAME 2> /dev/null
cd ..

# check if user want to run --revoke-mok
if [ -n "$1" ]; then
        RESULT=$(echo $1 | grep "revoke-mok")
        if [ -n "$RESULT" ]; then
		echo
		echo "========================================"
		echo "MOK Revoke Testing"
		echo "========================================"

		RESULT=$(mokutil --test-key mok-kernel-module-testing/signing_key.x509 2>&1)
		RESULT2=$(echo $RESULT | grep "is already enrolled")

		if [ -n "$RESULT2" ]; then
			cd mok-kernel-module-testing
			./mok-revoke-testing-1st.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/mok-revoke-testing-1st.log
			cd ..
		else
			cd mok-kernel-module-testing
			./mok-revoke-testing-2st.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/mok-revoke-testing-2st.log
			dmesg > ../$TEST_RESULT/$LOGDIRNAME/dmesg-revoked.log
			cd ..
		fi
                exit 0
        fi
fi

# check do we in second stage for running revoke MOK testing?
RESULT=$(mokutil --test-key mok-kernel-module-testing/signing_key.x509 2>&1)
RESULT2=$(echo $RESULT | grep "is already enrolled")

if [ -n "$RESULT2" ]; then
        RESULT=$(mokutil --list-new 2>&1)
        RESULT2=$(echo $RESULT | grep 'key 1')
        if [ -n "$RESULT2" ]; then
                echo
                echo "The certificate is in import list now!"
                echo
                echo "========================================"
                echo "Please run 'reboot' command to reboot system for enroll MOK from shim UI."
                echo "After enroll MOK by shim with root password then boot to system, please run plugfest-test.sh again to continue testing."
        else
                echo
                echo "========================================"
                echo "Check MOK enrolled and kerne module available"
                echo "========================================"

	        cd mok-kernel-module-testing
		./mok-enroll-testing-2st.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/mok-enroll-testing-2st.log
		dmesg > ../$TEST_RESULT/$LOGDIRNAME/dmesg-enrolled.log
		cd ..

		echo
		echo "========================================"
		echo "Testing suite finished!"
		echo 
		echo "Captured log files in:"
		echo $TEST_RESULT"/"${LOGDIRNAME// /-}
		echo
		echo "If your want to test again on the same machine, "
		echo "please run plugfest-test-revoke-mok.sh to revoke MOK first."
		echo "And, remember backup the test result of this time!"
        fi
	exit 0
fi

echo
echo "========================================"
echo "Take Machine information"
echo "========================================"

MACH_INFO="mach_info"
mkdir $TEST_RESULT/$LOGDIRNAME/$MACH_INFO

echo "take dmesg"
dmesg > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/dmesg.log
echo "[OK]"

echo "take dmidecode"
dmidecode > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/dmidecode.log
echo "[OK]"

echo "take /sys"
ls -R /sys 2>&1 | tee $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/sys.log > /dev/null
echo "[OK]"

echo "take /sys/firmware/efi/efivars/SecureBoot-*"
hexdump -C /sys/firmware/efi/efivars/SecureBoot-* > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/SecureBoot.dat
echo "[OK]"

echo "take Secure Boot state"
mokutil --sb-state > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/mokutil--sb-state.log
echo "[OK]"

echo "take hwinfo"
hwinfo 2>&1 | tee $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/hwinfo.log > /dev/null
echo "[OK]"

echo "take acpidump"
acpidump > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/acpidump.dat
echo "[OK]"

echo "take efibootmgr -l"
efibootmgr -v 2>&1 | tee  $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/efibootmgr-v.log > /dev/null
echo "[OK]"
# supportconfig -t $TEST_RESULT/$LOGDIRNAME 2>&1 | tee $TEST_RESULT/$LOGDIRNAME/supportconfig.log

echo
echo "========================================"
echo "UEFI Secure Boot Function Lock Testing"
echo "========================================"

cd function-lock-testing
./function-lock-testing.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/function-lock-testing.log
cd ..


echo
echo "========================================"
echo "EFI Variable Filesystem Testing"
echo "========================================"

cd efivarfs-testing
./efivarfs.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/efivarfs-testing.log
cd ..

echo
echo "========================================"
echo "MOK enroll with kernel module testing"
echo "========================================"

cd mok-kernel-module-testing
./mok-enroll-testing-1st.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/mok-enroll-testing-1st.log
cd ..


echo
echo "========================================"
echo "Captured log files in "$TEST_RESULT"/"${LOGDIRNAME// /-}
