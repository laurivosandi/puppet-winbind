# == Class: sssd
#
# Full description of class sssd here.
#
# === Parameters
#
# Document parameters here.
#
# [*sample_parameter*]
#   Explanation of what this parameter affects and what it defaults to.
#   e.g. "Specify one or more upstream ntp servers as an array."
#
# === Variables
#
# Here you should define a list of variables that this module would require.
#
# [*sample_variable*]
#   Explanation of how this variable affects the funtion of this class and if
#   it has a default. e.g. "The parameter enc_ntp_servers must be set by the
#   External Node Classifier as a comma separated list of hostnames." (Note,
#   global variables should be avoided in favor of class parameters as
#   of Puppet 2.6.)
#
# === Examples
#
#  class { sssd:
#    default_domain => "example.org"
#  }
#
#  sssd::ad { "example.org":
#    workgroup => "EXAMPLE",
#  }
#
#  OR with more parameters specified
#
#  class { sssd:
#    default_domain => "apple.org",
#    domains => ["apple.org", "banana.org"],
#    fallback_homedir => "/home/%d/%u",
#    override_shell => "/bin/bash",
#  }
#
#  sssd::ad { "apple.org":
#    workgroup => "APPLE",
#    netbios_name => "EMPLOYEE1",
#    join_username => "joiner",
#    join_password => "verysecure",
#    algorithmic_ids => false
#  }
#
#  sssd::ldap { "banana.org":
#    cacert_file => "/etc/ssl/certs/ldap-ca.pem",
#    uri => "ldap://ldap.banana.org",
#    search_base => "cn=users,dc=banana,dc=org",
#    bind_dn => "userid=sssd,dc=banana,dc=org",
#    bind_password => "verysecure"
#  }

#
# === Authors
#
# Lauri Võsandi <author@domain.com>
#
# === Copyright
#
# Copyright 2015 Lauri Võsandi, unless otherwise noted.
#

class winbind(
  $domain,
  $workgroup = "WORKGROUP",
  $netbios_name = upcase($hostname),
  $fallback_homedir = "/home/%u",
  $override_shell = "/bin/bash",
  $algorithmic_ids = true,
  $mkhomedir = true,
  $skel = undef,
  $umask = undef
) {
  $realm = upcase($domain)

  if $mkhomedir {
    file { "/usr/share/pam-configs/mkhomedir":
      ensure  => present,
      owner   => "root",
      group   => "root",
      mode    => "0644",
      content => template("winbind/mkhomedir.erb"),
    }
    ~>
    Exec['pam_auth_update']
  } else {
    file { "/usr/share/pam-configs/mkhomedir": ensure  => absent }
    ~>
    Exec['pam_auth_update']
  }


  if $join_username and $join_password {  
    Ini_setting <| path == '/etc/samba/smb.conf' |>
    ->
    exec { "net-ads-join":
      command => "/usr/bin/net ads join -U ${join_username}%${join_password}",
      unless => "/usr/bin/net ads testjoin"
    }
    ~>
    Service["winbind"]
  }

  # Ensure winbind service is running
  package { "samba-common": ensure => installed }
  ->
  Ini_setting <| path == '/etc/samba/smb.conf' |>

  # Ensure nsswitch is updated after PAM config is set
  Exec["pam_auth_update"]
  ->
  File_line <| path == "/etc/nsswitch.conf" |>


  # Update PAM config
  exec { "pam_auth_update":
    command => "/usr/sbin/pam-auth-update",
    refreshonly => true
  }
  
  # Ensure winbind is started after config changes
  package { "winbind": ensure => installed }
  ->
  Ini_setting <| path == '/etc/samba/smb.conf' |>
  ~>
  service { "winbind":
    ensure => running,
    enable => true
  }


  package { "libpam-winbind": ensure => installed, notify => Exec['pam_auth_update'] }
  package { "libnss-winbind": ensure => installed, notify => Exec['pam_auth_update'] }
  package { "sudo": ensure => installed }
  package { "krb5-user": ensure => installed }
  package { "kstart": ensure => installed }
  package { "libsasl2-modules-gssapi-heimdal": ensure => installed }
  package { "libsasl2-modules-ldap": ensure => installed }
  ->
  # Remove SSSD
  package { "sssd": ensure => absent }
  package { "sssd-tools": ensure => absent }
  package { "libpam-sss": ensure => absent, notify => Exec['pam_auth_update']  }
  package { "libnss-sss": ensure => absent }
  package { "libsss-sudo": ensure => absent }
  ->
  # Remove legacy
  file { "/etc/pam_ldap.conf": ensure => absent } ->
  file { '/etc/libnss-ldap.conf': ensure => absent }
  
  package { "libpam-pwquality": ensure => absent, notify => Exec['pam_auth_update']  }
  package { "libpam-python": ensure => absent, notify => Exec['pam_auth_update']  }
  package { "libpam-mklocaluser": ensure => absent, notify => Exec['pam_auth_update']  }
  package { "libpam-ccreds": ensure => absent, notify => Exec['pam_auth_update']  }
  package { "nsscache": ensure => absent }
  package { "libnss-db": ensure => absent }
  package { "libnss-cache": ensure => absent }
  package { "libpam-ldapd": ensure => absent, notify => Exec['pam_auth_update']  }
  package { "libnss-ldapd": ensure => absent }
  package { "nslcd": ensure => absent }
  package { "nscd": ensure => absent }
  package { "libpam-ldap": ensure => absent, notify => Exec['pam_auth_update'] }
  package { "libnss-ldap": ensure => absent }
  
  ini_setting { "/etc/samba/smb.conf -> global -> idmap config *:range":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "idmap config *:range",
    value => "1000000-2000000"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> idmap config *:backend":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "idmap config *:backend",
    value => $algorithmic_ids ? { true  => "rid", false => "ad" }
  }

  ini_setting { "/etc/samba/smb.conf -> global -> server role":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "server role",
    value => "member server"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> workgroup":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "workgroup",
    value => "$workgroup"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> security":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "security",
    value => "ads"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> netbios name":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "netbios name",
    value => "$netbios_name"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> realm":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "realm",
    value => "$realm"
  }
  ->
  ini_setting { "/etc/samba/smb.conf -> global -> kerberos method":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "kerberos method",
    value => "system keytab"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> template homedir":
    ensure => $algorithmic_ids ? { true => present, default => absent },
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "template homedir",
    value => "$fallback_homedir"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> template shell":
    ensure => $algorithmic_ids ? { true => present, default => absent },
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "template shell",
    value => "$override_shell"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> winbind use default domain":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "winbind use default domain",
    value => "yes"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> winbind nss info":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "winbind nss info",
    value => $algorithmic_ids ? { true  => "template", false => "rfc2307" }
  }

  ini_setting { "/etc/samba/smb.conf -> global -> winbind refresh tickets":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "winbind refresh tickets",
    value => "yes"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> client ldap sasl wrapping":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "client ldap sasl wrapping",
    value => "seal"
  }


  # This is only member server
  ini_setting { "/etc/samba/smb.conf -> global -> domain master":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "domain master",
    value => "no"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> local master":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "local master",
    value => "no"
  }


  # How to map ACL-s
  ini_setting { "/etc/samba/smb.conf -> global -> vfs objects":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "vfs objects",
    value => "acl_xattr"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> map acl inherit":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "map acl inherit",
    value => "yes"
  }

  ini_setting { "/etc/samba/smb.conf -> global -> store dos attributes":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "global",
    setting => "store dos attributes",
    value => "yes"
  }


  file_line { "nsswitch-passwd":
      path => "/etc/nsswitch.conf",
      match => "^passwd:",
      line => "passwd: compat winbind"
  }

  file_line { "nsswitch-group":
      path => "/etc/nsswitch.conf",
      match => "^group:",
      line => "group: compat winbind"
  }

  file_line { "nsswitch-shadow":
      path => "/etc/nsswitch.conf",
      match => "^shadow:",
      line => "shadow: compat winbind"
  }

  file_line { "nsswitch-netgroup":
      path => "/etc/nsswitch.conf",
      match => "^netgroup:",
      line => "netgroup: compat"
  }

}
