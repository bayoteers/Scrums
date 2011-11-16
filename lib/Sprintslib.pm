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
  sprint_summary
  handle_person_capacity
  );

sub handle_person_capacity {
    my ($data, $vars) = @_;

    my $json = new JSON::XS;
    if ($data =~ /(.*)/) {
        $data = $1;    # $data now untainted
    }

    my $content = $json->allow_nonref->utf8->relaxed->decode($data);
    my $params  = $content->{params};

    my $sprint_id = $params->{sprint_id};
    my $person_id = $params->{person_id};
    my $capacity  = $params->{capacity};
    my $sprint    = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
    $sprint->set_member_capacity($person_id, $capacity);
}

sub sprint_summary {
    my ($vars, $sprint_id) = @_;

    my $sprint  = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
    my $team_id = $sprint->team_id();
    my $team    = Bugzilla::Extension::Scrums::Team->new($team_id);
    _burndown_plot_by_hour($vars, $sprint_id);
    _burndown_plot_by_items($vars, $sprint_id);
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

sub _burndown_plot_by_hour {
    my ($vars, $sprint_id) = @_;

    if ($sprint_id =~ /([0-9]+)/) {
        $sprint_id = $1;    # $data now untainted
    }
    my ($ending_remain, $ending_work_time) = _ending_hours($sprint_id);
    my $hour_log_array = _task_hour_log($vars, $sprint_id);
    my ($remaining_array, $worktime_array) = _create_plot_chart($vars, $sprint_id, $ending_remain, $ending_work_time, $hour_log_array);

    $vars->{'remaining_hours_plot'} = $remaining_array;
    $vars->{'worktime_hours_plot'}  = $worktime_array;
}

sub _ending_hours {
    my ($sprint_id) = @_;

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
    my ($ending_remain) = $sth->fetchrow_array();

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
    my ($ending_work_time) = $sth->fetchrow_array();
    return ($ending_remain, $ending_work_time);
}

sub _create_plot_chart {
    my ($vars, $sprint_id, $cum_remain, $cum_work_time, $hour_log_array) = @_;

    my $index = scalar @{$hour_log_array};

    my $today = 1000 * Mktime(Today_and_Now());
    $vars->{'end'}  = $today;
    $vars->{'last'} = $index;

    my $sprint = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
    my $spr_end;
    my $spr_start;
    if ($sprint->end_date()) {
        my ($y, $m, $d);
        $sprint->end_date() =~ /^([0-9]+)-([0-9]+)-([0-9]+)$/;
        $y = $1;
        $m = $2;
        $d = $3;
        # The day, that ends sprint lasts for (almost) 24 hours.
        $spr_end = 1000 * Mktime($y, $m, $d, 23, 59, 0);
    }
    if ($sprint->start_date()) {
        my ($y, $m, $d);
        $sprint->start_date() =~ /^([0-9]+)-([0-9]+)-([0-9]+)$/;
        $y         = $1;
        $m         = $2;
        $d         = $3;
        $spr_start = 1000 * Mktime($y, $m, $d, 0, 0, 0);
    }

    my @remaining_array;
    my @worktime_array;
    my @last_rem_plot;
    my @last_work_plot;
    my $row;
    my ($x, $y);

    my $plot_ts;

    if (!$spr_end) {
        $x = $today;
    }
    while (!$x && $index > 0) {
        $row     = @{$hour_log_array}[$index];
        $plot_ts = @{$row}[0];
        if ($spr_end > $plot_ts) {
            $x = $spr_end;
        }
        else {
            $cum_remain    = $cum_remain - @{$row}[1];       # 'added' in remain field
            $cum_remain    = $cum_remain + @{$row}[2];       # 'removed' in remain field
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

    my $passed_beginning = 0;
    while ($index > 0 && !$passed_beginning) {
        $index = $index - 1;
        $row   = @{$hour_log_array}[$index];

        if ($spr_start && $spr_start > @{$row}[0]) {
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

    return (\@remaining_array, \@worktime_array);
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
# Using 'union' clause in SQL has a drawback. Union does not repeat same database records
# more than once. It conversely combines records in union, so that each line repeats only once.
# In this case that result is not what is needed. Combining results in union is avoided
# by grouping resulting data in each sub-query in union. It means, that in the end
# resulting data has been grouped twice.
#
sub _task_hour_log {
    my ($vars, $sprint_id) = @_;

    use Bugzilla::Field;
    my $remaining_fieldid = get_field_id('remaining_time');

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        # With MySql-database it would be possible to select directly with function unix_timestamp(bug_when).
        # That would not however be database agnostic.
        "select bug_when, sum(a), sum(r), sum(w) from (
        (select
            bug_when, sum(added) as a, sum(removed) as r, null as w
        from 
            bugs_activity ba
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = ba.bug_id
        where 
            fieldid = ? and
            sprint_id = ?
	group by
	    bug_when)

        union

        (select 
            creation_ts as bug_when, 
            sum(removed) as a,
            null as r,
            null as w
        from
            bugs_activity ba1
        inner join
            scrums_sprint_bug_map sbm 
	on
            sbm.bug_id = ba1.bug_id and
            sprint_id = ?
        inner join
            bugs b
	on
            ba1.bug_id = b.bug_id
	where
            fieldid = ? and
	    not exists (select null from bugs_activity ba2
	    where ba2.bug_id = ba1.bug_id and ba2.fieldid = ? and
	    ba2.bug_when < ba1.bug_when)
	group by
	    bug_when)

        union

            (select
            creation_ts as bug_when, 
            sum(remaining_time) as a,
            null as r,
            null as w
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
            fieldid = ?)
	group by
	    bug_when)

        union

        (select
            bug_when, null as a, null as r, sum(work_time) as w
        from 
            longdescs ld
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = ld.bug_id
        where
            sprint_id = ? and 
            work_time > 0
	group by
	    bug_when)) as hours
        group by
            bug_when
        order by
            bug_when"
    );
    $sth->execute($remaining_fieldid, $sprint_id, $sprint_id, $remaining_fieldid, $remaining_fieldid, $sprint_id, $remaining_fieldid, $sprint_id);
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

sub _burndown_plot_by_items {
    my ($vars, $sprint_id) = @_;

    if ($sprint_id =~ /([0-9]+)/) {
        $sprint_id = $1;    # $data now untainted
    }
    my ($ending_remain, $ending_work_time) = _ending_item_status($sprint_id);
    my $hour_log_array = _task_status_log($sprint_id);
    my ($remaining_array, $worktime_array) = _create_plot_chart($vars, $sprint_id, $ending_remain, $ending_work_time, $hour_log_array);

    $vars->{'remaining_items_plot'} = $remaining_array;
    $vars->{'worktime_items_plot'}  = $worktime_array;
}

sub _task_status_log {
    my ($sprint_id) = @_;

    use Bugzilla::Field;
    my $bug_status_fieldid = get_field_id('bug_status');

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        "(select
            bug_when, ad_st.is_open as a, re_st.is_open as r, re_st.is_open-ad_st.is_open as w
        from 
            bugs_activity ba
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = ba.bug_id
	inner join
	    bug_status ad_st on
	    ba.added = ad_st.value
	inner join
	    bug_status re_st on
	    ba.removed = re_st.value
        where 
            fieldid = ? and
            sprint_id = ?)

        union

	(select
	    creation_ts as bug_when, 1 as a, 0 as r, 0 as w
	from
	    bugs b
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = b.bug_id
        where 
            sprint_id = ?)
        order by 
            bug_when"
                           );
    $sth->execute($bug_status_fieldid, $sprint_id, $sprint_id);
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

sub _ending_item_status {
    my ($sprint_id) = @_;

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
    my ($open,        $closed);
    while (($open_status, $count) = $sth->fetchrow_array) {
        if ($open_status == 1) {
            $open = $count;
        }
        else {
            $closed = $count;
        }
    }
    return ($open, $closed);
}

1;

__END__

=head1 NAME

Bugzilla::Extension::Scrums::Sprintslib - Scrums function library for sprint diagrams and features related to persons in sprint.


=head1 SYNOPSIS

    use Bugzilla::Extension::Scrums::Sprintslib;

    Bugzilla::Extension::Scrums::Sprintslib::handle_person_capacity($data, $vars);
    Bugzilla::Extension::Scrums::Sprintslib::sprint_summary($vars, $sprint_id);


=head1 DESCRIPTION

Sprintslib.pm is a library, that contains sprint diagram and Ajax related functionalities. It is interface to server and its functions must be called with CGI-variables in hash-map.

=head1 METHODS

=over

=item C<handle_person_capacity($data, $vars)>

 Description: Sets personal capacity of single person in sprint with Ajax-interface.

 data:        JSON-string from Ajax-interface. Contains capacity information.


=item C<sprint_summary($vars, $sprint_id)>

 Description: Returns all diagram data and table data, that is needed for representing sprint summary.

 Params:      sprint_id              - Id of a Bugzilla::Extension::Scrums::Sprint object.

 Returns:     The vars-hashref is added the following keys:
              remaining_hours_plot   - Data of remaining hours diagram 
              worktime_hours_plot    - Data of work effort hours diagram 
              remaining_items_plot   - Data of remaining items diagram 
              worktime_items_plot    - Data of work effort items diagram 
              summary                - Numbers of open and closed items
              slist                  - Number of items in each status as an array
              team_name              - Name of team from Bugzilla::Extension::Scrums::Team
              team_id                - Id (integer) of Bugzilla::Extension::Scrums::Team object
              sprint_name            - Name of sprint from Bugzilla::Extension::Scrums::Sprint

=back

=cut

