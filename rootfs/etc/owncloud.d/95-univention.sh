#!/usr/bin/env bash
#95-univention.sh

to_logfile () {
  tee --append /var/lib/univention-appcenter/apps/owncloud/data/files/owncloud-appcenter.log
}

echo "[95.univeniton.sh] Checking if ldap file is present..."

if [ -f /var/lib/univention-appcenter/apps/owncloud/conf/ldap ]

then
  echo "[95.univeniton.sh] LDAP file found, continuing..."
  OWNCLOUD_PERMCONF_DIR="/var/lib/univention-appcenter/apps/owncloud/conf"
  OWNCLOUD_CONF_LDAP="${OWNCLOUD_PERMCONF_DIR}/ldap"

  echo "[95.univeniton.sh] Enable user_ldap app" 2>&1 | to_logfile
  n=1
  until [ $n -ge 20 ]
  do 
    r=$(occ app:enable user_ldap 2>&1)
    t=$?
    echo -n "."
    [[ $t == 0 ]] && break
    n=$(($n + 1))
    sleep 1
  done
  echo

  echo "[95.univeniton.sh] Read base configs for ldap" 2>&1 | to_logfile
  eval "$(< ${OWNCLOUD_CONF_LDAP})"


  if [ -f /var/lib/univention-appcenter/apps/owncloud/data/files/tobemigrated ]
  then
    echo "[95.univeniton.sh] delete ldap config in docker setup script" 2>&1 | to_logfile
    occ ldap:delete-config '' 2>&1 | to_logfile
    rm /var/lib/univention-appcenter/apps/owncloud/data/files/tobemigrated
  fi

  if [[ "$(occ ldap:show-config)" == "" ]]
  then
    echo "[95.univeniton.sh] creating new ldap config in docker setup script" 2>&1 | to_logfile
    occ ldap:create-empty-config 2>&1 | to_logfile
  fi

  echo "[95.univeniton.sh] setting variables from values in docker setup script" 2>&1 | to_logfile
  occ ldap:set-config s01 ldapHost ${LDAP_MASTER} 2>&1 | to_logfile
  occ ldap:set-config s01 ldapPort ${LDAP_MASTER_PORT} 2>&1 | to_logfile
  occ ldap:set-config s01 ldapAgentName ${LDAP_HOSTDN} 2>&1 | to_logfile
  
  while ! test -f "/etc/machine.secret"; do
  sleep 1
  echo "Still waiting"
  done
  
  occ ldap:set-config s01 ldapAgentPassword ${cat /etc/machine.secret} 2>&1 | to_logfile
  occ ldap:set-config s01 ldapBase ${owncloud_ldap_base} 2>&1 | to_logfile
  occ ldap:set-config s01 ldapLoginFilter $owncloud_ldap_loginFilter 2>&1 | to_logfile
  occ ldap:set-config s01 ldapUserFilter $owncloud_ldap_userFilter 2>&1 | to_logfile
  occ ldap:set-config s01 ldapGroupFilter $owncloud_ldap_groupFilter 2>&1 | to_logfile
  occ ldap:set-config s01 ldapQuotaAttribute $owncloud_ldap_user_quotaAttribute 2>&1 | to_logfile
  occ ldap:set-config s01 ldapExpertUsernameAttr $owncloud_ldap_internalNameAttribute 2>&1 | to_logfile
  occ ldap:set-config s01 ldapExpertUUIDUserAttr $owncloud_ldap_userUuid 2>&1 | to_logfile
  occ ldap:set-config s01 ldapExpertUUIDGroupAttr $owncloud_ldap_groupUuid 2>&1 | to_logfile
  occ ldap:set-config s01 ldapEmailAttribute $owncloud_ldap_emailAttribute 2>&1 | to_logfile
  occ ldap:set-config s01 ldapGroupMemberAssocAttr $owncloud_ldap_memberAssoc 2>&1 | to_logfile
  occ ldap:set-config s01 ldapBaseUsers $owncloud_ldap_base_users 2>&1 | to_logfile
  occ ldap:set-config s01 ldapBaseGroups $owncloud_ldap_base_groups 2>&1 | to_logfile
  occ ldap:set-config s01 useMemberOfToDetectMembership 0 2>&1 | to_logfile
  occ ldap:set-config s01 ldapConfigurationActive 1 2>&1 | to_logfile

  echo "[95.univeniton.sh] setting up user sync in cron"
cat << EOF >| /etc/cron.d/sync
*/10  *  *  *  * root /usr/local/bin/occ user:sync -m disable 'OCA\User_LDAP\User_Proxy'
EOF
  echo "[95.univeniton.sh] first user sync"
  occ user:sync -m disable "OCA\User_LDAP\User_Proxy" 2>&1 | to_logfile

## Added from request of Thomas, to have a working collabora setup out of the box
  echo "[95.univeniton.sh] setting collabora URL"
  if [[ "$(occ config:app:get richdocuments wopi_url)" == "" ]]
  then
     occ config:app:set richdocuments wopi_url --value https://"$docker_host_name" 2>&1 | to_logfile
  fi

  
  OWNCLOUD_PERM_DIR="/var/lib/univention-appcenter/apps/owncloud"
  OWNCLOUD_DATA="${OWNCLOUD_PERM_DIR}/data"
  OWNCLOUD_CONF="${OWNCLOUD_PERM_DIR}/conf"

  collabora_log=/var/lib/univention-appcenter/apps/owncloud/data/files/owncloud-appcenter.log
  collabora_cert=/etc/univention/ssl/ucsCA/CAcert.pem
  owncloud_certs=/var/www/owncloud/resources/config/ca-bundle.crt

  echo "[95.univeniton.sh] Is the collabora certificate is mounted correctly" >> $collabora_log
  if [ -f $collabora_cert ]
  then
          echo "Yes.
          Was it updated?" >> $collabora_log
          # Declaring the marker-string
          collab="This is a certificate for Collabora for ownCloud"
          if grep -Fq "$collab" "$owncloud_certs"
          then
                  echo "Yes. 
                  Certificate was already updated" >> $collabora_log
          else
                  echo "No. 
                  Updating Certificate..." >>$collabora_log
                  echo "$collab" >> $owncloud_certs
                  cat $collabora_cert >> $owncloud_certs
                  echo "Certificate has been succesfully updated" >> $collabora_log
          fi
  else 
          echo "There is no Collabora Certificate" >> $collabora_log        
  fi

  echo "[95.univeniton.sh] configuring owncloud for onlyoffice use"
  sed -i "s#);#  'onlyoffice' => array ('verify_peer_off' => TRUE),\n&#" $OWNCLOUD_CONF/config.php

else 

  echo "[95.univeniton.sh] no ldap file found..."

fi

true
