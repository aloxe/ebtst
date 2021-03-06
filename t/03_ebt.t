#!/usr/bin/perl

use warnings;
use strict;
use Test::More;
use MIME::Base64;
use Storable qw/thaw/;
use EBT2;
use EBT2::Util qw/_xor/;
use EBT2::Data;
use EBT2::Constants ':all';

plan tests => 35;

my $obj = new_ok 'EBT2', [ db => '/tmp/ebt2-storable', xor_key => 'test' ];
ok $obj->{'data'};
ok $obj->{'stats'};
ok !$obj->has_notes;

$obj->load_notes ('t/notes1.csv');
ok $obj->has_notes;
ok defined $obj->{'data'}{'notes'}, 'There are some notes after loading CSV';
is scalar @{ $obj->{'data'}{'notes'} }, 2, 'Correct number of notes';
$obj->load_hits ('t/hits1.csv');
is ref (thaw decode_base64 +(split ';', (_xor $obj->{'data'}{'notes'}[1]), NCOLS)[HIT]), 'HASH', 'There is a hit after loading hits CSV';
is +(split ';', (_xor $obj->{'data'}{'notes'}[0]), NCOLS)[HIT], '', 'No spurious hits after loading hits CSV';

$obj->load_notes ('t/notes1.csv');
is ref (thaw decode_base64 +(split ';', (_xor $obj->{'data'}{'notes'}[1]), NCOLS)[HIT]), 'HASH', 'Hits are still there after loading new notes CSV';
is +(split ';', (_xor $obj->{'data'}{'notes'}[0]), NCOLS)[HIT], '', 'No spurious hits after loading new notes CSV';

$obj->load_db;
ok defined $obj->{'data'}{'notes'}, 'There are notes after loading db';
is scalar @{ $obj->{'data'}{'notes'} }, 2, 'Correct number of notes';
is ref (thaw decode_base64 +(split ';', (_xor $obj->{'data'}{'notes'}[1]), NCOLS)[HIT]), 'HASH', 'Hits are still there after loading db';
is +(split ';', (_xor $obj->{'data'}{'notes'}[0]), NCOLS)[HIT], '', 'No spurious hits after loading db';

my $gotten;
$gotten = $obj->get_activity;
is ref $gotten, 'HASH', 'activity';
is $gotten->{'first_note'}{'date'}, '2010-01-26', 'First note date';
is $gotten->{'longest_active_period_notes'}, 1, 'Longest active period, given in notes';
is $gotten->{'active_days_count'}, 2, 'Active days count';

$gotten = $obj->get_count;
is $gotten, 2, 'Notes count';
$gotten = $obj->get_total_value;
is $gotten, 30, 'Total value';
$gotten = $obj->get_signatures;
is ref $gotten, 'HASH', 'Some signature';   ## TODO: all signatures, not only found ones

$gotten = $obj->get_days_elapsed;
like $gotten, qr/^\d+/, 'Days elapsed';

$gotten = $obj->get_notes_by_value;
is $gotten->{'10'}, 1, 'One 10€ note';
is $gotten->{'20'}, 1, 'One 20€ note';

$obj->load_notes ('t/notes-europa.csv');

$gotten = $obj->get_signatures;
ok !exists $gotten->{'_UNK'}, 'No unknown signatures';

$gotten = $obj->get_notes_by_cc;
is_deeply $gotten, {
    M => { total => 1, 5 => 1 },
    S => { total => 1, 20 => 1 },
    U => { total => 1, 20 => 1 },
    V => { total => 2, 20 => 1, 50 => 1 },
}, 'notes_by_cc ignores Europa notes';

$gotten = $obj->get_first_by_cc;
isnt $gotten->{'U'}{'serial'}, 'UB1016833133', 'first_by_cc ignores Europa notes';

$gotten = $obj->get_notes_by_pc;
is_deeply $gotten, {
    2002 => {
        J => { total => 1, 20 => 1 },
        L => { total => 1, 20 => 1 },
        M => { total => 2, 20 => 1, 50 => 1 },
        U => { total => 1, 5  => 1, },
    },
    europa => {
        U => { total => 2, 5  => 2, },
        V => { total => 1, 5  => 1, },
        Z => { total => 1, 5  => 1, },
    },
}, 'notes_by_pc';

$gotten = $obj->get_first_by_pc;
is $gotten->{'2002'}{'U'}{'serial'}, 'M18400000009', 'first_by_pc';
is $gotten->{'europa'}{'U'}{'serial'}, 'UB1016833133', 'first_by_pc';

$gotten = $obj->get_huge_table;
is_deeply $gotten, {
    '2002J025'   => { 20 => { S291     => { count => 1, recent => 0 } } },
    '2002L057'   => { 20 => { 'U**321' => { count => 1, recent => 0 } } },
    '2002M021'   => { 20 => { V236     => { count => 1, recent => 0 } } },
    '2002M030'   => { 50 => { V323     => { count => 1, recent => 0 } } },
    '2002U008'   => { 5  => { M184     => { count => 1, recent => 0 } } },
    'europaU002' => { 5  => { 'U**016' => { count => 2, recent => 0 } } },
    'europaV001' => { 5  => { VA07     => { count => 1, recent => 0 } } },
    'europaZ003' => { 5  => { ZB27     => { count => 1, recent => 0 } } },
}, 'huge_table';

$gotten = $obj->get_nice_serials;
ok +(!grep { 12 != length $_->{'visible_serial'} } @$gotten), 'nice_serials works with Europa notes';

#$gotten = $obj->get_missing_combs_and_history;
#ok !exists $gotten->{'sigs'}{'MD'}, 'missing_combs_and_history ignores Europa notes';

#$gotten = $obj->get_notes_by_combination;
#ok !exists $gotten->{'any'}{'UU'}, 'notes_by_combination ignores Europa notes';
#ok !exists $gotten->{'any'}{'VV'}, 'notes_by_combination ignores Europa notes';

$gotten = $obj->get_bad_notes;
is $gotten, undef, 'No bad Europa notes';

$obj->load_notes ('t/notes-validator.csv');
is scalar @${ thaw _xor $obj->{'data'}{'bad_notes'}{'data'} }, 13, 'Correct number of bad notes after loading CSV';

unlink '/tmp/ebt2-storable' or warn "unlink: '/tmp/ebt2-storable': $!";
