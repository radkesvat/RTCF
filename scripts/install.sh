#!/bin/bash

#colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
white='\033[0;37m'
rest='\033[0m'

root_access() {
    # Check if the script is running as root
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires root access. please run as root."
        exit 1
    fi
}

#detect_distribution
detect_distribution() {
    # Detect the Linux distribution
    local supported_distributions=("ubuntu" "debian" "centos" "fedora")
    
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "${ID}" = "ubuntu" || "${ID}" = "debian" || "${ID}" = "centos" || "${ID}" = "fedora" ]]; then
            pm="apt-get"
            [ "${ID}" = "centos" ] && pm="yum"
            [ "${ID}" = "fedora" ] && pm="dnf"
        else
            echo "Unsupported distribution!"
            exit 1
        fi
    else
        echo "Unsupported distribution!"
        exit 1
    fi
}

# check_dependencies
check_dependencies() {
    detect_distribution
    
    local dependencies=("wget" "lsof" "iptables" "unzip" "curl" "socat")
    
    sudo $pm update -y
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo -e "${dep} is not installed. Installing..."
            sudo "${pm}" install "${dep}" -y
        fi
    done
}

#HTTPS Ports
https_ports(){
    echo -e "${green}-----------------------------------${rest}"
    echo -e "${yellow}Cloudflare Https Ports:${rest}"
    echo -e "${yellow}[443, 2053, 2083, 2087, 2096, 8443]${rest}"
}

#get rtcf
get_rtcf() {
  core_count=$(nproc --all)

  if [ $core_count -le 1 ]; then
    wget "https://raw.githubusercontent.com/radkesvat/RTCF/master/scripts/install_st.sh" -O install_st.sh && chmod +x install_st.sh && bash install_st.sh &&  rm install_st.sh && sleep 1 && clear
  else
    wget "https://raw.githubusercontent.com/radkesvat/RTCF/master/scripts/install_mt.sh" -O install_mt.sh && chmod +x install_mt.sh && bash install_mt.sh && install_mt.sh && sleep 1 && clear
  fi
    mv RTCF /usr/local/bin
}

#Check port
check_port() {
    local port_in_use=$(lsof -i :80 -t)
    
    if [ -n "$port_in_use" ]; then
        echo -e "${red}Port 80 is in use. Release the port...${rest}"
        exit 1
    fi
}

#Get certificates
install_certs() {
    echo -e "${cyan}Methods of applying certificate:${rest}"
    echo -e "${green}1.${rest} Certbot${yellow} [default]${rest}"
    echo -e "${green}2.${rest} Acme (Domain Required)${rest}"
    echo -e "${green}3.${rest} Custom path${rest}"
    echo ""

    read -rp "Please enter options [1-3]: " certInput
    check_port
    cert_path="/root/cf_certs/cert.crt"
    key_path="/root/cf_certs/private.key"
    [ ! -f "$cert_path" ] && mkdir -p /root/cf_certs

    if [[ -s $cert_path && -s $key_path && -f /root/cf_certs/do.log ]]; then
        domain=$(cat /root/cf_certs/do.log)
        echo -e "${green}The certificate of the original domain name: $domain was detected and is being applied${rest}"
    else
        case $certInput in
            1|"") # Certbot
                echo -e "${green}-----------------------------------${rest}"
                read -rp "Please enter your domain name: " domain
                [[ -z $domain ]] && echo -e "${red}No domain name entered, unable to perform operation!${rest}" && exit 1
                echo -e "${green}Domain name entered: $domain${rest}" && sleep 1
                validate_domain $domain
                certbot_install
                ;;
            2) # Acme (Domain Required)
                read -rp "Please enter your domain name: " domain
                validate_domain $domain
                acme_install $domain
                ;;
            3) # Custom path
                echo -e "${green}-----------------------------------${rest}"
                read -rp "Please enter the path of the [Public key] crt file: " cert_path
                echo -e "${yellow}Your PublicKey path : $cert_path${rest}"
                echo -e "${green}-----------------------------------${rest}"
                read -rp "Please enter the path of the[Private key] key file: " key_path
                echo -e "${yellow}Your Privatekey path: $key_path${rest}"
                echo -e "${green}-----------------------------------${rest}"
                read -rp "Please enter your domain name: " domain
                echo -e "${yellow}Your domain: $domain${rest}"
                echo -e "${green}-----------------------------------${rest}"
                ;;
            *)
                echo -e "${red}Invalid option!${rest}" && exit 1
                ;;
        esac
    fi

    chmod 755 $cert_path
    chmod 755 $key_path
    chmod 755 /root/cf_certs
    chmod 755 /root/cf_certs/do.log

    echo -e "${green}-----------------------------------${rest}"
    echo -e "${green}Successful! The certificate (cer.crt) and private key (private.key) saved in /root/cf_certs${rest}"
    echo -e "${green}The certificate crt file path: $cert_path${rest}"
    echo -e "${green}The private key file path: $key_path${rest}"
}

#validate_domain
validate_domain() {
    domain=$1
    domainIP=$(dig +short "${domain}")
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k)

    if [[ $domainIP != $ip ]]; then
        echo -e "${red}The IP resolved by the current domain name does not match the real IP used by the current VPS${rest}"
        echo -e "${green}Suggestions below:${rest}"
        echo -e "${yellow}1. Please make sure that CloudFlare is turned off (DNS only). The same applies to other domain name resolution or CDN website settings.${rest}"
        echo -e "${yellow}2. Please check whether the IP set by DNS resolution is the real IP of the VPS${rest}"
        exit 1
    fi
}

#cron
setup_cron() {
    ID=$(lsb_release -si)
    if [[ $ID == "CentOS" ]]; then
        $pm install cronie -y
        systemctl start crond
        systemctl enable crond
    else
        $pm install cron -y
        systemctl start cron
        systemctl enable cron
    fi

    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
    echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
}

#install acme
acme_install() {
    check_port
    curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
    source ~/.bashrc
    bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

    if [[ -n $(echo $ip | grep ":") ]]; then
        bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --listen-v6 --insecure
    else
        bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --insecure
    fi

    bash ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file $key_path --fullchain-file $cert_path --ecc

    if [[ -s $cert_path && -s $key_path ]]; then
        echo $domain > /root/cf_certs/do.log
        setup_cron
    else
        echo -e "${red}Certificate installation failed.${rest}" && exit 1
    fi
}

#Install certbot
certbot_install() {
    check_port
    $pm install certbot -y
    certbot certonly --standalone --agree-tos --register-unsafely-without-email -d $domain
    cert_path_lets="/etc/letsencrypt/live/$domain/fullchain.pem"
    key_path_lets="/etc/letsencrypt/live/$domain/privkey.pem"
    cp $cert_path_lets $cert_path
    cp $key_path_lets $key_path
    echo $domain > /root/cf_certs/do.log
}

#Check installed service
check_installed() {
    if systemctl is-active --quiet rtcf.service; then
        echo "The service is already installed and active."
        exit 1
    fi
}

# Function to configure arguments based on user's choice
configure_arguments() {
    PS3="Which server do you want to use? [1/2]: "
    options=("Iran (internal-server)" "Kharej (external-server)")

    while true; do
        select server_choice in "${options[@]}"; do
            case $server_choice in
                "Iran (internal-server)")
                    echo -e "${green}-----------------------------------${rest}"
                    install_certs
                    https_ports
                    echo ""
                    read -p "Please Enter Config (Local) Port [ use cloudflare HTTPS Ports or Multiport (e.g., '2087' or for Multiport '23-65535')]: " iran_local_port
                    echo -e "${green}-----------------------------------${rest}"
                    read -p "Please Enter Password (Choose the same password on both servers): " pass
                    echo -e "${green}-----------------------------------${rest}"
                    while true; do
					    read -p "Do you want to enable compression? (yes/no): " enable_compression_iran
					    if [ "$enable_compression_iran" == "yes" ]; then
					        echo -e "${green}Choose compressor algorithm:${rest}"
					        echo -e "${purple}1) ${cyan}Deflate${rest}"
					        echo -e "${purple}2) ${cyan}Lz4${rest}"
					        read -p "Enter your choice (1 or 2): " choice_iran
					        case $choice_iran in
					            1)
					                compressor=" --compressor:deflate"
					                ;;
					            2)
					                compressor=" --compressor:lz4"
					                ;;
					            *)
					                echo -e "${red}Invalid choice. Please enter 1 or 2.${rest}"
					                continue
					                ;;
					        esac
					        arguments="--iran --auto:off --cert:$cert_path --pkey:$key_path --domain:$domain --lport:$iran_local_port --password:$pass$compressor"
					        break
					    elif [ "$enable_compression_iran" == "no" ]; then
					        arguments="--iran --auto:off --cert:$cert_path --pkey:$key_path --domain:$domain --lport:$iran_local_port --password:$pass"
					        break
					    else
					        echo -e "${red}Invalid choice. Please enter yes or no.${rest}"
					    fi
					done
                    break
                    ;;
                "Kharej (external-server)")
                    echo -e "${yellow}Please install on [Internal-server] first. If you have installed it, ${green}press Enter to continue...${rest}"
                    read -r
                    echo -e "${green}-----------------------------------${rest}"
                    read -p "Please Enter IRAN IP (internal-server): " iran_ip
                    echo -e "${green}-----------------------------------${rest}"
                    read -p "Please Enter Your Domain Name: " domain
                    echo -e "${green}Your domain: ${domain}${rest}"
                    echo -e "${green}-----------------------------------${rest}"
                    read -p "Please Enter Config [vpn] Port: " config_port
                    https_ports
                    echo ""
                    read -p "Enter the [Port] of Internal server. Use cloudflare HTTPS Ports: " user_port
                    case $user_port in
                        443|2053|2083|2087|2096|8443)
                            echo -e "${green}Valid port selected: $user_port${rest}"
                            echo -e "${green}-----------------------------------${rest}"
                             ;;
                        *)
                            echo -e "${red}Invalid port. Please select one of the specified ports.${rest}"
                            continue
                            ;;
                    esac
                    read -p "Please Enter Password (Please choose the same password on both servers): " pass
                    echo -e "${green}-----------------------------------${rest}"
                    while true; do
                        read -p "Do you want to enable compression? (yes/no): " enable_compression
                        if [ "$enable_compression" == "yes" ]; then
                            echo -e "${green}Choose compressor algorithm:${rest}"
                            echo -e "${purple}1) ${cyan}Deflate${rest}"
                            echo -e "${purple}2) ${cyan}Lz4${rest}"
                            read -p "Enter your choice (1 or 2): " choice
                            case $choice in
                                1)
                                    compressor=" --compressor:deflate"
                                    ;;
                                2)
                                    compressor=" --compressor:lz4"
                                    ;;
                                *)
                                    echo -e "${red}Invalid choice. Please enter 1 or 2.${rest}"
                                    continue
                                    ;;
                            esac
                            arguments="--kharej --auto:off --domain:$domain --iran-ip:$iran_ip --iran-port:$user_port --toip:127.0.0.1 --toport:$config_port --password:$pass$compressor"
                            break
                        elif [ "$enable_compression" == "no" ]; then
                            arguments="--kharej --auto:off --domain:$domain --iran-ip:$iran_ip --iran-port:$user_port --toip:127.0.0.1 --toport:$config_port --password:$pass"
                            break
                        else
                            echo -e "${red}Invalid choice. Please enter yes or no.${rest}"
                        fi
                    done

                    break
                    ;;
                *) 
                    echo -e "${red}Invalid choice. Please enter a valid number.${rest}"
                    ;;
            esac
        done

        echo -e "${green}Configured arguments: ${cyan}RTCF $arguments${rest}"
        break
    done
}

# Function to handle installation
install() {
    root_access
    check_installed
    check_dependencies
    get_rtcf
    configure_arguments

    # Create a new service file named rtcf.service
    cat <<EOL > /etc/systemd/system/rtcf.service
[Unit]
Description=my RTCF service

[Service]
Type=idle
User=root
WorkingDirectory=/root
ExecStart=/usr/local/bin/RTCF $arguments
Restart=always

[Install]
WantedBy=multi-user.target
EOL

    # Reload systemctl daemon and start the service
    sudo systemctl daemon-reload
    sudo systemctl start rtcf.service
    sudo systemctl enable rtcf.service
    echo "Checking status..."
    sleep 2 && echo "" && check_tunnel_status
}

# Function to handle uninstallation
uninstall() {
    # Check if the service is installed
    if [ ! -f "/etc/systemd/system/rtcf.service" ]; then
        echo "The service is not installed."
        return
    fi

    # Stop and disable the service
    sudo systemctl stop rtcf.service
    sudo systemctl disable rtcf.service

    # Get the domain from the do.log file
    if [ -f "/root/cf_certs/do.log" ]; then
        domain=$(cat /root/cf_certs/do.log)
    fi

    # Remove service file
    sudo rm /etc/systemd/system/rtcf.service
    sudo systemctl reset-failed
    sudo rm /usr/local/bin/RTCF
    sudo rm -rf "/root/.acme.sh" > /dev/null 2>&1
    sudo rm -rf "/etc/letsencrypt" > /dev/null 2>&1
    sudo rm -rf "/root/cf_certs" > /dev/null 2>&1

    echo -e "${green}Uninstallation completed successfully.${rest}"
}

#update_services
update_services() {
    # Check if RTCF executable exists
    if [ -x "/usr/local/bin/RTCF" ]; then
        # Get the current installed version of RTCF
        installed_version=$(/usr/local/bin/RTCF -V 2>&1 | awk '/version/{print $5}' | cut -d= -f2)

        # Fetch the latest version from GitHub releases
        latest_version=$(curl -s https://api.github.com/repos/radkesvat/RTCF/releases/latest | grep -o '"tag_name": "[^"]*"' | cut -d":" -f2 | sed 's/["V ]//g')

        # Compare the installed version with the latest version
        if [[ "$latest_version" > "$installed_version" ]]; then
            echo "Updating to $latest_version (Installed: $installed_version)..."

            if sudo systemctl is-active --quiet rtcf.service; then
                echo "rtcf.service is active, stopping..."
                sudo systemctl stop rtcf.service > /dev/null 2>&1
            fi

            # Download and update RTCF
            get_rtcf

            # Start the previously active service
            if sudo systemctl list-units --type=service --all | grep -q 'rtcf.service'; then
                echo "Starting rtcf.service..."
                sudo systemctl start rtcf.service
            fi

            if sudo systemctl list-units --type=service --all | grep -q 'custom_rtcf.service'; then
                echo "Starting custom_rtcf.service..."
                sudo systemctl start custom_rtcf.service
            fi

            echo -e "${green}Service updated and restarted successfully.${rest}"
        else
            echo -e "${cyan}You Installed the latest version.[$installed_version]${rest}"
        fi
    else
        echo -e "${yellow}Please install RTCF first.${rest}"
    fi
}

#check_tunnel_status
check_tunnel_status() {
    # Check the status of the tunnel service
    if sudo systemctl is-active --quiet rtcf.service; then
        echo -e "${yellow}RTCF Tunnel: ${green} [running ✔]${rest}"
    else
        echo -e "${yellow}RTCF Tunnel: ${red} [Not running ✗ ]${rest}"
    fi
}

# check custom install
check_c_installed() {
    if systemctl is-active --quiet custom_rtcf.service; then
        echo "The service is already installed and active."
        exit 1
    fi
}
# check custom status
check_c_tunnel_status() {
    # Check the status of the load balancer tunnel service
    if sudo systemctl is-active --quiet custom_rtcf.service; then
        echo -e "${yellow}Custom Tunnel: ${green}[running ✔]${rest}"
    else
        echo -e "${yellow}Custom Tunnel:${red}[Not running ✗ ]${rest}"
    fi
}

#install_custom
install_custom() {
    root_access
    check_c_installed
    check_dependencies
    get_rtcf
    install_certs
    read -p "Enter RTCF arguments (Example: RTCF --auto:off --iran --lport:443 --password:123): " arguments
    
    # Create the custom_rtcf.service file with user input
    cat <<EOL > /etc/systemd/system/custom_rtcf.service
[Unit]
Description=Rtcf custom tunnel service

[Service]
Type=idle
User=root
WorkingDirectory=/root
ExecStart=/usr/local/bin/$arguments
Restart=always

[Install]
WantedBy=multi-user.target
EOL

    # Reload systemctl daemon and start the service
    sudo systemctl daemon-reload
    sudo systemctl start custom_rtcf.service
    sudo systemctl enable custom_rtcf.service
    sleep 1 && echo "" && check_c_tunnel_status
}

# uninstall_custom
uninstall_custom() {
    # Check if the service is installed
    if [ ! -f "/etc/systemd/system/custom_rtcf.service" ]; then
        echo "The Custom Tunnel is not installed."
        return
    fi

    # Stop and disable the service
    sudo systemctl stop custom_rtcf.service
    sudo systemctl disable custom_rtcf.service

    # Remove service file
    sudo rm /etc/systemd/system/custom_rtcf.service
    sudo systemctl reset-failed
    sudo rm /usr/local/bin/RTCF

    echo -e "${green}Uninstallation completed successfully.${rest}"
}

#ip  & version
myip=$(hostname -I | awk '{print $1}')
version=$(RTCF -V 2>&1 | awk '/version/{print $5}' | cut -d= -f2)

display_version() {
  if [ -n "$version" ]; then
    echo -e "${purple}-----------${cyan}Version: $version${purple}-----------${rest}"
  else
    echo -e "${purple}----------------------------------${rest}"
  fi
}

#Restart service
restart() {
    # Check if the service is installed
    if sudo systemctl is-enabled --quiet rtcf.service > /dev/null 2>&1; then
        # Service is installed, start it
        sudo systemctl restart rtcf.service > /dev/null 2>&1

        if sudo systemctl is-active --quiet rtcf.service; then
            echo -e "${green}The service has been successfully restarted.${rest}"
        else
            echo -e "${red}Tunnel service failed to Restart.${rest}"
        fi
    else
        echo -e "${yellow}Service is not installed.${rest}"
    fi
}

#Restart custom service
restart_custom() {
    # Check if the service is installed
    if sudo systemctl is-enabled --quiet custom_rtcf.service > /dev/null 2>&1; then
        # Service is installed, start it
        sudo systemctl restart custom_rtcf.service > /dev/null 2>&1

        if sudo systemctl is-active --quiet custom_rtcf.service; then
            echo -e "${green}The service has been successfully restarted.${rest}"
        else
            echo -e "${red}Tunnel service failed to Restart.${rest}"
        fi
    else
        echo -e "${yellow}Service is not installed.${rest}"
    fi
}

# Main menu
clear
echo -e "${cyan}By --> Peyman * Github.com/Ptechgithub * ${rest}"
echo -e "Your IP is: ${cyan}($myip)${rest} "
echo -e "${yellow}******************************${rest}"
check_tunnel_status
check_c_tunnel_status
echo -e "${yellow}******************************${rest}"
echo -e "${purple}-----#- RTCF Tunnel ${cyan}(Beta)${purple}-#-----${rest}"
echo -e "${green}1) Install${rest}"
echo -e "${green}2) Restart${rest}"
echo -e "${red}3) Uninstall${rest}"
echo -e "${yellow} ----------------------------${rest}"
echo -e "${green}4) Install Custom${rest}"
echo -e "${green}5) Restart Custom${rest}"
echo -e "${red}6) Uninstall Custom${rest}"
echo -e "${yellow} ----------------------------${rest}"
echo -e "${cyan}7) Update RTCF${rest}"
echo -e "${red}0) Exit${rest}"
display_version
read -p "Please choose: " choice

case $choice in
    1)
        install
        ;;
    2)
        restart
        ;;
    3)
        uninstall
        ;;
    4)
        install_custom
        ;;
    5)
        restart_custom
        ;;
    6)
        uninstall_custom
        ;;
    7)
        update_services
        ;;
    0)   
        exit
        ;;
    *)
        echo "Invalid choice. Please try again."
       ;;
esac
