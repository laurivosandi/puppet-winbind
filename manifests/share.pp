define winbind::share(
    $path,
    $available = true,
    $read_only = true,
    $writable = false,
    $valid_groups = [],
    $valid_users = [],
    $public = false, # same as guest ok
) {
  $valid_objects = !empty($valid_groups) or !empty($valid_users)
  
  ini_setting { "/etc/samba/smb.conf -> $title -> valid users":
    ensure => $valid_objects ? { true => "present", false => "absent" },
    path => "/etc/samba/smb.conf",
    section => "$title",
    setting => "valid users",
    value => inline_template("<%= scope.lookupvar('valid_users').map{|j| '\"'+j+'\"'}.join(' ') %> <%= scope.lookupvar('valid_groups').map{|j| '@\"'+j+'\"'}.join(' ') %>"),
  }

  ini_setting { "/etc/samba/smb.conf -> $title -> path":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "$title",
    setting => "path",
    value => "$path"
  }

  ini_setting { "/etc/samba/smb.conf -> $title -> public":
    ensure => present,
    path => "/etc/samba/smb.conf",
    section => "$title",
    setting => "public",
    value => $public ? { true => "yes", false => "no" }
  }
}
