package EBTST::Main::Gnuplot;

use warnings;
use strict;
use DateTime;
use List::MoreUtils qw/zip/;
use Chart::Gnuplot;

my $PI = 3.14159265;

sub _deg2rad { return $_[0] * $PI/180; }

sub _quantize {
    my ($limit, $xdata, $dsets) = @_;

    return $xdata, $dsets if @$xdata <= $limit;

    my $graph_type = (caller 1)[3];
    $graph_type =~ s/.*::(\w+)_chart$/$1/;

    ## we draw a point every X amount of time. @intervals contains the latest date for notes to be in a given point
    ## ie the first point represents the note at (or just before) $intervals[0]

    ## keep the first $limit/2 as-is, regular intervals for the other half
    my $first_dt = DateTime->new (zip @{[ qw/year month day hour minute second/ ]}, @{[ split /[ :-]/, $xdata->[$limit/2-1] ]})->epoch;
    my $last_dt  = DateTime->new (zip @{[ qw/year month day hour minute second/ ]}, @{[ split /[ :-]/, $xdata->[-1]         ]})->epoch;

    my @new_xdata = @$xdata[0 .. $limit/2-1];
    my @new_dsets;
    foreach my $dset_idx (0 .. $#$dsets) {
        @{ $new_dsets[$dset_idx] } = @{ $dsets->[$dset_idx] }[0 .. $limit/2-1];
    }

    my @intervals;
    my $interval_duration = ($last_dt - $first_dt) / int (($limit+1)/2);
    foreach my $idx (1 .. ($limit+1)/2) {
        my ($S,$M,$H,$d,$m,$y) = gmtime $first_dt + $interval_duration * $idx;
        push @intervals, sprintf '%d-%02d-%02d %02d:%02d:%02d', 1900+$y, 1+$m, $d, $H, $M, $S;
    }

    my @last_pushed;
    my $last_idx = int $limit/2;
    OUTER:
    foreach my $limit_date (@intervals) {
        ## if a lot of time has passed, $cur_xdata could be greater than this $limit_date
        ## (never true in the first iteration)
        my $cur_xdata = $xdata->[$last_idx];
        if (1 == ($cur_xdata cmp $limit_date)) {
            ## push $limit_date to @new_xdata and...
            push @new_xdata, $limit_date;
            foreach my $dset_idx (0 .. $#$dsets) {
                if ('bartime' eq $graph_type) {
                    ## ...each last pushed value to each datasets, so the bartime graphs don't have any gaps
                    push @{ $new_dsets[$dset_idx] }, $last_pushed[$dset_idx];
                } else {
                    ## ...undef to each dataset
                    push @{ $new_dsets[$dset_idx] }, undef;
                }
            }

            next;
        }

        while (1) {
            if ($last_idx > $#$xdata) {
                ## at this point:
                ## - $limit_date should be eq $intervals[-1];
                ## - $cur_xdata should be undef
                if ($limit_date ne $intervals[-1]) {
                    warn "about to exit loop but limit_date ($limit_date) isn't the last elem in intervals ($intervals[-1])";
                }
                if (defined $cur_xdata) {
                    warn "about to exit loop but cur_xdata is defined ($cur_xdata)";
                }
                last OUTER;
            }
            if (1 == ($cur_xdata cmp $limit_date)) {
                ## push a point to @new_xdata and to the datasets
                push @new_xdata, $xdata->[ $last_idx-1 ];
                foreach my $dset_idx (0 .. $#$dsets) {
                    push @{ $new_dsets[$dset_idx] }, $dsets->[$dset_idx][ $last_idx-1 ];
                    $last_pushed[$dset_idx] = $dsets->[$dset_idx][ $last_idx-1 ];
                }

                last;
            }
            $last_idx++;
            $cur_xdata = $xdata->[$last_idx];
        }
    }
    ## at this point, $last_idx should be == (1 + $#$xdata) == @$xdata
    if ($last_idx != @$xdata) {
        warn sprintf "premature exit from _quantize loop, last_idx (%s) xdata size (%s)", $last_idx//'<undef>', scalar @$xdata;
    }

    ## push last point to @new_xdata and to the datasets
    push @new_xdata, $xdata->[ $last_idx-1 ];
    foreach my $dset_idx (0 .. $#$dsets) {
        push @{ $new_dsets[$dset_idx] }, $dsets->[$dset_idx][ $last_idx-1 ];
    }

    ## check that @new_xdata and the new datasets have the same number of points
    my $npoints = @new_xdata;
    foreach my $dset_idx (0 .. $#$dsets) {
        if ($npoints != @{ $new_dsets[$dset_idx] }) {
            warn sprintf "new pointset $dset_idx has %d points instead of \@new_xdata's $npoints", scalar @{ $new_dsets[$dset_idx] };
        }
    }

    return \@new_xdata, \@new_dsets;
}

sub line_chart {
    my (%args) = @_;

    ## showing a lot of points is both cpu- and memory-intensive
    my ($xdata, $psets) = _quantize 10000, $args{'xdata'}, [ map { $_->{'points'} } @{ $args{'dsets'} } ];

    my %gp_dset_args = (
        xdata    => $xdata,
        style    => 'lines',
        linetype => 'solid',
        timefmt  => '%Y-%m-%d %H:%M:%S',
    );

    my @gp_dsets;
    foreach my $dset_idx (0 .. $#{ $args{'dsets'} }) {
        push @gp_dsets, Chart::Gnuplot::DataSet->new (
            %gp_dset_args,
            ydata => $psets->[$dset_idx],
            title => $args{'dsets'}[$dset_idx]{'title'},
            color => $args{'dsets'}[$dset_idx]{'color'},
        );
    }

    my $gp = Chart::Gnuplot->new (
        encoding  => 'utf8',
        terminal  => 'svg fsize 9',
        #imagesize => '800, 600',
        output    => $args{'output'},
        title     => $args{'title'},
        #xlabel    => 'Time',
        #ylabel    => 'Notes',
        timeaxis  => 'x',
        #bg        => 'white',
        ($args{'logscale'} ? (logscale => $args{'logscale'}) : ()),
        ($args{'yrange'} ? (yrange => $args{'yrange'}) : ()),
        grid => {
            type  => 'dot',
            width => 1,
            color => 'grey',
        },
        xtics => {
            labelfmt => '%Y-%m-%d',
            rotate   => 90,
            offset   => '0, -5',
        },
        legend => {
            position => 'bmargin left',
            width    => 1,
            align    => 'right',
            order    => 'horizontal',
            border   => { width => 1 },
        },
    );
    $gp->plot2d (@gp_dsets);
}

## the datasets must be in order, nearest to the zero line first
sub bar_chart {
    my (%args) = @_;

    my %gp_dset_args = (
        xdata    => [ 0..$#{ $args{'labels'} } ],
        style    => 'boxes',
        linetype => 'solid',
    );

    my @gp_dsets;
    my @acum;  ## we need to sum values, to make the illusion to create stacked boxes (actually they are tall ones, placed behind the smaller ones)
    foreach my $dset (@{ $args{'dsets'} }) {
        $acum[$_] += $dset->{'points'}[$_]//0 for 0..$#{ $dset->{'points'} };
        unshift @gp_dsets, Chart::Gnuplot::DataSet->new (
            %gp_dset_args,
            ydata    => [ @acum ],
            title    => $dset->{'title'},
            color    => $dset->{'color'},
            using    => 2,
            linetype => 'solid',
        );
    }
    my @labels;
    foreach my $idx (0..$#{ $args{'labels'} }) {
        push @labels, sprintf '"%s" %d', $args{'labels'}[$idx], $idx;
    }
    my $labels_rotate = $args{'labels_rotate'} // 0;
    my $label_y_offset = -3.5 * sin _deg2rad $labels_rotate;
    my $labels_offset = "0, $label_y_offset";

    my $gp = Chart::Gnuplot->new (
        encoding     => 'utf8',
        terminal     => 'svg fsize 9',
        #imagesize   => '800, 600',
        output       => $args{'output'},
        title        => $args{'title'},
        boxwidth     => '0.75 absolute',
        'style fill' => ($args{'bar_border'} ? 'solid 1 border lt -1' : 'solid 1'),
        yrange       => [ 0, '*' ],
        grid => {
            type   => 'dot',
            width  => 1,
            color  => 'grey',
            xlines => 'off',
        },
        xtics => {
            labels => \@labels,
            rotate => $labels_rotate,
            offset => $labels_offset,
        },
        legend => {
            position => 'rmargin top',
            width    => 1,
            align    => 'right',
            order    => 'vertical invert',  ## 'invert' doesn't seem to work with 'horizontal', and we need it since we plot the datasets in reverse order
            border => {
                width => 1,
            },
        },
    );
    $gp->plot2d (@gp_dsets);
}

## the datasets must be in order, nearest to the zero line first
sub bartime_chart {
    my (%args) = @_;

    ## showing a lot of boxes is slow
    my ($xdata, $psets) = _quantize 500, $args{'xdata'}, [ map { $_->{'points'} } @{ $args{'dsets'} } ];

    ## transform into percent
    if ($args{'percent'}) {
        my @totals;
        foreach my $idx (0 .. $#$xdata) {
            foreach my $dset_idx (0 .. $#{ $args{'dsets'} }) {
                next unless defined $psets->[$dset_idx][$idx];
                $totals[$idx] += $psets->[$dset_idx][$idx];
            }
        }

        foreach my $dset_idx (0 .. $#{ $args{'dsets'} }) {
            foreach my $idx (0..$#{ $psets->[$dset_idx] }) {
                next unless $totals[$idx];
                $psets->[$dset_idx][$idx] = 100 * $psets->[$dset_idx][$idx] / $totals[$idx];
            }
        }
    }

    my %gp_dset_args = (
        xdata    => $xdata,
        style    => 'boxes',
        linetype => 'solid',
        timefmt  => '%Y-%m-%d %H:%M:%S',
    );

    my @gp_dsets;
    my @acum;  ## we need to sum values, to make the illusion of creating stacked boxes (actually they are tall ones, placed behind the smaller ones)
    foreach my $dset_idx (0 .. $#{ $args{'dsets'} }) {
        $acum[$_] += $psets->[$dset_idx][$_]//0 for 0..$#{ $psets->[$dset_idx] };
        unshift @gp_dsets, Chart::Gnuplot::DataSet->new (
            %gp_dset_args,
            ydata    => [ @acum ],
            title    => $args{'dsets'}[$dset_idx]{'title'},
            color    => $args{'dsets'}[$dset_idx]{'color'},
            using    => '1:3',
            linetype => 'solid',
        );
    }

    my $gp = Chart::Gnuplot->new (
        encoding     => 'utf8',
        terminal     => 'svg fsize 9',
        #imagesize   => '800, 600',
        output       => $args{'output'},
        title        => $args{'title'},
        timeaxis  => 'x',
        #boxwidth     => '0.75 absolute',
        'style fill' => ($args{'bar_border'} ? 'solid 1 border lt -1' : 'solid 1'),
        ($args{'yrange'} ? (yrange => $args{'yrange'}) : $args{'percent'} ? (yrange => [ 0, 100 ]) : ()),
        grid => {
            type   => 'dot',
            width  => 1,
            color  => 'grey',
            xlines => 'off',
        },
        xtics => {
            labelfmt => '%Y-%m-%d',
            rotate   => 90,
            offset   => '0, -5',
        },
        legend => {
            position => 'rmargin top',
            width    => 1,
            align    => 'right',
            order    => 'vertical invert',  ## 'invert' doesn't seem to work with 'horizontal', and we need it since we plot the datasets in reverse order
            border => {
                width => 1,
            },
        },
    );
    $gp->plot2d (@gp_dsets);
}

1;
