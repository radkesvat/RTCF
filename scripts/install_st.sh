#install singlethreaded
print_red() {
    echo -e "\e[31m$1\e[0m"
}

if [ "$EUID" -ne 0 ]
  then print_red "Please run as root."
  exit
fi
#echo nameserver 8.8.8.8 | sudo tee /etc/resolv.conf



# Define the threshold in seconds (e.g., 72 hours)
threshold=259200

# Get the modification time of the package index file
last_update=$(stat -c %Y /var/lib/apt/lists/)

# Get the current time
current_time=$(date +%s)

# Calculate the time difference
time_difference=$((current_time - last_update))

# Check if the last update is older than the threshold
if [ "$time_difference" -gt "$threshold" ]; then
    echo "Updating package information..."
    
    # Execute apt-get update
    sudo apt-get update -y
    
else
    echo "Package information has been updated recently. Skipping."
fi



if pgrep -x "RTCF" > /dev/null; then
	print_red "Tunnel is running!. you must stop the tunnel before update. (pkill RTCF)"
	print_red "update is canceled."
  exit
fi




REQUIRED_PKG="unzip"
PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG|grep "install ok installed")
echo Checking for $REQUIRED_PKG: $PKG_OK
if [ "" = "$PKG_OK" ]; then
  echo "Setting up $REQUIRED_PKG."
  sudo apt-get --yes install $REQUIRED_PKG
fi

REQUIRED_PKG="wget"
PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG|grep "install ok installed")
echo Checking for $REQUIRED_PKG: $PKG_OK
if [ "" = "$PKG_OK" ]; then
  echo "Setting up $REQUIRED_PKG."
  sudo apt-get --yes install $REQUIRED_PKG
fi

REQUIRED_PKG="lsof"
PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG|grep "install ok installed")
echo Checking for $REQUIRED_PKG: $PKG_OK
if [ "" = "$PKG_OK" ]; then
  echo "Setting up $REQUIRED_PKG."
  sudo apt-get --yes install $REQUIRED_PKG
fi




printf  "\n"
printf  "\n"


echo "downloading ReverseTlsTunnel (Single Thread Version)"

printf  "\n"


case $(uname -m) in
    x86_64)  URL="https://github.com/radkesvat/RTCF/releases/download/V0.7/RTCF_ST_AMD-0.7.zip" ;;
    arm)     URL="https://github.com/radkesvat/RTCF/releases/download/V0.7/RTCF_ST_AMD-0.7.zip" ;;
    aarch64) URL="https://github.com/radkesvat/RTCF/releases/download/V0.7/RTCF_ST_AMD-0.7.zip" ;;
    
    *)   print_red "Unable to determine system architecture."; exit 1 ;;

esac


wget  $URL -O RTCF_ST_AMD-0.7.zip
unzip -o RTCF_ST_AMD-0.7.zip
chmod +x RTCF
rm RTCF_ST_AMD-0.7.zip

echo "finished."



