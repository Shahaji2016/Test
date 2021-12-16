##############################################################################################################################
#                         ################ ==|Install Prerequisites and AD Domain join setup on Linux VM|== ####################                                        
#                                                                                                                            
#  File name: domain_join_script.sh                                                                         
#  Owner:  Shahaji Nalawade                                                                                                     
#  Tester: Shahaji Nalawade                                                                                                      
#  Reviewer:                                                                                                                 
#  Environment: Azure Productions                                                                                           
#  Description: This script will do install Prerequisites and AD Domain join setup on Linux VM in bash file.         
#
#  Support -Verbose option
#
#  Written by Shahaji Nalawade
#
#  Version 1.0 - 2021-07-25
#
###############################################################################################################################
#!/bin/bash

help()
{
    echo "This script install Prerequisites and AD Domain join setup on Linux OS"
    echo "Parameters:"
    echo "  -d AD Domain Join Domain name"
    echo "  -o AD Domain Join OSTYPE "
	echo "  -p AD Domain Join AADPASS "
	echo "  -u AD Domain Join AADUSER "
	echo "  -v AD Domain Join OSVERSION "
    echo "  -h view this help content"
}

# Log method to control/redirect log output
log()
{
    echo "$1"
}

log "Begin execution of install Prerequisites and AD Domain join setup script extension on ${HOSTNAME}"


# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM
grep -q "${HOSTNAME}" /etc/hosts
if [ $? == 0 ]
then
  echo "${HOSTNAME} found in /etc/hosts"
else
  echo "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hosts file if not there
  sudo echo "127.0.0.1 ${HOSTNAME}.${DOMAINNAME} ${HOSTNAME}" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etc/hosts"
fi


#Loop through options passed
while getopts "d:f:n:o:p:u:v:h" optname; do
  log "Option $optname set with value ${OPTARG}"
  case $optname in
    d) #set domain name
      DOMAINNAME=${OPTARG}
      ;;
	f) #set domain name
      DOMAINFLAG=${OPTARG}
      ;;
	n) #set os version
      COMNAME=${OPTARG}
      ;;	
	o) #set os type
      OSTYPE=${OPTARG}
      ;;
	p) #set domain password
      AADPASS=${OPTARG}
      ;;
    u) #set domain user
      AADUSER=${OPTARG}
      ;;
	v) #set os version
      OSVERSION=${OPTARG}
      ;;		  
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done



join_domain_rhel(){
	echo y | sudo yum install oddjob oddjob-mkhomedir sssd adcli krb5-workstation krb5-libs realmd samba-common-tools authconfig 
	sudo realm discover ${DOMAINNAME}
	echo ${AADPASS} | kinit ${AADUSER}
	echo ${AADPASS} | sudo realm join --verbose ${DOMAINNAME} -U ${AADUSER}
}

join_domain_centos(){
	echo y | sudo yum install oddjob oddjob-mkhomedir sssd adcli krb5-workstation krb5-libs realmd samba-common-tools
	sudo realm discover ${DOMAINNAME}
	echo ${AADPASS} | kinit ${AADUSER}
	echo ${AADPASS} | sudo realm join --verbose ${DOMAINNAME} -U ${AADUSER} --membership-software=adcli
}

join_domain_ubuntu(){

	echo y | sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get -yq install krb5-user
	echo y | sudo apt-get install samba sssd sssd-tools libnss-sss libpam-sss ntp ntpdate realmd adcli
	
	sudo echo "127.0.0.1 ${COMNAME}.${DOMAINNAME} ${COMNAME}" >> /etc/hosts
	
	# This step will add domain name into ntp.conf
	grep -q "${DOMAINNAME}" /etc/ntp.conf
	if [ $? == 0 ]
	then
	  echo "${DOMAINNAME} found in /etc/ntp.conf"
	else
	  echo "${DOMAINNAME} not found in /etc/ntp.conf"
	  # Append it to the ntp.conf file if not there
	  sudo sed -i '$ a server ${DOMAINNAME}' /etc/ntp.conf
	  log "domain name ${DOMAINNAME} added to /etc/ntp.conf"
	fi
	
	sudo systemctl stop ntp
	sudo ntpdate ${DOMAINNAME}
	sudo systemctl start ntp
	
	grep -q "rdns=false" /etc/krb5.conf
	if [ $? == 0 ]
	then
	  echo "rdns=false found in /etc/krb5.conf"
	else
	  echo "rdns=false not found in /etc/krb5.conf"
	  # Append it to the hosts file if not there
	  sudo sed -i '/libdefaults]$/a \\trdns=false' /etc/krb5.conf
	  log "rdns=false added to /etc/krb5.conf"
	fi
	
	sudo realm discover ${DOMAINNAME}
	echo ${AADPASS} | kinit -V ${AADUSER} 
	echo ${AADPASS} | sudo realm join --verbose ${DOMAINNAME} -U ${AADUSER}  --install=/
	
	
	sudo sed -i -e 's|use_fully_qualified_names|#use_fully_qualified_names|g' /etc/sssd/sssd.conf	
	sudo systemctl restart sssd
	
}

join_domain_sles(){
	
	echo y | sudo zypper in krb5-client samba-winbind ntp
	
	
	WORKGROUPNAME=(${DOMAINNAME//./ })
	
	sudo sed -i 's/workgroup = WORKGROUP/workgroup = ${WORKGROUPNAME[0]}/g'  /etc/samba/smb.conf
	sudo sed -i 's/usershare allow guests = Yes/usershare allow guests = NO/g'  /etc/samba/smb.conf
	sudo sed -i '/global]$/a \\tidmap config * : backend = tdb\n\tidmap config * : range = 1000000-1999999\n\tidmap config IBMIMI : backend = rid\n\tidmap config IBMIMI : range = 5000000-5999999\n\tkerberos method = secrets and keytab\n\trealm = ${DOMAINNAME}\n\tsecurity = ADS\n\ttemplate homedir = /home/%D/%U\n\ttemplate shell = /bin/bash\n\twinbind offline logon = yes\n\twinbind refresh tickets = yes' /etc/samba/smb.conf

	sudo sed -i '/libdefaults]$/a \\tdefault_realm = ${DOMAINNAME}\n\tclockskew = 300' /etc/krb5.conf
	sudo sed -i '/realms]$/a \\t${DOMAINNAME} = {\n\tkdc = PDC.${DOMAINNAME}\n\tdefault_domain = ${DOMAINNAME}\n\tadmin_server = PDC.${DOMAINNAME}\n\t}' /etc/krb5.conf
	sudo sed -i '$ a [domain_realm]\n\t.${DOMAINNAME} = ${DOMAINNAME}.COM' /etc/krb5.conf
	sudo sed -i '$ a [appdefaults]\n\tpam = {\n\t\tticket_lifetime = 1d\n\t\trenew_lifetime = 1d\n\t\tforwardable = true\n\t\tproxiable = false\n\t\tminimum_uid = 1\n\t}' /etc/krb5.conf

	sudo sed -i 's/cached_login = no/cached_login = yes/g'  /etc/security/pam_winbind.conf
	sudo sed -i 's/krb5_auth = no/krb5_auth = yes/g'  /etc/security/pam_winbind.conf
	sudo sed -i 's/krb5_ccache_type =/krb5_ccache_type = FILE/g'  /etc/security/pam_winbind.conf

	sudo sed -i 's/passwd: compat/passwd: compat winbind/g'  /etc/nsswitch.conf
	sudo sed -i 's/group:  compat/group: compat winbind/g'  /etc/nsswitch.conf
	
	# This step will add domain name into ntp.conf
	grep -q "${DOMAINNAME}" /etc/ntp.conf
	if [ $? == 0 ]
	then
	  echo "${DOMAINNAME} found in /etc/ntp.conf"
	else
	  echo "${DOMAINNAME} not found in /etc/ntp.con"
	  # Append it to the ntp.con file if not there
	  sudo sed -i '$ a server ${DOMAINNAME}' /etc/ntp.conf
	  log "domain name ${DOMAINNAME} added to /etc/ntp.conf"
	fi
	
	sudo systemctl restart ntpd
	
	echo ${AADPASS} | sudo net ads join -U ${AADUSER}
	
	sudo pam-config --add --winbind
	sudo pam-config -a --mkhomedir
	
	sudo systemctl enable winbind
	sudo systemctl start winbind
	
}

add_adadmin_sudoers_file(){
    sudo sh -c "echo '%AAD\ DC\ Administrators@${DOMAINNAME}  ALL=(ALL)  NOPASSWD:ALL' >> /etc/sudoers"
	sudo sh -c "echo 'Defaults:Administrators@${DOMAINNAME} !requiretty' >> /etc/sudoers"
}

install_prereq_rhel(){
    sudo yum update -y --disablerepo='*' --enablerepo='*microsoft*'
    echo y | sudo yum install python3
	sudo sed -i 's/Defaults    requiretty/#Defaults    requiretty/g' /etc/sudoers
} 

install_prereq_centos(){
	sudo yum update -y --disablerepo='*' --enablerepo='*microsoft*'
	echo y | sudo yum install python3
	sudo sed -i 's/Defaults    requiretty/#Defaults    requiretty/g' /etc/sudoers
}

install_prereq_ubuntu(){
	echo y | sudo apt install python3.7
}

install_prereq_sles(){
	echo y | sudo zypper install python3
}

if [ "${DOMAINFLAG}" = "Yes" ]; then
	log "starting install Prerequisites and AD Domain join setup"
	if [ "${OSTYPE}" = "UbuntuServer" ]; then
		log "starting install Prerequisites and AD Domain join setup on Ubuntu Server"		
		install_prereq_ubuntu
		join_domain_ubuntu
		add_adadmin_sudoers_file
		log "completed install Prerequisites and AD Domain join setup on Ubuntu Server"
	elif [ "${OSTYPE}" = "RHEL" ]; then
		log "starting install Prerequisites and AD Domain join setup on RedHat Server"		
		install_prereq_rhel
		join_domain_rhel
		add_adadmin_sudoers_file
		log "completed install Prerequisites and AD Domain join setup on RedHat Server"
	elif [ "${OSTYPE}" = "CentOS" ]; then
		log "starting install Prerequisites and AD Domain join setup on CentOS Server"		
		install_prereq_centos
		join_domain_centos
		add_adadmin_sudoers_file
		log "completed install Prerequisites and AD Domain join setup on CentOS Server"
	elif [ "${OSTYPE}" = "SLES" ]; then
		log "starting install Prerequisites and AD Domain join setup on SLES Server"		
		install_prereq_sles
		join_domain_sles
		add_adadmin_sudoers_file
		log "completed install Prerequisites and AD Domain join setup on SLES Server"
	elif [ "${OSTYPE}" = "Oracle-Linux" ]; then
		log "starting install Prerequisites and AD Domain join setup on Oracle Server"
		install_prereq_sles
		join_domain_oracle
		add_adadmin_sudoers_file
		log "completed install Prerequisites and AD Domain join setup on Oracle Server"
	else
		echo "Install Prerequisites and AD Domain join setup are not performed for ${HOSTNAME}"
	fi
	log "completed install Prerequisites and AD Domain join setup"
else
	log "starting install Prerequisites"
	if [ "${OSTYPE}" = "UbuntuServer" ]; then
		log "starting install Prerequisites on Ubuntu Server"
		install_prereq_ubuntu
		log "completed install Prerequisites on Ubuntu Server"
	elif [ "${OSTYPE}" = "RHEL" ]; then
		log "starting install Prerequisites on RedHat Server"
		install_prereq_rhel
		log "completed install Prerequisites on RedHat Server"
	elif [ "${OSTYPE}" = "CentOS" ]; then
		log "starting install Prerequisites on CentOS Server"
		install_prereq_centos
		log "completed install Prerequisites on CentOS Server"
	elif [ "${OSTYPE}" = "SLES" ]; then
		log "starting install Prerequisites on SLES Server"
		install_prereq_sles
		log "completed install Prerequisites on SLES Server"
	elif [ "${OSTYPE}" = "Oracle-Linux" ]; then
		log "starting install Prerequisites on Oracle Server"
		install_prereq_oracle
		log "completed install Prerequisites on Oracle Server"
	else
		echo "Install Prerequisites is not performed for ${HOSTNAME}"
	fi
	log "completed install Prerequisites"
fi

exit 0

