# SUSE's openQA tests
#
# Copyright © 2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: openSUSE Welcome should auto-launch on GNOME/KDE/XFCE Sessions
#          Disable auto-launch on next boot and close application
# Maintainer: Dominique Leuenberger <dimstar@suse.de>

use base "x11test";
use strict;
use warnings;
use testapi;
use utils;
use x11utils 'untick_welcome_on_next_startup';

sub run {
    assert_screen("opensuse-welcome");
    untick_welcome_on_next_startup;
    # Can I haz IP v6 localhost?
    assert_script_run 'ping -c 1 0:0:0:0:0:0:0:1';
}

sub test_flags {
    return {milestone => 1};
}

1;
