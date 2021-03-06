#!/bin/bash
export LANG=en_US

env_check()
{
	# check need root 
	if [ $UID != 0 ]; then
		echo Testing suite must be run as root >&2
		exit 1
	fi

	# check efivarfs should available
	if [ ! -d /sys/firmware/efi/efivars ]; then
		echo "/sys/firmware/efi/efivars/ doesn't exist."	
		echo "Please enable EFI variable filesystem due to this testing suite need it!"	
		exit 1
	fi

	SECUREBOOT=$(cat /sys/firmware/efi/efivars/SecureBoot-* | grep '01')
	if [ -n "$SECUREBOOT" ]; then
		echo "Secure Boot Disabled! Please enable it in BIOS before whole testing."
		exit 1
	fi
}

show_help()
{
	echo "Usage:"
	echo "  plugfest-test.sh OPTIONS"
	echo
	echo "Options:"
	echo "  --help			Show this help"
	echo "  --stage1			Run the first stage of UEFI testing (before reboot for enrolling key)"
	echo "  --stage2			Run the second stage of UEFI testing (after reboot for enrolling key)"
	echo "  --clean			Revoke testing MOK from MOKlist to reset for next time testing"
	exit 0
}

create_workspace()
{
	MACH_INFO="mach_info"

	# create folder of test result
	TEST_RESULT="test-result"

	if [ ! -f $TEST_RESULT ]; then  
		mkdir $TEST_RESULT 2> /dev/null
	fi

	SYSTEM_MANUFACTURER=$(dmidecode -s system-manufacturer | grep -v \#)
	SYSTEM_PRODUCT_NAME=$(dmidecode -s system-product-name | grep -v \#)
	BIOS_VENDOR=$(dmidecode -s bios-vendor | grep -v \#)
	BIOS_VERSION=$(dmidecode -s bios-version | grep -v \#)
	DATE=$(date +%F)
	SUSE_RELEASE=$(head -1 /etc/SuSE-release | sed 's/ /_/g')
	PATCHLEVEL=$(cat /etc/SuSE-release | grep PATCHLEVEL | sed 's/ //g' | sed 's/=/_/g')
	UNAME_R=$(uname -r)

	cd $TEST_RESULT
	DIRNAME=$SYSTEM_MANUFACTURER"_"$SYSTEM_PRODUCT_NAME"_"$BIOS_VENDOR"_"$BIOS_VERSION"_"$DATE_$SUSE_RELEASE"_"$PATCHLEVEL_"$UNAME_R"
	LOGDIRNAME=${DIRNAME// /-}
	LOGDIRNAME=${LOGDIRNAME//[\/(),]/}
	mkdir $LOGDIRNAME 2> /dev/null
	cd ..
}

stage1()
{
	echo
	echo "========================================"
	echo "Take Machine information"
	echo "========================================"

	# Enable efi=debug in grub2.cfg
	EFI_DEBUG=$(cat /etc/default/grub | grep 'efi=debug')
	if [ -z "$EFI_DEBUG" ]; then
		echo "Enabling efi=debug and earlyprintk=efi in grub2.cfg"
		sed -i 's/showopts/showopts efi=debug earlyprintk=efi/1' /etc/default/grub
		grub2-mkconfig -o /boot/grub2/grub.cfg
	fi

	# Install acpica RPM if not there
	RPM=$(rpm -qa | grep acpica)
	if ! [ -n "$RPM" ]; then
		rpm -i rpm/acpica*.rpm
		echo "Install acpica RPM"
		echo ""
	fi

	mkdir $TEST_RESULT/$LOGDIRNAME/$MACH_INFO

	echo "take dmesg"
	dmesg > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/dmesg.log
	echo "[OK]"
	echo ""

	echo "take dmidecode"
	dmidecode > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/dmidecode.log
	echo "[OK]"
	echo ""

	echo "take /sys"
	ls -R /sys 2>&1 | tee $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/sys.log > /dev/null
	echo "[OK]"
	echo ""

	echo "take /sys/firmware/efi/efivars/SecureBoot-*"
	hexdump -C /sys/firmware/efi/efivars/SecureBoot-* > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/SecureBoot.dat
	SECUREBOOT=$(cat $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/SecureBoot.dat | grep '01')
	if [ -n "$SECUREBOOT" ]; then
		echo "Secure Boot Enabled"
	fi
	echo "[OK]"
	echo ""

	echo "take Secure Boot state"
	mokutil --sb-state > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/mokutil--sb-state.log
	echo "[OK]"
	echo ""

	echo "take hwinfo"
	hwinfo 2>&1 | tee $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/hwinfo.log > /dev/null
	echo "[OK]"
	echo ""

	echo "take acpidump"
	acpidump > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/acpidump.dat
	echo "[OK]"
	echo ""

	echo "take efibootmgr -l"
	efibootmgr -v 2>&1 | tee  $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/efibootmgr-v.log > /dev/null
	echo "[OK]"
	echo ""
	# supportconfig -t $TEST_RESULT/$LOGDIRNAME 2>&1 | tee $TEST_RESULT/$LOGDIRNAME/supportconfig.log

	echo
	echo "========================================"
	echo "UEFI Secure Boot Function Lock Testing"
	echo "========================================"

	if [ -n "$SECUREBOOT" ]; then
		echo "(Secure Boot Enabled in BIOS)"
	else
		echo "(Secure Boot Disabled in BIOS)"
	fi
	echo ""

	cd function-lock-testing
	sh ./function-lock-testing.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/function-lock-testing.log
	cd ..


	echo
	echo "========================================"
	echo "EFI Variable Filesystem Testing"
	echo "========================================"

	cd efivarfs-testing
	sh ./efivarfs.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/efivarfs-testing.log
	cd ..

	echo
	echo "========================================"
	echo "MOK enroll with kernel module testing"
	echo "========================================"

	cd mok-kernel-module-testing
	sh ./mok-enroll-testing-1st.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/mok-enroll-testing-1st.log
	cd ..


	echo
	echo "========================================"
	echo "Captured log files in "$TEST_RESULT"/"${LOGDIRNAME// /-}
	exit 0
}

stage2()
{
	echo "take dmesg with efi=debug"
	dmesg > $TEST_RESULT/$LOGDIRNAME/$MACH_INFO/dmesg-efi_debug.log
	echo "[OK]"
	echo ""

	echo
	echo "========================================"
	echo "Check MOK enrolled success"
	echo "========================================"

	RESULT=$(mokutil --test-key /etc/uefi/certs/uefi-plugfest.der 2>&1)
	ENROLLED=$(echo $RESULT | grep "is not enrolled")

	if [ -n "$ENROLLED" ]; then
		echo "MOK did not enrolled"
		exit 1
	fi

	echo
	echo "========================================"
	echo "Check MOK enrolled and kerne module available"
	echo "========================================"

	cd mok-kernel-module-testing
	sh ./mok-enroll-testing-2st.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/mok-enroll-testing-2st.log
	dmesg > ../$TEST_RESULT/$LOGDIRNAME/dmesg-enrolled.log
	cd ..

#	echo
#	echo "========================================"
#	echo "EFI Time Services Testing"
#	echo "========================================"
#
#	cd efi-time-testing
#	sh ./efi-time-testing.sh > ../$TEST_RESULT/$LOGDIRNAME/efi-time-testing.log
#	dmesg > ../$TEST_RESULT/$LOGDIRNAME/efi-time-dmesg.log
#	cd ..

	echo
	echo "========================================"
	echo "Testing suite finished!"
	echo 
	echo "Captured log files in:"
	echo $TEST_RESULT"/"${LOGDIRNAME// /-}
	echo
	echo "If your want to test again on the same machine, "
	echo "please run \"plugfest-test.sh --clean\" to remove MOK first."
	echo "And, remember backup the test result of this time!"

	exit 0
}

clean()
{
        if [ -e /etc/uefi/certs/uefi-plugfest.der ]; then
		echo
		echo "========================================"
		echo "MOK Revoke Testing"
		echo "========================================"

		RESULT=$(mokutil --test-key /etc/uefi/certs/uefi-plugfest.der 2>&1)
		RESULT2=$(echo $RESULT | grep "is already enrolled")

		cd mok-kernel-module-testing
		sh ./mok-revoke-testing-1st.sh 2>&1 | tee ../$TEST_RESULT/$LOGDIRNAME/mok-revoke-testing-1st.log
		cd ..
	fi
	exit 0
}

env_check
create_workspace
case "$1" in
        --help)
	    show_help
            ;;

        --stage1)
	    create_workspace
	    stage1
            ;;

        --stage2)
	    create_workspace
	    stage2
            ;;

        --clean)
            clean
            ;;

        *)
            echo $"Usage: $0 {--help|--stage1|--stage2|--clean}"
            exit 1
esac

# check if need reboot for enroll MOK
RESULT=$(mokutil --test-key /etc/uefi/certs/uefi-plugfest.der 2>&1)
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
		echo "The testing MOK enrolled now!"
		echo
		echo "========================================"
		echo "Please run 'plugfest-test --stage2' to the second stage of MOK testing."
		echo "or"
		echo "If your want to run testing again on the same machine, "
		echo "please run \"plugfest-test.sh --clean\" to remove MOK first."
		echo "And, remember backup the test result of this time!"
	fi
	exit 0
fi
