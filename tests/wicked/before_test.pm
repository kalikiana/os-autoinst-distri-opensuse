# SUSE's openQA tests
#
# Copyright © 2017-2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Do basic checks to make sure system is ready for wicked testing
# Maintainer: Anton Smorodskyi <asmorodskyi@suse.com>

use base 'wickedbase';
use strict;
use testapi;
use utils qw(zypper_call systemctl);
use network_utils qw(iface setup_static_network);

sub run {
    my ($self) = @_;
    $self->select_serial_terminal;
    my $iface                  = iface();
    my $enable_command_logging = 'export PROMPT_COMMAND=\'logger -t openQA_CMD "$(history 1 | sed "s/^[ ]*[0-9]\+[ ]*//")"\'';
    my $escaped                = $enable_command_logging =~ s/'/'"'"'/gr;
    assert_script_run("echo '$escaped' >> /root/.bashrc");
    assert_script_run($enable_command_logging);
    systemctl("stop " . opensusebasetest::firewall);
    systemctl("disable " . opensusebasetest::firewall);
    assert_script_run('[ -z "$(coredumpctl -1 --no-pager --no-legend)" ]');
    record_info('INFO', 'Setting debug level for wicked logs');
    assert_script_run('sed -e "s/^WICKED_DEBUG=.*/WICKED_DEBUG=\"all\"/g" -i /etc/sysconfig/network/config');
    assert_script_run('sed -e "s/^WICKED_LOG_LEVEL=.*/WICKED_LOG_LEVEL=\"debug\"/g" -i /etc/sysconfig/network/config');
    assert_script_run('cat /etc/sysconfig/network/config');
    #preparing directories for holding config files
    assert_script_run('mkdir -p /data/{static_address,dynamic_address}');
    setup_static_network(ip => $self->get_ip(type => 'host', netmask => 1));
    record_info('INFO', 'Checking that network service is up');
    systemctl('is-active network');
    systemctl('is-active wicked');

    if (check_var('IS_WICKED_REF', '1')) {
        record_info('INFO', 'Setup DHCP server');
        zypper_call('--quiet in dhcp-server', timeout => 200);
        $self->get_from_data('wicked/dhcp/dhcpd.conf', '/etc/dhcpd.conf');
        assert_script_run("sed \'s/^DHCPD_INTERFACE=.*/DHCPD_INTERFACE=\"$iface\"/g\' -i /etc/sysconfig/dhcpd");
        systemctl 'enable dhcpd.service';
        systemctl 'start dhcpd.service';
    }
    if (check_var('WICKED', 'basic')) {
        $self->get_from_data('wicked/check_interfaces.sh', '/data/check_interfaces.sh', executable => 1);
        assert_script_run("rcwickedd restart");
        unless (get_var('IS_WICKED_REF')) {
            # Remove previous static config and leave dynamic one, only for SUT
            assert_script_run("rm /etc/sysconfig/network/ifcfg-$iface");
            $self->get_from_data("wicked/dynamic_address/ifcfg-eth0", "/etc/sysconfig/network/ifcfg-$iface");
        }
    }
    elsif (check_var('WICKED', 'advanced') || check_var('WICKED', 'startandstop')) {
        assert_script_run("rcwickedd restart");
        record_info('INFO', 'Setup OpenVPN');
        zypper_call('--quiet in openvpn', timeout => 200);
    }
}

sub test_flags {
    return {fatal => 1, milestone => 1};
}

1;
