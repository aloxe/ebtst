package EBTST;

use Mojo::Base 'Mojolicious';
use File::Spec;
use Config::General;
use Devel::Size qw/total_size/;
use DBI;
use EBT2;

my $work_dir = EBT2::_work_dir;
my $cfg_file = File::Spec->catfile ($work_dir, 'ebtst.cfg');
-r $cfg_file or die "Can't find configuration file '$cfg_file'\n";
our %config = Config::General->new (-ConfigFile => $cfg_file, -IncludeRelative => 1, -UTF8 => 1)->getall;

my $sess_dir                    = $config{'session_dir'}       // die "'session_dir' isn't configured";
my $user_data_basedir           = $config{'user_data_basedir'} // die "'user_data_basedir' isn't configured";
my $html_dir                    = $config{'html_dir'}    // File::Spec->catfile ($ENV{'BASE_DIR'}, 'public', 'stats');
my $statics_dir                 = $config{'statics_dir'} // File::Spec->catfile ($ENV{'BASE_DIR'}, 'public');
my $images_dir                  = File::Spec->catfile ($config{'statics_dir'} ? $config{'statics_dir'} : ($ENV{'BASE_DIR'}, 'public'), 'images');
my $session_expire              = $config{'session_expire'} // 30;
my $base_href                   = $config{'base_href'};
our @graphs_colors              = $config{'graphs_colors'} ? (split /[\s,]+/, $config{'graphs_colors'}) : ('blue', 'green', '#FFBF00', 'red', 'black');
my $max_rss_size                = $config{'max_rss_size'} // 150e3;
my $hypnotoad_listen            = $config{'hypnotoad_listen'} // 'http://localhost:3000'; $hypnotoad_listen = [ $hypnotoad_listen ] if 'ARRAY' ne ref $hypnotoad_listen;
my $hypnotoad_accepts           = $config{'hypnotoad_accepts'} // 1000;             ## Mojo::Server::Hypnotoad default
my $hypnotoad_keep_alive_requests = $config{'hypnotoad_keep_alive_requests'} // 25; ## Mojo::Server::Hypnotoad default
my $hypnotoad_is_proxy          = $config{'hypnotoad_is_proxy'} // 0;
my $hypnotoad_heartbeat_timeout = $config{'hypnotoad_heartbeat_timeout'} // 60;
my $base_parts = @{ Mojo::URL->new ($base_href)->path->parts };

sub helper_rss_process {
    my ($self) = @_;

    local $_;
    if (open my $fd, '<', "/proc/$$/status") {
        while (<$fd>) {
            next unless /^VmRSS:\s*(\d+)\s*kB/;
            close $fd;
            return $1;
        }
    } else {
        $self->app->log->warn ("helper_rss_process: open: '/proc/$$/status': $!");
    }
}

sub _inc {
    my ($coderef, $filename) = @_;

    return if $filename !~ m{EBTST/I18N/..\.pm};

    my $class = $filename;
    $class =~ s{/}{::}g;
    $class =~ s/\.pm$//;

    my $contents = q{
        package _CLASS;

        use Mojo::Base 'EBTST::I18N';
        use EBTST::I18N;

        EBTST::I18N::setup_lex +(split '::', __PACKAGE__)[-1], \our %Lexicon;

        1;
    };
    $contents =~ s/_CLASS/$class/;

    return \$contents;
}

sub bd_set_initial_stash {
    my $self = shift;

    my $al = $self->tx->req->content->headers->accept_language // ''; $ENV{'LANG'} = substr $al, 0, 2;  ## could be improved...
    $self->stash (base_href     => $base_href);
    $self->stash (checked_boxes => {});
    $self->stash (html_hrefs    => {});
    $self->stash (public_stats  => undef);
    $self->stash (has_notes     => undef);
    $self->stash (has_hits      => undef);
    $self->stash (has_bad_notes => undef);
    $self->stash (user          => undef);
    $self->stash (title         => undef);
    $self->stash (requested_url => $self->req->url->path->leading_slash (0)->to_string);
}

sub helper_ebt {
    my ($self) = @_;

    if (ref $self->stash ('ebt')) {
        my $ret = $self->stash ('ebt');
        return $ret;
    } else {
        die "Oops, this shouldn't happen";
    }
}

sub helper_color {
    my ($self, $num, $what) = @_;
    my $color;

    if ('notes' eq $what) {
        if (!$num)                             { $color = '#B0B0B0';
        } elsif ($num >=    1 and $num <=  49) { $color = $graphs_colors[0];
        } elsif ($num >=   50 and $num <=  99) { $color = $graphs_colors[1];
        } elsif ($num >=  100 and $num <= 499) { $color = $graphs_colors[2];
        } elsif ($num >=  500 and $num <= 999) { $color = $graphs_colors[3];
        } elsif ($num >= 1000)                 { $color = $graphs_colors[4];
        } else {
            die "Should not happen, num ($num) what ($what)";
        }
    } elsif ('hits' eq $what) {
        if (!$num)                         { $color = '#B0B0B0';
        } elsif ($num ==  1)               { $color = $graphs_colors[0];
        } elsif ($num ==  2)               { $color = $graphs_colors[1];
        } elsif ($num >=  3 and $num <= 4) { $color = $graphs_colors[2];
        } elsif ($num >=  5 and $num <= 9) { $color = $graphs_colors[3];
        } elsif ($num >= 10)               { $color = $graphs_colors[4];
        } else {
            die "Should not happen, num ($num) what ($what)";
        }
    } else {
        die "Don't know what to color";
    }

    return $color;
}

## only used from templates/main/help.html.ep, which uses a different mechanism for translations
sub helper_l2 {
    my ($self, $txt) = @_;

    my $ret = $self->l ($txt);
    return $ret if '_' ne substr $ret, 0, 1;

    my @save_langs = $self->stash->{i18n}->languages;
    $self->stash->{i18n}->languages ('en');
    $ret = $self->l ($txt);
    $self->stash->{i18n}->languages (@save_langs);

    return $ret;
}

## for the hit templates
sub helper_hit_partners {
    my ($self, $mode, $my_id, $partners, $partner_ids) = @_;

    my $before = 1;
    my @visible;
    foreach my $idx (0 .. $#$partners) {
        my $name = $partners->[$idx];
        my $id   = $partner_ids->[$idx];
        if ($id eq $my_id) { $before = 0; next; }
        if ($before) {
            if ('html' eq $mode) {
                push @visible,
                    (sprintf '<a href="https://en.eurobilltracker.com/profile/?user=%s">%s</a>', $id, $name),
                    '<img src="images/red_arrow.gif">';
            } elsif ('txt' eq $mode) {
                push @visible, sprintf "[color=darkred]%s[/color] [url=https://en.eurobilltracker.com/profile/?user=%s]%s[/url]", ($self->l ('from')), $id, $name;
            }
        } else {
            if ('html' eq $mode) {
                push @visible,
                    '<img src="images/blue_arrow.gif">',
                    (sprintf '<a href="https://en.eurobilltracker.com/profile/?user=%s">%s</a>', $id, $name);
            } elsif ('txt' eq $mode) {
                push @visible, sprintf "[color=darkblue]%s[/color] [url=https://en.eurobilltracker.com/profile/?user=%s]%s[/url]", ($self->l ('to')), $id, $name;
            }
        }
    }
    return join ' ', @visible;
}

sub ad_rss_sigquit {
    my ($self) = @_;

    my $rss = $self->rss_process or return;
    if ($rss > $max_rss_size) {
        $self->app->log->debug ("process $$ RSS is $rss Kb, sending SIGQUIT and closing connection");
        $self->res->headers->connection ('close');
        kill QUIT => $$;    ## hypnotoad-specific, breaks morbo
    } else { $self->app->log->debug ("process $$ RSS is $rss Kb"); }
    return;
}

## would put this into an after_dispatch hook, but $self->stash('ebt') doesn't seem to be available there
sub log_sizes {
    my ($log, $ebt) = @_;

    my %sizes = (
        ebt2 => (total_size $ebt),
        (map { $_ => total_size $ebt->{'data'}{$_} } keys %{ $ebt->{'data'} }),
    );

    foreach my $k (
        reverse
        sort { ($sizes{$a}) <=> ($sizes{$b}) }
        grep { $sizes{$_} > $sizes{'ebt2'}/100 and $sizes{$_} > 512*1024 }
        keys %sizes
    ) {
        $log->debug (sprintf '%35s: %6.0f Kb', $k, ($sizes{$k})/1024);
    }
}

## TODO: I don't think this is the right place for this code
sub helper_html_hrefs {
    my ($self) = @_;

    my %done_data;
    undef @done_data{ $self->ebt->done_data };

    my %html_hrefs;
    $html_hrefs{'information'}          = undef if exists $done_data{'activity'};
    $html_hrefs{'value'}                = undef if exists $done_data{'notes_by_value'};
    $html_hrefs{'countries'}            = undef if exists $done_data{'notes_by_cc'};
    $html_hrefs{'printers'}             = undef if exists $done_data{'notes_by_pc'};
    $html_hrefs{'locations'}            = undef if exists $done_data{'notes_by_city'};
    $html_hrefs{'travel_stats'}         = undef if exists $done_data{'travel_stats'};
    $html_hrefs{'huge_table'}           = undef if exists $done_data{'huge_table'};
    $html_hrefs{'short_codes'}          = undef if exists $done_data{'highest_short_codes'};
    $html_hrefs{'nice_serials'}         = undef if exists $done_data{'nice_serials'};
    $html_hrefs{'coords_bingo'}         = undef if exists $done_data{'coords_bingo'};
    $html_hrefs{'notes_per_year'}       = undef if exists $done_data{'notes_per_year'};
    $html_hrefs{'notes_per_month'}      = undef if exists $done_data{'notes_per_month'};
    $html_hrefs{'top_days'}             = undef if exists $done_data{'top10days'};
    $html_hrefs{'time_analysis_bingo'}  = undef if exists $done_data{'time_analysis'};
    $html_hrefs{'time_analysis_detail'} = undef if exists $done_data{'time_analysis'};
    $html_hrefs{'combs_bingo'}          = undef if exists $done_data{'notes_by_combination'};
    $html_hrefs{'combs_detail'}         = undef if exists $done_data{'notes_by_combination'};
    $html_hrefs{'plate_bingo'}          = undef if exists $done_data{'plate_bingo'};
    $html_hrefs{'hit_list'}             = undef if exists $done_data{'hit_list'};
    $html_hrefs{'hit_times_bingo'}      = undef if exists $done_data{'hit_times'};
    $html_hrefs{'hit_times_detail'}     = undef if exists $done_data{'hit_times'};
    $html_hrefs{'hit_locations'}        = undef if exists $done_data{'notes_by_city'} and exists $done_data{'hit_list'};
    $html_hrefs{'hit_analysis'}         = undef if exists $done_data{'hit_analysis'};
    $html_hrefs{'hit_summary'}          = undef if exists $done_data{'hit_summary'};
    $html_hrefs{'calendar'}             = undef if exists $done_data{'calendar'};

    return %html_hrefs;
}

sub startup {
    my ($self) = @_;

    push @INC, \&_inc;

    $self->app->config ({
        hypnotoad => {
            accepts           => $hypnotoad_accepts,
            keep_alive_requests => $hypnotoad_keep_alive_requests,
            listen            => $hypnotoad_listen,
            proxy             => $hypnotoad_is_proxy,
            heartbeat_timeout => $hypnotoad_heartbeat_timeout,
        }
    });

    ## In case of CSRF token mismatch, Mojolicious::Plugin::CSRFDefender calls render without specifying a layout,
    ## then our layout 'online' is rendered and Mojo croaks on non-declared variables. Work that around.
    $self->hook (before_dispatch => \&bd_set_initial_stash);
    $self->hook (after_dispatch  => \&ad_rss_sigquit);

    if ($self->mode eq 'production') {
        $self->hook (before_dispatch => sub {
            my $self = shift;

            ## Move prefix from path to base path
            push @{$self->req->url->base->path->parts}, shift @{$self->req->url->path->parts} for 1..$base_parts;
            $self->stash (production => 1);
        });
    } else {
        $self->hook (before_dispatch => sub {
            my $self = shift;

            $self->stash (production => 0);
        });
    }

    my $dbh = DBI->connect ('dbi:CSV:', undef, undef, {
        f_dir            => $sess_dir,
        f_encoding       => 'utf8',
        #csv_eol          => "\r\n",
        #csv_sep_char     => ",",
        #csv_quote_char   => '"',
        #csv_escape_char  => '"',
        RaiseError       => 1,
        #PrintError       => 1,
    }) or die $DBI::errstr;

    $self->helper (ebt => \&helper_ebt);
    $self->helper (color => \&helper_color);
    $self->helper (l2 => \&helper_l2);
    $self->helper (hit_partners => \&helper_hit_partners);
    $self->helper (rss_process => \&helper_rss_process);
    $self->helper (html_hrefs => \&helper_html_hrefs);
    $self->secret ('[12:36:04] gnome-screensaver-dialog: gkr-pam: unlocked login keyring');   ## :P
    $self->defaults (layout => 'online');
    $self->plugin ('I18N');

    ## - load /index
    ## - wait some minutes/hours
    ## - try to log in
    ## - boom
    #$self->plugin ('Mojolicious::Plugin::CSRFDefender');

    $self->plugin (session => {
        stash_key     => 'sess',
        store         => [ dbi => { dbh => $dbh } ],
        expires_delta => $session_expire * 60,
    });

    my $r = $self->routes;

    my $r_has_notes_hits = $r->under (sub {
        my ($self) = @_;

        ## TODO: reorganize routes
        #if (ref sess) { sess->load }

        if (ref $self->stash ('sess') and $self->stash ('sess')->load) {  ## s/load/sid/, index y $r_user pueden asumir que hay sess
            my $user = $self->stash ('sess')->data ('user');
            my $sid = $self->stash ('sess')->sid;
            $self->app->log->debug ("user: '$user'");

            my $gnuplot_img_dir = File::Spec->catfile ($images_dir, $user);
            my $user_data_dir   = File::Spec->catfile ($user_data_basedir, $user);
            my $db              = File::Spec->catfile ($user_data_dir, 'db');
            if (!-d $gnuplot_img_dir) {
                mkdir $gnuplot_img_dir          or die "mkdir: '$gnuplot_img_dir': $!\n";
                mkdir "$gnuplot_img_dir/static" or die "mkdir: '$gnuplot_img_dir/static': $!\n";
            }
            if (!-d $user_data_dir) { mkdir $user_data_dir or die "mkdir: '$user_data_dir': $!"; }
            if (!-d $html_dir)      { mkdir $html_dir      or die "mkdir: '$html_dir': $!"; }

            eval { $self->stash (ebt => EBT2->new (db => $db)); };
            $@ and die "Initializing model: '$@'\n";   ## TODO: this isn's working
            eval { $self->ebt->load_db; };
            if ($@ and $@ !~ /No such file or directory/) {
                $self->app->log->warn ("loading db: '$@'. Going on anyway.\n");
            }
            $self->ebt->set_logger ($self->app->log);
            $self->stash ('sess')->extend_expires;
            #$self->req->is_xhr or log_sizes $self->app->log, $self->ebt;

            if (-e File::Spec->catfile ($html_dir, $user, 'index.html')) {
                my $url;
                if ($base_href) {
                    my $stripped = $base_href; $stripped =~ s{/*$}{};
                    $url = sprintf '%s/stats/%s', $stripped, $user;
                } else {
                    $url = sprintf 'stats/%s/%s', $user, 'index.html';
                }
                $self->stash (public_stats => $url);
            }

            my $cbs = $self->ebt->get_checked_boxes // [];
            my %cbs; @cbs{@$cbs} = (1) x @$cbs;

            my %html_hrefs = $self->html_hrefs;
            $html_hrefs{ $self->stash ('requested_url') } = undef;  ## we are going to work on this right now, so set it as done in the template
            ## TODO: if users requests e.g. notes_per_year, then we should set as done all sections in EBT2's time bundle

            $self->stash (checked_boxes => \%cbs);
            $self->stash (html_hrefs    => \%html_hrefs);
            $self->stash (has_notes     => $self->ebt->has_notes);
            $self->stash (has_hits      => $self->ebt->has_hits);
            $self->stash (has_bad_notes => $self->ebt->has_bad_notes);
            $self->stash (user          => $user);
            $self->stash (html_dir      => $html_dir);
            $self->stash (statics_dir   => $statics_dir);
            $self->stash (images_dir    => $images_dir);
        }

        return 1;
    });
    $r_has_notes_hits->get ('/')->to ('main#index');
    $r_has_notes_hits->get ('//')->to ('main#index');
    $r_has_notes_hits->get ('/index')->to ('main#index');
    $r_has_notes_hits->post ('/login')->to ('main#login');

    my $r_user = $r_has_notes_hits->under (sub {
        my ($self) = @_;

        return 1 if ref $self->stash ('sess') and $self->stash ('sess')->sid;

        my $requested_url = $self->stash ('requested_url');
        $self->app->log->debug (sprintf 'set flash: requested_url (before tampering) is (%s)', $requested_url);
        $requested_url = '' if grep { $_ eq $requested_url } qw/logout index gen_output/;
        $requested_url = 'configure' if 'upload' eq $requested_url;
        $self->flash (requested_url => $requested_url);
        $self->app->log->debug ("no session, redirecting to index, requested_url ($requested_url)");
        $self->redirect_to ('index');
        return 0;
    });
    $r_user->get ('/configure')->to ('main#configure');
    $r_user->post ('/upload')->to ('main#upload');
    $r_user->get ('/help')->to ('main#help');
    $r_user->get ('/logout')->to ('main#logout');
    $r_user->get ('/progress')->to ('main#progress');

    my $u = $r_user->under (sub {
        my ($self) = @_;

        if (!$self->stash ('has_notes')) {
            $self->app->log->debug ('has no notes, redirecting to configure');
            $self->redirect_to ('configure');
            return 0;
        }

        return 1;
    });
    $u->get ('/information')->to ('main#information');
    $u->get ('/value')->to ('main#value');
    $u->get ('/countries')->to ('main#countries');
    $u->get ('/printers')->to ('main#printers');
    $u->get ('/locations')->to ('main#locations');
    $u->get ('/travel_stats')->to ('main#travel_stats');
    $u->get ('/huge_table')->to ('main#huge_table');
    $u->get ('/short_codes')->to ('main#short_codes');
    $u->get ('/nice_serials')->to ('main#nice_serials');
    $u->get ('/coords_bingo')->to ('main#coords_bingo');
    $u->get ('/notes_per_year')->to ('main#notes_per_year');
    $u->get ('/notes_per_month')->to ('main#notes_per_month');
    $u->get ('/top_days')->to ('main#top_days');
    $u->get ('/time_analysis_bingo')->to ('main#time_analysis_bingo');
    $u->get ('/time_analysis_detail')->to ('main#time_analysis_detail');
    $u->get ('/combs_bingo')->to ('main#combs_bingo');
    $u->get ('/combs_detail')->to ('main#combs_detail');
    $u->get ('/plate_bingo')->to ('main#plate_bingo');
    $u->get ('/bad_notes')->to ('main#bad_notes');
    $u->get ('/hit_list')->to ('main#hit_list');
    $u->get ('/hit_times_bingo')->to ('main#hit_times_bingo');
    $u->get ('/hit_times_detail')->to ('main#hit_times_detail');
    $u->get ('/hit_locations')->to ('main#hit_locations');
    $u->get ('/hit_analysis')->to ('main#hit_analysis');
    $u->get ('/hit_summary')->to ('main#hit_summary');
    $u->get ('/calendar')->to ('main#calendar');
    $u->post ('/gen_output')->to ('main#gen_output');
    #$u->get ('/charts')->to ('main#charts');
}

1;
