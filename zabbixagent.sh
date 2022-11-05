: '
  Zabbix Agent Deployment Script
  Version:        1.3
  Creation Date:  21/02/22
  Purpose/Change: Added firewall rule
'

# Permission Check
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Script requires root to proceed."
  exit
fi

rm -f zabbixagent.sh

# Checking if a hostname is set
HOSTNAME=$(hostname -f)
if [ "$HOSTNAME" = "localhost" ]; then
  printf "ERROR: localhost is not a valid hostname, please change the hostname of the system to proceed.\nYou can use 'sudo hostnamectl set-hostname hostnamehere' to change the system hostname.\n"
  exit
fi

CHECK=$(systemctl status zabbix-agent | grep -o running)
CHECK2=$(systemctl status zabbix-agent2 | grep -o running)
if [ "$CHECK" = "running" ] || [ "$CHECK2" = "running" ]; then
  printf "Zabbix Agent is already running.\nIf upgrading to Zabbix Agent 2, uninstall the Agent before proceeding.\nExiting Script...\n"
  exit
fi

printf '*****\nFor the Zabbix Agent to collect and send metrics SeLinux will need to be disabled.\nTo quote some guy on the zabbix forum "This sounds really like "I want to drive this car, but I really would like to avoid opening doors to get in... "\n*****\n'
read -r -p "Do you want to set SeLinux to permissive? [Y/N]: " SELINUX_CONFIRM
case "$SELINUX_CONFIRM" in
  [Yy])
    sudo sed -c -i "s/\SELINUX=.*/SELINUX=permissive/" /etc/sysconfig/selinux
    setenforce 0
    ;;
  *)
    ;;
esac

read -r -p "Is an ACTIVE Agent required? [Y/N]: " ACTIVE_CONFIRM
echo "Running Script..."

# Install Repo
rpm -Uvh https://repo.zabbix.com/zabbix/6.2/rhel/8/x86_64/zabbix-release-6.2-3.el8.noarch.rpm > /dev/null 2> /dev/null
dnf clean all > /dev/null

# Install Agent
dnf install -y zabbix-agent2 > /dev/null 2> /dev/null
mkdir tmp
cd /tmp/

case "$ACTIVE_CONFIRM" in
  [yY])
    printf "Active agent not available\n"

    ;;
  *)
    curl -s url/to/config-tar/zabbix_agent2_passive.tar > zabbix_agent2_passive.tar
    tar -xf zabbix_agent2_passive.tar > /dev/null 2> /dev/null

    cp zabbix_agent2_passive.conf /etc/zabbix/zabbix_agent2.conf

    rm -f zabbix_agent2_passive.conf
    rm -f zabbix_agent2_passive.tar
  
    ;;
esac

if ! command -v firewall-cmd &> /dev/null
then
  printf "*****\nFirewalld not found, skipping firewall rule\nIf you intend for a firewall to be in place, run the following commands:\n"
  printf "\ndnf install -y firewalld\nfirewall-cmd --permanent --zone=public --add-service=zabbix-agent\nfirewall-cmd --reload\n*****\n"

else
  firewall-cmd --permanent --zone=public --add-service=zabbix-agent
  firewall-cmd --reload

fi

systemctl enable --now zabbix-agent2 > /dev/null 2> /dev/null

CHECK=$(systemctl status zabbix-agent2 | grep -o running)
if [ "$CHECK" = "running" ]; then
  echo "Zabbix Agent 2 is running"
else
  echo "Something went wrong with the install and the Zabbix Agent 2 is not running."
fi

echo Server Hostname: $HOSTNAME