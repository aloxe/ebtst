package EBT2;

use warnings;
use strict;
use Storable qw/dclone/;
use Config::General;

sub _work_dir {
    my $work_dir;

    $work_dir = File::Spec->catfile ($ENV{'HOME'}, '.ebt');
    if (!mkdir $work_dir) {
        if (17 != $!) {   ## "File exists"
            die "Couldn't create work directory: '$work_dir': $!\n";
        }
    }

    return $work_dir;
}

## set up configuration before use'ing other EBT2 modules
my $work_dir;
our %config;
BEGIN {
    $work_dir = _work_dir;
    my $cfg_file = File::Spec->catfile ($work_dir, 'ebt2.cfg');
    -r $cfg_file or die "Can't find configuration file '$cfg_file'\n";
    %config = Config::General->new (-ConfigFile => $cfg_file, -IncludeRelative => 1, -UTF8 => 1)->getall;
}

use EBT2::Data;
use EBT2::Stats;

our $progress_every = 5000;
## build empty hashes with all possible combinations
#our %combs_pc_cc;
our %combs_pc_cc_val;
our %combs_pc_cc_sig;
our %combs_pc_cc_val_sig;
#our %combs_plate_cc_val_sig;
our %all_plates;
foreach my $v (keys %{ $config{'sigs'} }) {
    foreach my $cc (keys %{ $config{'sigs'}{$v} }) {
        foreach my $plate (keys %{ $config{'sigs'}{$v}{$cc} }) {
            my $pc = substr $plate, 0, 1;

            #$combs_pc_cc{"$pc$cc"} = undef;

            my $k_pcv = sprintf '%s%s%03d', $pc, $cc, $v;
            $combs_pc_cc_val{$k_pcv} = undef;

            my $sig = [ split /, */, $config{'sigs'}{$v}{$cc}{$plate} ];
            foreach my $s (@$sig) {
                $s =~ /^([A-Z]+)/ or die "invalid signature '$s' found in configuration, v ($v) cc ($cc) plate ($plate)";
                $s = $1;

                $combs_pc_cc_sig{'any'}{"$pc$cc"} = undef;
                $combs_pc_cc_sig{$s}{"$pc$cc"} = undef;

                my $k_pcv = sprintf '%s%s%03d', $pc, $cc, $v;
                $combs_pc_cc_val_sig{'any'}{$k_pcv} = undef;
                $combs_pc_cc_val_sig{$s}{$k_pcv} = undef;

                #$k_pcv = sprintf '%s%s%03d', $plate, $cc, $v;
                #$combs_plate_cc_val_sig{'any'}{$k_pcv} = undef;
                #$combs_plate_cc_val_sig{$s}{$k_pcv} = undef;
            }

            push @{ $all_plates{$cc}{$v} }, $plate;
        }
    }
}

sub new {
    my ($class, %args) = @_;

    my %attrs;
    $attrs{$_} = delete $args{$_} for qw/db/;
    %args and die sprintf 'unrecognized parameters: %s', join ', ', sort keys %args;

    #exists $attrs{'foo'} or die "need a 'foo' parameter";
    $attrs{'db'} //= File::Spec->catfile ($work_dir, 'db2');

    bless {
        data  => EBT2::Data->new (db => $attrs{'db'}),
        stats => EBT2::Stats->new,
    }, $class;
}

sub ebt_lang {
    return substr +($ENV{'EBT_LANG'} || $ENV{'LANG'} || $ENV{'LANGUAGE'} || 'en'), 0, 2;
}

sub flag {
    my ($self, $iso3166) = @_;
    my $flag_txt;

    if (grep { $_ eq $iso3166 } values %{ EBT2->countries }, values %{ EBT2->printers }) {
        $flag_txt = ":flag-$iso3166:";
    } else {
        $flag_txt = sprintf '[img]https://dserrano5.es/ebtdev/ebtst/images/%s.gif[/img]', $iso3166;
    }

    return $flag_txt;
}

sub load_notes        { my ($self, @args) = @_; $self->{'data'}->load_notes (@args); return $self; }
sub load_hits         { my ($self, @args) = @_; $self->{'data'}->load_hits  (@args); return $self; }
sub load_db           { my ($self)        = @_; $self->{'data'}->load_db; return $self; }
sub has_notes         { my ($self)        = @_; $self->{'data'}->has_notes; }
sub has_hits          { my ($self)        = @_; $self->{'data'}->has_hits; }
sub has_bad_notes     { my ($self)        = @_; $self->{'data'}->has_bad_notes; }
sub whoami            { my ($self)        = @_; $self->{'data'}->whoami; }
sub set_checked_boxes { my ($self, @cbs)  = @_; $self->{'data'}->set_checked_boxes (@cbs); }
sub get_checked_boxes { my ($self)        = @_; return $self->{'data'}->get_checked_boxes; }
sub set_progress_obj  { my ($self, $obj)  = @_; $self->{'progress'} = $obj; }
sub del_progress_obj  { my ($self, $obj)  = @_; delete $self->{'progress'}; }
sub set_logger        { my ($self, $log)  = @_; $self->{'log'} = $log; }
sub values            { return $config{'values'};     }
sub presidents        { return $config{'presidents'}; }

sub _log {
    my ($self, $prio, $msg) = @_;

    return unless $self->{'log'};
    my $user = (split m{/}, $self->{'data'}{'db'})[-2];   ## TODO: would need $self->{'user'} instead of this hack
    $self->{'log'}->$prio (sprintf '%s: %s', ($user // '<no user>'), $msg);
}

sub done_data {
    my ($self) = @_;

    my %done = map { $_ => undef } keys %{ $self->{'data'} };
    delete @done{qw/db whoami version eof has_hits has_notes has_bad_notes checked_boxes notes_pos/};
    my @done = keys %done;
    return @done;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my ($self, @args) = @_;
    my ($pkg, $field) = (__PACKAGE__, $AUTOLOAD);

    $field =~ s/${pkg}:://;
    return if $field eq 'DESTROY';
    if ($field =~ s/^get_//) {
        if (!$self->{'data'}{'notes'}) {
            $self->_log (warn => "'$field' was queried but there's no data");
            return undef;
        }

        ## temporary code for existing databases
        delete $self->{'data'}{'stats_version'};
        if (exists $self->{'data'}{$field}) {
            if ('HASH' ne ref $self->{'data'}{$field}) {
                #$self->_log (debug => "existing field ($field) is not a hashref: delete");
                delete $self->{'data'}{$field};
            } else {
                if (!exists $self->{'data'}{$field}{'version'}) {
                    #$self->_log (debug => "existing field ($field) is a versionless hashref: delete");
                    delete $self->{'data'}{$field};
                }
            }
        }

        if (exists $self->{'data'}{$field}) {
            if ($self->{'data'}{$field}{'version'}) {
                if (-1 != ($self->{'data'}{$field}{'version'} cmp $EBT2::Stats::STATS_VERSION)) {
                    #$self->_log (debug => "version of field ($field) ok, returning cached");
                    return ref $self->{'data'}{$field}{'data'} ? dclone $self->{'data'}{$field}{'data'} : $self->{'data'}{$field}{'data'};
                }
                #$self->_log (info => sprintf q{version '%s' of field '%s' is less than $STATS_VERSION '%s', recalculating},
                #    $self->{'data'}{$field}{'version'}, $field, $EBT2::Stats::STATS_VERSION);
            } else {
                ## shouldn't happen, since the temporary code above deletes these entries
                $self->_log (debug => "unversioned field ($field) exists, assume it is outdated");
            }
        } else {
            if (!$self->{'stats'}->can ($field)) {
                $self->_log (warn => "Method 'get_$field' called but field '$field' is unknown");
                return undef;
            }
            #$self->_log (debug => "field ($field) doesn't exist, let's go for it");
        }
        my $ret = $self->{'stats'}->$field ($self->{'progress'}, $self->{'data'}, @args);
        if (!keys %$ret) {
            $self->_log (warn => "Method 'get_$field' returned nothing");
            return undef;
        }
        foreach my $f (keys %$ret) {
            ## temporary code for existing databases
            if (exists $self->{'data'}{$f}) {
                if ('HASH' ne ref $self->{'data'}{$f}) {
                    delete $self->{'data'}{$f};
                } else {
                    if (!exists $self->{'data'}{$f}{'version'}) {
                        delete $self->{'data'}{$f};
                    }
                }
            }

            $self->{'data'}{$f}{'data'} = $ret->{$f};
            $self->{'data'}{$f}{'version'} = $EBT2::Stats::STATS_VERSION;
        }
        $self->{'data'}->write_db;
        return ref $self->{'data'}{$field}{'data'} ? dclone $self->{'data'}{$field}{'data'} : $self->{'data'}{$field}{'data'} if exists $self->{'data'}{$field};

    } elsif ($field =~ /^(countries|printers)$/) {
        ## close over %config - the quoted eval doesn't do it, resulting in 'Variable "%config" is not available'
        %config if 0;

        eval <<"EOF";
            *$field = sub {
                my (\$self, \$what) = \@_;
                if (\$what) {
                    return \$config{\$field}{\$what};
                } else {
                    return \$config{\$field};
                }
            };
EOF
        $@ and die "eval failed: $@\n";
        goto &$field;

    } elsif ($field =~ /^(printer_names)$/) {
        ## close over %config - the quoted eval doesn't do it, resulting in 'Variable "%config" is not available'
        %config if 0;

        eval <<"EOF";
            *$field = sub {
                my (\$self, \$what) = \@_;
                return \$config{\$field}{\$lang}{\$what};
            };
EOF
        $@ and die "eval failed: $@\n";
        goto &$field;

    } else {
        die "Can't call non existing method '$field'\n";
    }
}

1;




__END__

aqui el /tmp/ebt.pm:

package EBT;

use warnings;
use strict;
use File::Spec;

## $Id$
our $VERSION = (qw$Revision$)[-1];


################# CONSTANTS AND GLOBALS

my $primes_file   = File::Spec->catfile ($work_dir, 'prime-numbers');


## DATA METHODS

sub note_grep {
    my ($self, %filter) = @_;

    my $iter = $self->note_getter (interval => 'all', filter => \%filter, one_result_full_data => 0);
    return $iter->();
}





## this should go in the application, not in the module
sub note_evolution {
    my ($self, $interval, $filter, $group_by, $show_only, $output) = @_;

    ## no premature return, this always calculates data
    $self->{'note_evolution'} = [];

    my ($percent, $percent_shown);
    if ('count' ne $output) {
        if ('percent' eq $output) {
            $percent = 1;
        }
        if ('percent_shown' eq $output) {
            $percent_shown = 1;
        }
    }

    my $iter = $self->note_getter (interval => $interval, filter => $filter);
    while (my $chunk = $iter->()) {
        if (!defined $group_by) {
            push @{ $self->{'note_evolution'} }, {
                start_date => $chunk->{'start_date'},
                end_date   => $chunk->{'end_date'},
                val        => {
                    all => scalar @{ $chunk->{'notes'} },
                },
            };
            next;
        }

        my %group;
        foreach my $hr (@{ $chunk->{'notes'} }) {
            my $key;
            if ('cc' eq $group_by) {
                $key = substr $hr->{'serial'}, 0, 1;
            } elsif ('pc' eq $group_by) {
                $key = substr $hr->{'short_code'}, 0, 1;
            } elsif ('plate' eq $group_by) {
                $key = substr $hr->{'short_code'}, 0, 4;
            } elsif ('comb1' eq $group_by) {
                $key = sprintf '%s%s', (substr $hr->{'short_code'}, 0, 1), (substr $hr->{'serial'}, 0, 1);
            } elsif ('comb2' eq $group_by) {
                $key = sprintf '%s%s%s', (substr $hr->{'short_code'}, 0, 1), (substr $hr->{'serial'}, 0, 1), ($hr->{'value'});
            } elsif ('value' eq $group_by) {
                $key = $hr->{'value'};
            } elsif ('city' eq $group_by) {
                $key = $hr->{'city'};
            } elsif ('country' eq $group_by) {
                $key = $hr->{'country'};
            } elsif ('zip' eq $group_by) {
                $key = $hr->{'zip'};
            } elsif ('signature' eq $group_by) {
                $key = $hr->{'signature'};
            } else {   ## TODO: time/hour/min/sec? lat/long?
                die "Unknown 'group-by' value\n";
            }
            $group{$key}++;
        }

        if ($percent_shown) {
            ## delete from %group what we're not going to show
            foreach my $g (keys %group) {
                next if grep { $g =~ /^$_/ } @$show_only;
                delete $group{$g};
            }
        }
        my $total = (sum values %group)//0;

        my $show_pieces = {};
        foreach my $k (keys %group) {
            my $match;
            if ('value' eq $group_by) {
                $match = grep { $k == $_ } @$show_only;
            } else {
                $match = grep { $k =~ /^$_/ } @$show_only;
            }
            ## push (ie show) if @$show_only isn't defined OR if it's defined and there's match
            if (!@$show_only or $match) {
                my $v = $group{$k}//0;
                $percent||$percent_shown and $v = sprintf '%.2f', $v*100/$total;
                #push @show_pieces, 1==@$show_only ? ($v) : (join ':', $k, $v);
                $show_pieces->{$k} = $v;
            }
        }

        push @{ $self->{'note_evolution'} }, {
            start_date => $chunk->{'start_date'},
            end_date   => $chunk->{'end_date'},
            val        => $show_pieces,
        };
    }

    return $self;
}

1;
