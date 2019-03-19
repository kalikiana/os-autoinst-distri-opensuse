# SUSE's openQA tests
#
# Copyright © 2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Set up static routes from wicked XML files
# Maintainer: Anton Smorodskyi <asmorodskyi@suse.com>
#             Jose Lausuch <jalausuch@suse.com>
#             Clemens Famulla-Conrad <cfamullaconrad@suse.de>


use base 'wickedbase';
use strict;
use warnings;
use testapi;
use network_utils 'iface';
use utils 'file_content_replace';

sub run {
    my ($self) = @_;
    my $iface  = iface();
    my $config = '/data/static_address/static-addresses-and-routes.xml';
    record_info('Info', 'Set up static routes from wicked XML files');
    $self->get_from_data('wicked/static_address/static-addresses-and-routes.xml', $config);
    file_content_replace($config, '--sed-modifier' => 'g', xxx => $iface);
    $self->wicked_command('ifup --ifconfig /data/static_address/static-addresses-and-routes.xml', $iface);
    $self->assert_wicked_state(ping_ip => '10.0.2.2', iface => $iface);
}


1;
