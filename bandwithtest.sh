#!/bin/bash


if [ ! -f /mnt/remote/Backups/GoogleDriveSpeedTest/500MB.bin ]; then
    echo "First run detected. Creating 500MB test file and uploading it to Google Drive."
    mkdir /mnt/remote/Backups/GoogleDriveSpeedTest/
    fallocate -l 500M /tmp/500MB.bin
    mv /tmp/500MB.bin /mnt/remote/Backups/GoogleDriveSpeedTest/
    echo "Finished uploading to Google Drive."
fi


testfile='google:/Backups/GoogleDriveSpeedTest/500MB.bin'

# Defaults
api=www.googleapis.com
whitelist=.whitelist-apis
blacklist=.blacklist-apis

#-------------------#
# Hosts file backup #
#-------------------#

for f in /etc/hosts.backup; do
	if [ -f "$f" ]; then
		printf "Hosts backup file found - restoring\n"
		sudo cp $f /etc/hosts
		break
	else
		printf "Hosts backup file not found - backing up\n"
		sudo cp /etc/hosts $f
		break
	fi
done

#-----------------#
# Diggity dig dig #
#-----------------#

mkdir tmpapi
mkdir tmpapi/speedresults/
mkdir tmpapi/testfile/
touch tmpapi/rclone.log
dig +answer $api +short > tmpapi/api-ips-fresh

#--------------------------#
# Whitelist Known Good IPs #
#--------------------------#

mv tmpapi/api-ips-fresh tmpapi/api-ips-progress
touch $whitelist
while IFS= read -r wip; do
	echo "$wip" >> tmpapi/api-ips-progress
done < "$whitelist"
mv tmpapi/api-ips-progress tmpapi/api-ips-plus-white

#------------------------#
# Backlist Known Bad IPs #
#------------------------#

mv tmpapi/api-ips-plus-white tmpapi/api-ips-progress
touch $blacklist
while IFS= read -r bip; do
        grep -v "$bip" tmpapi/api-ips-progress > tmpapi/api-ips
        mv tmpapi/api-ips tmpapi/api-ips-progress
done < "$blacklist"
mv tmpapi/api-ips-progress tmpapi/api-ips

#--------------#
# Colour codes #
#--------------#

RED='\033[1;31m'
YEL='\033[1;33m'
GRN='\033[0;32m'
NC='\033[0m'

#------------------#
# Checking each IP #
#------------------#

input=tmpapi/api-ips
sudo systemctl stop cloudplow
while IFS= read -r ip; do
	hostsline="$ip\t$api"
	sudo -- sh -c -e "echo '$hostsline' >> /etc/hosts"
	printf "Please wait, downloading the test file from $ip... "
	rclone copy --log-file tmpapi/rclone.log -v "${testfile}" tmpapi/testfile
		if grep -q "KiB/s" tmpapi/rclone.log; then
		speed=$(grep "KiB/s" tmpapi/rclone.log | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
	        printf "${RED}$speed KiB/s${NC} - Blacklisting\n"
        	rm -r tmpapi/testfile
	        rm tmpapi/rclone.log
		echo "$ip" >> .blacklist-apis
		sudo cp /etc/hosts.backup /etc/hosts
		else
	speed=$(grep "MiB/s" tmpapi/rclone.log | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
	printf "${GRN}$speed MiB/s${NC}\n"
	echo "$ip" >> tmpapi/speedresults/$speed
	rm -r tmpapi/testfile
	rm tmpapi/rclone.log
	sudo cp /etc/hosts.backup /etc/hosts
	fi
done < "$input"
sudo systemctl start cloudplow
#-----------------#
# Use best result #
#-----------------#

ls tmpapi/speedresults > tmpapi/count
max=$(sort -nr tmpapi/count | head -1)
macs=$(cat tmpapi/speedresults/$max)
printf "${YEL}The fastest IP is $macs at a speed of $max | putting into hosts file\n"
hostsline="$macs\t$api"
sudo -- sh -c -e "echo '$hostsline' >> /etc/hosts"

#-------------------#
# Cleanup tmp files #
#-------------------#

rm -r tmpapi
