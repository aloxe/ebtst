#!/usr/bin/perl

use warnings;
use strict;
use Test::More;

use EBT2;
use EBT2::Util qw/set_xor_key/;
use EBT2::Data;
use EBT2::Stats;

set_xor_key 'test';

plan tests => 254;

my $data_obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$data_obj->load_notes (undef, 't/notes2.csv');
ok defined $data_obj->{'notes'}, 'There are notes after loading db';
is scalar @{ $data_obj->{'notes'} }, 7, 'Correct number of notes';

my $st = new_ok 'EBT2::Stats';

my $res;
$res = $st->activity (undef, $data_obj);
is ref $res, 'HASH', 'activity';
is $res->{'activity'}{'first_note'}{'date'}, '2010-02-11', 'First note date';
## there are two periods of 1 day of duration in notes2.csv. EBT2 takes the first of them, which has 3 notes
is $res->{'activity'}{'longest_active_period_notes'}, 3, 'Longest active period, given in notes';
is $res->{'activity'}{'active_days_count'}, 2, 'Active days count';

$res = $st->count (undef, $data_obj);
is ref $res, 'HASH', 'count';
is $res->{'count'}, 7, 'Note count';

$res = $st->total_value (undef, $data_obj);
is $res->{'total_value'}, 640, 'Total value';
is ref $res->{'signatures'}, 'HASH', 'Signatures';

$res = $st->notes_by_value (undef, $data_obj);
is ref $res, 'HASH', 'notes_by_value';
is $res->{'notes_by_value'}{'10'}, 1, 'One 10€ note';
is $res->{'notes_by_value'}{'20'}, 4, 'Four 20€ notes';
is $res->{'notes_by_value'}{'50'}, 1, 'One 50€ note';
is $res->{'notes_by_value'}{'500'}, 1, 'One 500€ note';


note 'locations';
$res = $st->notes_by_city (undef, $data_obj);
is $res->{'notes_by_city'}{'es'}{'Madrid'}{'first_id'},  '99999999993', 'Correct id in notes_by_city for Madrid';
is $res->{'notes_by_city'}{'es'}{'Sevilla'}{'first_id'}, '99999999998', 'Correct id in notes_by_city for Sevilla';
is $res->{'notes_by_city'}{'es'}{'Toledo'}{'first_id'},  '99999999999', 'Correct id in notes_by_city for Toledo';


note 'short_codes';
$data_obj->load_notes (undef, 't/notes-combs.csv');
$res = $st->highest_short_codes (undef, $data_obj);
is $res->{'highest_short_codes'}{'E'}{'5'}{'sort_key'}, 'E010A1H002', 'Highest short code for 5 E/H';
is $res->{'highest_short_codes'}{'E'}{'20'}{'sort_key'}, 'E003A1H**011', 'Highest short code for 20 E/H';
is $res->{'highest_short_codes'}{'G'}{'20'}{'sort_key'}, 'G008A1H550', 'Highest short code for 20 G/H';
is $res->{'highest_short_codes'}{'U'}{'20'}{'sort_key'}, 'U001A1M378', 'Highest short code for 20 U/M';
is $res->{'highest_short_codes'}{'F'}{'10'}{'sort_key'}, 'F001A1N**211', 'Highest short code for 10 F/N';
is $res->{'highest_short_codes'}{'G'}{'200'}{'sort_key'}, 'G001A1N000', 'Highest short code for 200 G/N';
is $res->{'highest_short_codes'}{'F'}{'5'}{'sort_key'}, 'F003A1P04**1', 'Highest short code for 5 F/P';
is $res->{'highest_short_codes'}{'F'}{'500'}{'sort_key'}, 'F001A1P**011', 'Highest short code for 500 F/P';
is $res->{'highest_short_codes'}{'K'}{'10'}{'sort_key'}, 'K001A1T265', 'Highest short code for 10 K/T';
is $res->{'highest_short_codes'}{'L'}{'20'}{'sort_key'}, 'L004A1U**311', 'Highest short code for 20 L/U';
is $res->{'highest_short_codes'}{'T'}{'50'}{'sort_key'}, 'T001A1Z3**11', 'Highest short code for 50 T/Z';


note 'hit_list';
$data_obj->load_notes (undef, 't/notes4.csv');
$data_obj->load_hits (undef, 't/hits4.csv');
my $foo = <<'EOF';
notes:
1    50;2002;V****6280***;;2010-10-05 09:27:31
2    20;2002;V****6958***;;2010-10-05 09:27:31
3    20;2002;P****1539***;;2010-10-05 09:27:31
4    20;2002;L****1739***;;2010-10-05 09:27:31  active hit
5    20;2002;V****7215***;;2010-10-20 22:34:31  (will be passive)
6    20;2002;S****2567***;;2010-11-24 20:11:39  active hit
7     5;2002;V****5654***;;2011-03-11 11:51:40  (will be passive)
8     5;2002;P****1079***;;2011-03-11 11:51:40
                           2011-04-30           passive hit (5)
9    20;2002;T****0637***;;2011-10-09 10:28:03  (will be passive)
                           2011-10-19           passive hit (9)
10   20;2002;L****4707***;;2011-11-11 10:43:37  active hit
                           2011-11-14           passive hit (7)
11   20;2002;S****1900***;;2012-02-01 09:25:51  active hit

------

hits              nnum  elapsed   old_hr    new_hr      n_betw  d_betw
20;L****1739***    4      4       na        4/1=4         3      0        ;2010-10-05 09:27:31;2;0;1407;212
20;S****2567***    6      6       5/1=5     6/2=3         1      49       ;2010-11-24 20:11:39;2;0;476;210
20;V****7215***    5      8       8/2=4     8/3=2.6       2      156      ;2011-04-30 13:28:45;2;0;34;68
20;T****0637***    9      9       9/3=3     9/4=2.2       1      171      ;2011-10-19 00:47:18;2;0;36;9
20;L****4707***    10     10      9/4=2.2   10/5=2        0      22       ;2011-11-11 10:43:37;2;0;2824;837
 5;V****5654***    7      10      10/5=2    10/6=1.6      0      2        ;2011-11-14 22:12:29;2;0;1624;248
20;S****1900***    11     11      10/6=1.6  11/7=1.5      0      78       ;2012-02-01 09:25:51;2;0;1637;857
EOF
$res = $st->hit_list (undef, $data_obj, $data_obj->whoami);

for (0..6) { is $res->{'hit_list'}[$_]{'hit_no'}, $_+1, sprintf 'Correct hit %d number', $_ + 1; }

my @hit_dates = (
    '2010-10-07 00:00:00', '2010-11-26 00:00:00', '2011-05-02 00:00:00', '2011-10-21 00:00:00', '2011-11-13 00:00:00',
    '2011-11-16 00:00:00', '2012-02-03 00:00:00',
);
for (0..6) { is $res->{'hit_list'}[$_]{'hit_date'}, $hit_dates[$_], sprintf 'Correct hit %d date', $_ + 1; }
is +(join ',', @{ $res->{'hits_dates'} }), (join ',', @hit_dates), 'Correct hits_dates';

my @hit_days = qw/212 210 68 9 837 248 857/;
for (0..6) { is $res->{'hit_list'}[$_]{'days'}, $hit_days[$_], sprintf 'Correct hit %d travel days', $_ + 1; }
is $res->{'elem_travel_days'}, (join ',', @hit_days), 'Correct elem_travel_days';

my @hit_km = qw/1407 476 34 36 2824 1624 1637/;
for (0..6) { is $res->{'hit_list'}[$_]{'km'}, $hit_km[$_], sprintf 'Correct hit %d travel km', $_ + 1; }
is $res->{'elem_travel_km'}, (join ',', @hit_km), 'Correct elem_travel_km';

my @hit_note_nos = qw/4 6 5 9 10 7 11/;
for (0..6) { ok abs $res->{'hit_list'}[$_]{'note_no'} - $hit_note_nos[$_] < 0.001, sprintf 'Correct hit %d note number', $_ + 1; }

my @hit_notes_elapsed = qw/4 6 8 9 10 10 11/;
for (0..6) { ok abs $res->{'hit_list'}[$_]{'notes'} - $hit_notes_elapsed[$_] < 0.001, sprintf 'Correct hit %d notes elapsed', $_ + 1; }

my @hit_old_ratios = (undef, qw/5 4 3 2.25 2 1.6667/);
is $res->{'hit_list'}[0]{'old_hit_ratio'}, undef, 'Correct hit 1 old ratio';
for (1..6) { ok abs $res->{'hit_list'}[$_]{'old_hit_ratio'} - $hit_old_ratios[$_] < 0.001, sprintf 'Correct hit %d old ratio', $_ + 1; }

my @hit_new_ratios = qw/4 3 2.6667 2.25 2 1.6667 1.5714/;
for (0..6) { ok abs $res->{'hit_list'}[$_]{'new_hit_ratio'} - $hit_new_ratios[$_] < 0.001, sprintf 'Correct hit %d new ratio', $_ + 1; }

my @hit_notes_between = qw/3 1 2 1 0 0 0/;
for (0..6) { is $res->{'hit_list'}[$_]{'notes_between'}, $hit_notes_between[$_], sprintf 'Correct hit %d notes between', $_ + 1; }

my @hit_days_between = qw/0 49 156 171 22 2 78/;
for (0..6) { is $res->{'hit_list'}[$_]{'days_between'}, $hit_days_between[$_], sprintf 'Correct hit %d days between', $_ + 1; }


note 'hit_list again, now with some moderated hits';
$data_obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$data_obj->load_notes (undef, 't/notes5.csv');
$data_obj->load_hits (undef, 't/hits5.csv');
$res = $st->hit_list (undef, $data_obj, $data_obj->whoami);

is $res->{'hit_list'}[0]{'hit_no'}, undef, sprintf 'Correct hit 1 (moderated) number';
is $res->{'hit_list'}[1]{'hit_no'}, 1,     sprintf 'Correct hit 2 number';
is $res->{'hit_list'}[2]{'hit_no'}, 2,     sprintf 'Correct hit 3 number';
is $res->{'hit_list'}[3]{'hit_no'}, undef, sprintf 'Correct hit 4 (moderated) number';
is $res->{'hit_list'}[4]{'hit_no'}, 3,     sprintf 'Correct hit 5 number';
is $res->{'hit_list'}[5]{'hit_no'}, 4,     sprintf 'Correct hit 6 number';
is $res->{'hit_list'}[6]{'hit_no'}, 5,     sprintf 'Correct hit 7 number';
is $res->{'hit_list'}[7]{'hit_no'}, 6,     sprintf 'Correct hit 8 number';
is $res->{'hit_list'}[8]{'hit_no'}, 7,     sprintf 'Correct hit 9 number';

for (0..8) { is $res->{'hit_list'}[$_]{'hit_no2'}, $_+1, sprintf 'Correct hit %d number, including moderated ones', $_ + 1; }

my @all_hit_dates = (
    '2010-03-13 00:00:00', '2010-10-07 00:00:00', '2010-11-26 00:00:00', '2011-03-13 00:00:00', '2011-05-02 00:00:00',
    '2011-10-21 00:00:00', '2011-11-13 00:00:00', '2011-11-16 00:00:00', '2012-02-03 00:00:00',
);
for (0..8) { is $res->{'hit_list'}[$_]{'hit_date'}, $all_hit_dates[$_], sprintf 'Correct hit %d date', $_ + 1; }
## use @hit_dates here, not all_hit_dates since $res->{'hits_dates'} shouldn't contain moderated hits
is +(join ',', @{ $res->{'hits_dates'} }), (join ',', @hit_dates), 'Correct hits_dates';

my @all_hit_days = qw/85 212 210 85 68 9 837 248 857/;
for (0..8) { is $res->{'hit_list'}[$_]{'days'}, $all_hit_days[$_], sprintf 'Correct hit %d travel days', $_ + 1; }
## use @hit_days here, not all_hit_days since $res->{'elem_travel_days'} shouldn't contain moderated hits
is $res->{'elem_travel_days'}, (join ',', @hit_days), 'Correct elem_travel_days';

my @all_hit_km = qw/28 1407 476 28 34 36 2824 1624 1637/;
for (0..8) { is $res->{'hit_list'}[$_]{'km'}, $all_hit_km[$_], sprintf 'Correct hit %d travel km', $_ + 1; }
## use @hit_km here, not all_hit_km since $res->{'elem_travel_km'} shouldn't contain moderated hits
is $res->{'elem_travel_km'}, (join ',', @hit_km), 'Correct elem_travel_km';

my @all_hit_note_nos = qw/1 5 7 8 6 11 12 9 13/;
for (0..8) { ok abs $res->{'hit_list'}[$_]{'note_no'} - $all_hit_note_nos[$_] < 0.001, sprintf 'Correct hit %d note number', $_ + 1; }

is $res->{'hit_list'}[0]{'notes'}, undef, sprintf 'Correct hit 1 notes elapsed';
is $res->{'hit_list'}[1]{'notes'}, 5,     sprintf 'Correct hit 2 notes elapsed';
is $res->{'hit_list'}[2]{'notes'}, 7,     sprintf 'Correct hit 3 notes elapsed';
is $res->{'hit_list'}[3]{'notes'}, undef, sprintf 'Correct hit 4 notes elapsed';
is $res->{'hit_list'}[4]{'notes'}, 10,    sprintf 'Correct hit 5 notes elapsed';
is $res->{'hit_list'}[5]{'notes'}, 11,    sprintf 'Correct hit 6 notes elapsed';
is $res->{'hit_list'}[6]{'notes'}, 12,    sprintf 'Correct hit 7 notes elapsed';
is $res->{'hit_list'}[7]{'notes'}, 12,    sprintf 'Correct hit 8 notes elapsed';
is $res->{'hit_list'}[8]{'notes'}, 13,    sprintf 'Correct hit 9 notes elapsed';

is $res->{'hit_list'}[0]{'old_hit_ratio'}, undef,               'Correct hit 1 old ratio';
is $res->{'hit_list'}[1]{'old_hit_ratio'}, undef,               'Correct hit 2 old ratio';
ok abs $res->{'hit_list'}[2]{'old_hit_ratio'} - 6      < 0.001, 'Correct hit 3 old ratio';
is $res->{'hit_list'}[3]{'old_hit_ratio'}, undef              , 'Correct hit 4 old ratio';
ok abs $res->{'hit_list'}[4]{'old_hit_ratio'} - 5      < 0.001, 'Correct hit 5 old ratio';
ok abs $res->{'hit_list'}[5]{'old_hit_ratio'} - 3.6667 < 0.001, 'Correct hit 6 old ratio';
ok abs $res->{'hit_list'}[6]{'old_hit_ratio'} - 2.75   < 0.001, 'Correct hit 7 old ratio';
ok abs $res->{'hit_list'}[7]{'old_hit_ratio'} - 2.4    < 0.001, 'Correct hit 8 old ratio';
ok abs $res->{'hit_list'}[8]{'old_hit_ratio'} - 2      < 0.001, 'Correct hit 9 old ratio';

is $res->{'hit_list'}[0]{'new_hit_ratio'}, undef,               'Correct hit 1 new ratio';
ok abs $res->{'hit_list'}[1]{'new_hit_ratio'} - 5      < 0.001, 'Correct hit 2 new ratio';
ok abs $res->{'hit_list'}[2]{'new_hit_ratio'} - 3.5    < 0.001, 'Correct hit 3 new ratio';
is $res->{'hit_list'}[3]{'new_hit_ratio'}, undef,               'Correct hit 4 new ratio';
ok abs $res->{'hit_list'}[4]{'new_hit_ratio'} - 3.3333 < 0.001, 'Correct hit 5 new ratio';
ok abs $res->{'hit_list'}[5]{'new_hit_ratio'} - 2.75   < 0.001, 'Correct hit 6 new ratio';
ok abs $res->{'hit_list'}[6]{'new_hit_ratio'} - 2.4    < 0.001, 'Correct hit 7 new ratio';
ok abs $res->{'hit_list'}[7]{'new_hit_ratio'} - 2      < 0.001, 'Correct hit 8 new ratio';
ok abs $res->{'hit_list'}[8]{'new_hit_ratio'} - 1.8571 < 0.001, 'Correct hit 9 new ratio';

my @all_hit_notes_between = (undef, qw/4 1/, undef, qw/3 1 0 0 0/);
for (0..8) { is $res->{'hit_list'}[$_]{'notes_between'}, $all_hit_notes_between[$_], sprintf 'Correct hit %d notes between', $_ + 1; }

my @all_hit_days_between = (undef, qw/207 49/, undef, qw/156 171 22 2 78/);
for (0..8) { is $res->{'hit_list'}[$_]{'days_between'}, $all_hit_days_between[$_], sprintf 'Correct hit %d days between', $_ + 1; }


note 'first hit is passive and moderated';
$data_obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$data_obj->load_notes (undef, 't/notes6.csv');
$data_obj->load_hits (undef, 't/hits6.csv');
$res = $st->hit_list (undef, $data_obj, $data_obj->whoami);
is $res->{'hit_list'}[0]{'moderated'}, 1, 'First hit is moderated';
is $res->{'hit_list'}[1]{'moderated'}, 0, 'Second hit is not moderated';
ok !exists $res->{'hit_list'}[0]{'old_hit_ratio'}, 'Key "old_hit_ratio" is not present';   ## the code doesn't set some keys for moderated hits


note 'notes_between on passive interesting hits';
$data_obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$data_obj->load_notes (undef, 't/notes7.csv');
$data_obj->load_hits (undef, 't/hits7.csv');
$res = $st->hit_list (undef, $data_obj, $data_obj->whoami);
is $res->{'hit_list'}[3]{'notes_between'}, 7, 'Correct notes_between';


note q[notes_between when there's more than one passive hit in a row without user entering notes];
@hit_notes_between = qw/7 2 0 0 0 3 0 0 1/;
$data_obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$data_obj->load_notes (undef, 't/notes8.csv');
$data_obj->load_hits (undef, 't/hits8.csv');
$res = $st->hit_list (undef, $data_obj, $data_obj->whoami);
for (0..8) { is $res->{'hit_list'}[$_]{'notes_between'}, $hit_notes_between[$_], sprintf 'Correct hit %d notes between', $_ + 1; }


note q[hit number of a triple where I'm not the last user];
$data_obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$data_obj->load_notes (undef, 't/notes9.csv');
$data_obj->load_hits (undef, 't/hits9.csv');
$res = $st->hit_list (undef, $data_obj, $data_obj->whoami);
is $res->{'hit_list'}[0]{'hit_no'}, undef, sprintf 'Correct hit 1 (moderated) number';
is $res->{'hit_list'}[1]{'hit_no'}, 1,     sprintf 'Correct hit 2 number';
is $res->{'hit_list'}[2]{'hit_no'}, undef, sprintf 'Correct hit 3 (moderated) number';
is $res->{'hit_list'}[3]{'hit_no'}, 2,     sprintf 'Correct hit 4 number';
is $res->{'hit_list'}[4]{'hit_no'}, 3,     sprintf 'Correct hit 5 number';
is $res->{'hit_list'}[5]{'hit_no'}, 4,     sprintf 'Correct hit 6 number';
is $res->{'hit_list'}[6]{'hit_no'}, 5,     sprintf 'Correct hit 7 number';
is $res->{'hit_list'}[7]{'hit_no'}, 6,     sprintf 'Correct hit 8 number';
is $res->{'hit_list'}[8]{'hit_no'}, 7,     sprintf 'Correct hit 9 number';



note 'hits file references unknown notes';
eval { $data_obj->load_hits (undef, 't/hits8b.csv'); };
like $@, qr/Unrecognized hits file/, 'load_hits dies if it references unknown notes';


note 'note validator';
$data_obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$data_obj->load_notes (undef, 't/notes-validator.csv');
$res = $st->bad_notes (undef, $data_obj);
is $res->{'bad_notes'}[0]{'errors'}[0], q{Bad value '6'}, 'Bad value';
is $res->{'bad_notes'}[1]{'errors'}[0], q{Bad year '2005'}, 'Bad year';
is $res->{'bad_notes'}[2]{'errors'}[0], q{Bad checksum for serial number}, 'Bad checksum';
is $res->{'bad_notes'}[3]{'errors'}[0], q{Bad serial number}, 'Bad serial number';
is $res->{'bad_notes'}[4]{'errors'}[0], q{Bad short code 'E001A9'}, 'Bad short code';
is $res->{'bad_notes'}[5]{'errors'}[0], q{Bad short code position 'J1'}, 'Bad short code position';
is $res->{'bad_notes'}[6]{'errors'}[0], q{Plate 'P100' doesn't exist for 5/X}, 'Unknown plate';
is $res->{'bad_notes'}[7]{'errors'}[0], q{Bad note id '_9999999992'}, 'Bad note id';
is $res->{'bad_notes'}[8]{'errors'}[0], q{Bad number of times entered '_'}, 'Bad times_entered';
is $res->{'bad_notes'}[9]{'errors'}[0], q{Bad status of moderated hit '2'}, 'Bad is_moderated';
is $res->{'bad_notes'}[10]{'errors'}[0], q{Bad latitude '442532.3'}, 'Bad latitude';
is $res->{'bad_notes'}[11]{'errors'}[0], q{Bad longitude '122317.6'}, 'Bad longitude';
is $res->{'bad_notes'}[12]{'errors'}[0], q{Bad value '7'}, 'Multiple errors: bad value';
is $res->{'bad_notes'}[12]{'errors'}[1], q{Bad year '2009'}, 'Multiple errors: bad year';
is $res->{'bad_notes'}[12]{'errors'}[2], q{Bad note id '_9999999987'}, 'Multiple errors: bad note id';
is $res->{'bad_notes'}[12]{'errors'}[3], q{Bad number of times entered '_'}, 'Multiple errors: bad times_entered';
is $res->{'bad_notes'}[12]{'errors'}[4], q{Bad status of moderated hit '2'}, 'Multiple errors: bad is_moderated';
is $res->{'bad_notes'}[12]{'errors'}[5], q{Bad latitude '44532.3'}, 'Multiple errors: bad latitude';
is $res->{'bad_notes'}[12]{'errors'}[6], q{Bad longitude '12317.6'}, 'Multiple errors: bad longitude';


unlink '/tmp/ebt2-storable' or warn "unlink: '/tmp/ebt2-storable': $!";
