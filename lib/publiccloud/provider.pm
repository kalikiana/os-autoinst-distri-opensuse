# SUSE's openQA tests
#
# Copyright © 2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Base helper class for public cloud
#
# Maintainer: Clemens Famulla-Conrad <cfamullaconrad@suse.de>

package publiccloud::provider;
use testapi;
use Mojo::Base -base;
use publiccloud::instance;
use Data::Dumper;

has key_id     => undef;
has key_secret => undef;
has region     => undef;
has prefix     => 'openqa';

=head1 METHODS

=head2 init

Needs provider specific credentials, e.g. key_id, key_secret, region.

=cut
sub init {
    die('init() isn\'t implemented');
}


=head2 find_img

Retrieves the image-id by given image C<name>.

=cut
sub find_img {
    die('find_image() isn\'t implemented');
}

=head2 upload_image

Upload a image to the CSP. Required parameter is the
location of the C<image> file.

Retrieves the image-id after upload or die.

=cut
sub upload_image {
    die('find_image() isn\'t implemented');
}


=head2 ipa

  ipa(instance_type => <string>, cleanup => <bool>, tests => <string>, timeout => <seconds>, results_dir => <string>, distro => <string>);

Call ipa tool and retrieves a hashref as result. Do not die if ipa call exit with error.
  $result_hash = {
        instance    => <publiccloud:instance>,    # instance object
        logfile     => <string>,                  # the pytest logfile
        results     => <string>,                  # json results file
        tests       => <int>,                     # total number of tests
        pass        => <int>,                     # successful tests
        skip        => <int>,                     # skipped tests
        fail        => <int>,                     # number of failed tests
        error       => <int>,                     # number of errors
  };

=cut
sub ipa {
    die('ipa() isn\'t implemented');
}

=head2 parse_ipa_output

Parse the output from ipa command and retrieves instance-id, ip and logfile names.

=cut
sub parse_ipa_output {
    my ($self, $output) = @_;
    my $ret = {};
    my $instance_id;
    my $ip;

    for my $line (split(/\r?\n/, $output)) {
        if ($line =~ m/^ID of instance: (\S+)$/) {
            $ret->{instance_id} = $1;
        }
        elsif ($line =~ m/^Terminating instance (\S+)$/) {
            $ret->{instance_id} = $1;
        }
        elsif ($line =~ m/^IP of instance: (\S+)$/) {
            $ret->{ip} = $1;
        }
        elsif ($line =~ m/^Created log file (\S+)$/) {
            $ret->{logfile} = $1;
        }
        elsif ($line =~ m/^Created results file (\S+)$/) {
            $ret->{results} = $1;
        }
        elsif ($line =~ m/tests=(\d+)\|pass=(\d+)\|skip=(\d+)\|fail=(\d+)\|error=(\d+)/) {
            $ret->{tests} = $1;
            $ret->{pass}  = $2;
            $ret->{skip}  = $3;
            $ret->{fail}  = $4;
            $ret->{error} = $5;
        }
    }

    for my $k (qw(instance_id ip logfile results tests pass skip fail error)) {
        return unless (exists($ret->{$k}));
    }
    return $ret;
}

=head2 create_ssh_key

Creates an ssh keypair in a given file path by $args{ssh_private_key_file}

=cut
sub create_ssh_key {
    my ($self, %args) = @_;
    if (script_run('test -f ' . $args{ssh_private_key_file}) != 0) {
        assert_script_run('SSH_DIR=`dirname ' . $args{ssh_private_key_file} . '`; mkdir -p $SSH_DIR');
        assert_script_run('ssh-keygen -b 2048 -t rsa -q -N "" -f ' . $args{ssh_private_key_file});
    }
}

=head2 run_ipa

called by childs within ipa function

=cut
sub run_ipa {
    my ($self, %args) = @_;
    $args{cleanup}              //= 1;
    $args{ssh_private_key_file} //= '.ssh/id_rsa';
    $args{tests}                //= '';
    $args{timeout}              //= 60 * 30;
    $args{results_dir}          //= 'ipa_results';
    $args{distro}               //= 'sles';
    $args{tests} =~ s/,/ /g;

    $self->create_ssh_key(ssh_private_key_file => $args{ssh_private_key_file});

    my $cmd = 'ipa --no-color test ' . $args{provider};
    $cmd .= ' --debug ';
    $cmd .= "--distro " . $args{distro} . " ";
    $cmd .= '--region "' . $self->region . '" ';
    $cmd .= '--results-dir "' . $args{results_dir} . '" ';
    $cmd .= ($args{cleanup}) ? '--cleanup ' : '--no-cleanup ';
    $cmd .= '--instance-type "' . $args{instance_type} . '" ';
    $cmd .= '--service-account-file "' . $args{credentials_file} . '" ' if ($args{credentials_file});
    $cmd .= "--access-key-id '" . $args{key_id} . "' "                  if ($args{key_id});
    $cmd .= "--secret-access-key '" . $args{key_secret} . "' "          if ($args{key_secret});
    $cmd .= "--ssh-key-name '" . $args{key_name} . "' "                 if ($args{key_name});
    $cmd .= '-u ' . $args{user} . ' '                                   if ($args{user});
    $cmd .= '--ssh-private-key-file "' . $args{ssh_private_key_file} . '" ';

    if (exists($args{running_instance_id})) {
        $cmd .= '--running-instance-id "' . $args{running_instance_id} . '" ';
    } else {
        $cmd .= '--image-id "' . $args{image_id} . '" ';
    }
    $cmd .= $args{tests};
    record_info("ipa cmd", $cmd);

    my $output = script_output($cmd . ' 2>&1', $args{timeout}, proceed_on_failure => 1);
    my $ipa = $self->parse_ipa_output($output);
    die($output) unless (defined($ipa));

    my $instance = $ipa->{instance} = publiccloud::instance->new(
        public_ip   => $ipa->{ip},
        instance_id => $ipa->{instance_id},
        username    => $args{user},
        ssh_key     => $args{ssh_private_key_file},
        provider    => $self
    );
    delete($ipa->{instance_id});
    delete($ipa->{ip});

    $self->{running_instances} //= {};
    if ($args{cleanup}) {
        delete($self->{running_instances}->{$instance->instance_id});
    } else {
        $self->{running_instances}->{$instance->instance_id} = $instance;
    }

    return $ipa;
}

=head2 get_image_id

    get_image_id([$img_url]);

Retrieves the CSP image id if exists, otherwise exception is thrown.
The given C<$img_url> is optional, if not present it retrieves from
PUBLIC_CLOUD_IMAGE_LOCATION.
=cut
sub get_image_id {
    my ($self, $img_url) = @_;
    $img_url //= get_required_var('PUBLIC_CLOUD_IMAGE_LOCATION');
    my ($img_name) = $img_url =~ /([^\/]+)$/;
    $self->{image_cache} //= {};
    return $self->{image_cache}->{$img_name} if ($self->{image_cache}->{$img_name});
    my $image_id = $self->find_img($img_name);
    die("Image $img_name is not available in the cloud provider") unless ($image_id);
    $self->{image_cache}->{$img_name} = $image_id;
    return $image_id;
}

=head2 create_instance

Creates an instance on the public cloud provider. Retrieves a publiccloud::instance
object.

C<image>         defines the image_id to create the instance.
C<instance_type> defines the flavor of the instance. If not specified, it will load it
                     from PUBLIC_CLOUD_INSTANCE_TYPE.

=cut
sub create_instance {
    my ($self, %args) = @_;
    $args{instance_type} //= get_var('PUBLIC_CLOUD_INSTANCE_TYPE');
    $args{image} //= $self->get_image_id();

    record_info('INFO', "Creating instance $args{instance_type} from $args{image} ...");
    my $ipa = $self->ipa(
        instance_type => $args{instance_type},
        cleanup       => 0,
        image_id      => $args{image}
    );
    return $ipa->{instance};
}

=head2 destroy_instance

Destroy a instance previously created with this provider. Require a C<publiccloud::instance> object.
=cut
sub destroy_instance {
    my ($self, $instance) = @_;
    $self->ipa(cleanup => 1, running_instance_id => $instance->instance_id);
}

=head2 cleanup

This method is called called after each test on failure or success.

=cut
sub cleanup {
    my ($self) = @_;

    for my $i (keys(%{$self->{running_instances}})) {
        my $instance = $self->{running_instances}->{$i};
        record_info('INFO', 'Destroy instance ' . $instance->instance_id . '(' . $instance->public_ip . ')');
        $self->destroy_instance($instance);
    }
}

1;
