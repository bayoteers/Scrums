# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Scrums Bugzilla Extension.
#
# The Initial Developer of the Original Code is "Nokia corporation"
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Visa Korhonen <visa.korhonen@symbio.com>

package Bugzilla::Extension::Scrums::Sprintslib;

use lib qw(./extensions/Scrums/lib);

use Bugzilla::Extension::Scrums::Bugorder;

use Bugzilla::FlagType;
use Bugzilla::Error;
use Bugzilla::Util qw(trick_taint);

use JSON::XS;
use Date::Parse;
use Date::Calc qw(Today_and_Now Mktime);

use strict;
use base qw(Exporter);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::Scruns::Releases". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)
our @EXPORT = qw(
  update_bug_order_from_json
  sprint_summary
  );
#
# Important!
# Data needs to be in exact format:
#
#  { -1 : [1,2,3,4,5], 18 : [10,11,12] }
#

sub update_bug_order_from_json {
    my ($team_id, $data) = @_;

    my $json = new JSON::XS;
    if ($data =~ /(.*)/) {
        $data = $1;    # $data now untainted
    }
    my $content = $json->allow_nonref->utf8->relaxed->decode($data);

    my %all_team_sprints_and_unprioritised_in = %{$content};
    team_bug_order($team_id, $content);
}

sub team_bug_order {
    my ($team_id, $all_team_sprints_and_unprioritised_in) = @_;

    my %sprints_hash;
    #    my %team_order_hash;

    _get_sprints_hash(\%sprints_hash, $team_id);
    #    _get_team_order_hash(\%team_order_hash, $team_id);

    my @sprint_id_array = keys %{$all_team_sprints_and_unprioritised_in};
    for my $sprint_id (@sprint_id_array) {
        my $bugs = $all_team_sprints_and_unprioritised_in->{$sprint_id};

        if ($sprint_id == -1) {
            process_unprioritised_in($bugs);
        }
        else {
            process_sprint($sprint_id, $bugs, \%sprints_hash);
        }
    }

    #    process_team_orders($all_team_sprints_and_unprioritised_in, \%team_order_hash);
    process_team_orders($all_team_sprints_and_unprioritised_in);
}

sub process_sprint() {
    my ($sprint_id, $bugs, $sprints_hash) = @_;

    # print "Processing sprint\n";
    foreach my $bug (@{$bugs}) {
        my $old_sprint = $sprints_hash->{$bug};

        if ($old_sprint == $sprint_id) {
            # print "(Sprint is unchanged)\n";
        }
        elsif ($old_sprint == 0) {
            Bugzilla->dbh->do('INSERT INTO scrums_sprint_bug_map (bug_id, sprint_id) values (?, ?)', undef, $bug, $sprint_id);
        }
        else {
            Bugzilla->dbh->do('UPDATE scrums_sprint_bug_map set sprint_id=? where bug_id=?', undef, $sprint_id, $bug);
        }
    }
}

sub process_unprioritised_in() {
    my ($unprioritised_in) = @_;

    foreach my $bug (@{$unprioritised_in}) {
        Bugzilla->dbh->do('DELETE from scrums_sprint_bug_map where bug_id=?',         undef, $bug);
        Bugzilla->dbh->do('UPDATE scrums_bug_order set team = NULL where bug_id = ?', undef, $bug);
    }
}

sub process_team_orders() {
    #    my ($ref, $team_order_hash) = @_;
    my ($ref) = @_;

    my %all_team_sprints_and_unprioritised_in = %{$ref};

    my $counter = 1;

    my @sprint_id_array = keys %all_team_sprints_and_unprioritised_in;
    for my $sprint_id (@sprint_id_array) {
        my $bugs = $all_team_sprints_and_unprioritised_in{$sprint_id};

        # This means, that table is sprint and not unprioritised_in
        if ($sprint_id != -1) {
            foreach my $bug (@{$bugs}) {
                #                my $old_team_order = $team_order_hash->{$bug};
                #                if (!exists $team_order_hash->{$bug}) {
                my $old_team_order = _old_team_order($bug);
                #                if (!_exists_bug_order($bug->id());
                if ($old_team_order == -1) {
                    Bugzilla->dbh->do('INSERT INTO scrums_bug_order (bug_id, team) values (?, ?)', undef, $bug, $counter);
                }
                elsif ($counter != $old_team_order) {
                    Bugzilla->dbh->do('UPDATE scrums_bug_order set team=? where bug_id=?', undef, $counter, $bug);
                }
                else {
                    # Team order for bug ($bug) is unchanged ($old_team_order)
                }
                $counter = $counter + 1;
            }
        }
        # Unprioritised_in must be handled separately
        # Table scrums_bug_order is however updated for unprioritised_in at the same time as scrums_sprint_bug_map, because order in table is irrelevant.
    }
}

sub sprint_summary {
    my ($vars, $sprint_id) = @_;

    my $sprint  = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
    my $team_id = $sprint->team_id();
    my $team    = Bugzilla::Extension::Scrums::Team->new($team_id);
    _burndown_plot($vars, $sprint_id);
    _status_summary($vars, $sprint_id);
    $vars->{'team_name'}   = $team->name();
    $vars->{'team_id'}     = $team_id;
    $vars->{'sprint_name'} = $sprint->name();
}

sub _status_summary {
    my ($vars, $sprint_id) = @_;

    if ($sprint_id =~ /([0-9]+)/) {
        $sprint_id = $1;    # $data now untainted
    }

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        "select
	bs.is_open,
	count(b.bug_id)
    from
	bugs b
    inner join
	bug_status bs 
    on
	b.bug_status = bs.value
    inner join
	scrums_sprint_bug_map sbm on sbm.bug_id = b.bug_id
    inner join
	scrums_sprints s on s.id = sbm.sprint_id
    where
	s.id = ?
    group by
	bs.is_open"
                           );
    $sth->execute($sprint_id);
    my ($open_status, $count);
    my %summary;
    while (($open_status, $count) = $sth->fetchrow_array) {
        if ($open_status == 1) {
            $summary{"open"} = $count;
        }
        else {
            $summary{"closed"} = $count;
        }
    }

    $sth = $dbh->prepare(
        "select
	    b.bug_status,
	    count(b.bug_id)
        from
	    bugs b
        inner join
	    scrums_sprint_bug_map sbm on sbm.bug_id = b.bug_id
        inner join
	    scrums_sprints s on s.id = sbm.sprint_id
        where
	    s.id = ?
        group by
	    b.bug_status"
                        );
    $sth->execute($sprint_id);
    my @slist;
    my $status;
    while (($status, $count) = $sth->fetchrow_array) {
        my @row;
        push(@row,   $status);
        push(@row,   $count);
        push(@slist, \@row);
    }
    $vars->{'summary'} = \%summary;
    $vars->{'slist'}   = \@slist;
}

sub _burndown_plot {
    my ($vars, $sprint_id) = @_;

    if ($sprint_id =~ /([0-9]+)/) {
        $sprint_id = $1;    # $data now untainted
    }

    my $hour_log_array = _task_hour_log($vars, $sprint_id);
    my $index = scalar @{$hour_log_array};

    my $today = 1000 * Mktime(Today_and_Now());
    $vars->{'end'}  = $today;
    $vars->{'last'} = $index;

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        "select
            sum(remaining_time) as remaining
        from 
            bugs b
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = b.bug_id
        where 
            sprint_id = ?"
                           );
    $sth->execute($sprint_id);
    my ($cum_remain) = $sth->fetchrow_array();

    $sth = $dbh->prepare(
        "select
            sum(work_time)
        from 
            longdescs ld
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = ld.bug_id
        where
            sprint_id = ?"
                        );
    $sth->execute($sprint_id);
    my ($cum_work_time) = $sth->fetchrow_array();

    my $sprint  = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
    my $spr_end;
    my $spr_start;
    if($sprint->end_date()) {
        my ($y, $m, $d);
        $sprint->end_date() =~ /^([0-9]+)-([0-9]+)-([0-9]+)$/;
        $y = $1;
        $m = $2;
        $d = $3;
        # The day, that ends sprint lasts for (almost) 24 hours. 
        $spr_end = 1000 * Mktime($y, $m, $d, 23, 59, 0);
    }
    if($sprint->start_date()) {
        my ($y, $m, $d);
        $sprint->start_date() =~ /^([0-9]+)-([0-9]+)-([0-9]+)$/;
        $y = $1;
        $m = $2;
        $d = $3;
        $spr_start = 1000 * Mktime($y, $m, $d, 0, 0, 0);
    }

    my @remaining_array;
    my @worktime_array;
    my @last_rem_plot;
    my @last_work_plot;
    my $row;
    my ($x, $y);

    my $plot_ts;

    if(!$spr_end) {
        $x = $today;
    }
    while(!$x && $index > 0) {
        $row   = @{$hour_log_array}[$index];
        $plot_ts = @{$row}[0];
        if($spr_end > $plot_ts) {
            $x = $spr_end; 
        }
        else {
            $cum_remain = $cum_remain - @{$row}[1];    # 'added' in remain field
            $cum_remain = $cum_remain + @{$row}[2];    # 'removed' in remain field
            $cum_work_time = $cum_work_time - @{$row}[3];    # 'work_time'
            $index--;
        }
    }

    $y = $cum_remain;
    push @last_rem_plot,   $x;
    push @last_rem_plot,   $y;
    push @remaining_array, \@last_rem_plot;

    $y = $cum_remain + $cum_work_time;
    push @last_work_plot, $x;
    push @last_work_plot, $y;
    push @worktime_array, \@last_work_plot;

    my  $passed_beginning = 0;
    while ($index > 0 && !$passed_beginning) {
        $index = $index - 1;
        $row   = @{$hour_log_array}[$index];

        if($spr_start && $spr_start > @{$row}[0]) {
            $x = $spr_start;    
            $y = $cum_remain;
            my @rem_plot1;
            push @rem_plot1,       $x;
            push @rem_plot1,       $y;
            push @remaining_array, \@rem_plot1;

            $y = $cum_remain + $cum_work_time;
            my @work_plot1;
            push @work_plot1,     $x;
            push @work_plot1,     $y;
            push @worktime_array, \@work_plot1;

            $passed_beginning = 1;
        }
        else {
            $x = @{$row}[0];
            $y = $cum_remain;
            my @rem_plot1;
            push @rem_plot1,       $x;
            push @rem_plot1,       $y;
            push @remaining_array, \@rem_plot1;

            $y = $cum_remain + $cum_work_time;
            my @work_plot1;
            push @work_plot1,     $x;
            push @work_plot1,     $y;
            push @worktime_array, \@work_plot1;

            $cum_remain = $cum_remain - @{$row}[1];    # 'added' in remain field
            $cum_remain = $cum_remain + @{$row}[2];    # 'removed' in remain field
            $y          = $cum_remain;
            my @rem_plot2;
            push @rem_plot2,       $x;
            push @rem_plot2,       $y;
            push @remaining_array, \@rem_plot2;

            $cum_work_time = $cum_work_time - @{$row}[3];    # 'work_time'
            $y             = $cum_remain + $cum_work_time;
            my @work_plot2;
            push @work_plot2,     $x;
            push @work_plot2,     $y;
            push @worktime_array, \@work_plot2;
        }
    }

    $vars->{'result'}         = $hour_log_array;
    $vars->{'remaining_plot'} = \@remaining_array;
    $vars->{'worktime_plot'}  = \@worktime_array;
}

#
# Function fetches every log record from sprint, which changes hour balance.
# Main focus is on 'remaining hour' information. Also worked hours are collected.
#
# Remaining hours need to be collected from several sources. Remaining hours are
# recorded into some items while creating them and later changed. Some items are
# given hours while creating them and not changed after that (yet). Also some items
# are left without hour record while creating but hours are added later.
#
# Hour are fetched in union of four queries.
# 1.
# First query fetches changes in 'remaining hours' that are done after creating items.
# These changes are incremental.
# 2.
# Second query fetches values of 'remaining hours' that have been recorded while
# creating items, but which have been overwritten after that. The time amount,
# that was recorded while creating item, can not be read directly from item, because
# it has been overwritten. Time amount is read from later record of change of value.
# Timestamp of creating item is read from item itself.
# 3.
# Third query fetches values of 'remaining hours' that have been recorded while
# creating items and which have not been changed after that. The time amount,
# that was recorded while creating item, can be read directly from item.
# 4.
# Fourth query fetches worked hour, that have been recorded. Work hours are combined
# with 'remaining hours' in single query result. Rows are sorted by timestamp.
#
sub _task_hour_log {
    my ($vars, $sprint_id) = @_;

    use Bugzilla::Field;
    my $remaining_fieldid = get_field_id('remaining_time');

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        # With MySql-database it would be possible to select directly with function unix_timestamp(bug_when).
        # That would not however be database agnostic.
        "select bug_when, sum(added), sum(removed), sum(work_time) from (
        (select
            bug_when, added, removed, null as work_time
        from 
            bugs_activity ba
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = ba.bug_id
        where 
            fieldid = ? and
            sprint_id = ?)

        union

        (select 
            creation_ts as bug_when, 
            removed as added,
            null as removed,
            null as work_time
        from
            bugs_activity ba
            inner join
        (select
            sbm.bug_id as bug_id, min(bug_when) as ts
        from 
            scrums_sprint_bug_map sbm 
        inner join
            bugs_activity ba
        on
            sbm.bug_id = ba.bug_id and
            fieldid = ? 
        where 
            sprint_id = ?
        group by
            sbm.bug_id) as first_change
        on
            first_change.bug_id = ba.bug_id and
            fieldid = ? and
            first_change.ts = ba.bug_when and
            ba.removed > 0
        inner join
            bugs b
        on
            first_change.bug_id = b.bug_id)

        union

            (select
            creation_ts as bug_when, 
            remaining_time as added,
            null as removed,
            null as worktime
        from 
            scrums_sprint_bug_map sbm 
        inner join
            bugs b
        on
            sbm.bug_id = b.bug_id
        where 
            sprint_id = ? and
            remaining_time > 0 and
            not exists
        (select null from bugs_activity ba
            where b.bug_id = ba.bug_id and
            fieldid = ?))

        union

        (select
            bug_when, null as added, null as removed, work_time 
        from 
            longdescs ld
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = ld.bug_id
        where
            sprint_id = ? and 
            work_time > 0)) as hours
        group by
            bug_when
        order by
            bug_when"
    );
    $sth->execute($remaining_fieldid, $sprint_id, $remaining_fieldid, $sprint_id, $remaining_fieldid, $sprint_id, $remaining_fieldid, $sprint_id);
    my @result;
    my ($v1, $v2, $v3, $v4);
    while (($v1, $v2, $v3, $v4) = $sth->fetchrow_array) {
        my @copy;
        push(@copy,   1000 * str2time($v1));
        push(@copy,   $v2);
        push(@copy,   $v3);
        push(@copy,   $v4);
        push(@result, \@copy);
    }
    return \@result;
}

sub _old_team_order {
    my ($bug_id) = @_;

    my ($item_id, $team_order) = Bugzilla->dbh->selectrow_array('SELECT bug_id, team FROM scrums_bug_order WHERE bug_id = ?', undef, $bug_id);
    if ($item_id) {
        return $team_order;
    }
    return -1;
}

sub _get_sprints_hash {
    my ($sprints_hash, $team_id) = @_;

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        "select
	sbm.bug_id as bug_id,
	spr.id as sprint
    from 
	scrums_sprint_bug_map sbm
    inner join 
	scrums_sprints spr on sbm.sprint_id = spr.id
    where 
        spr.is_active = 1 and
	spr.team_id = ?"
                           );
    trick_taint($team_id);
    $sth->execute($team_id);

    while (my $row = $sth->fetchrow_arrayref) {
        my ($bug_id, $sprint) = @$row;
        $sprints_hash->{$bug_id} = $sprint;
    }
}

1;
