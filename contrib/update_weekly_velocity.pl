#!/usr/bin/perl -wT
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
# The Initial Developer of the Original Code is "Nokia Corporation"
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Visa Korhonen <visa.korhonen@symbio.com>

use Bugzilla;

use Date::Calc qw(Monday_of_Week);

sub main {
    my ($time_span_start, $time_span_end) = _create_time_span();

    my $query = _create_sql($time_span_start, $time_span_end);

    _update_teams($query, $time_span_start, $time_span_end);
}

sub _update_teams {
    my ($query, $time_span_start, $time_span_end) = @_;

    $dbh = Bugzilla->dbh;
    my $sth_query = $dbh->prepare($query);
    $sth_query->execute();

    my $team_id, $weekly_velocity;

    while (($team_id, $weekly_velocity) = $sth_query->fetchrow_array) {
        my $update_query = "update scrums_team set weekly_velocity_value = $weekly_velocity,
		weekly_velocity_start='$time_span_start', weekly_velocity_end='$time_span_end' where id=$team_id";
        my $sth_update_query = $dbh->prepare($update_query);
        $sth_update_query->execute();
    }
}

# Here is two versions of select. They have different formula for fetching hours.

# This select gets all tasks regardless of whether they are open, closed or re-opened.
# Those hours, that have been reported during time span, are calculated.

sub _create_sql_version1 {
    my ($time_span_start, $time_span_end) = @_;

    my $query = "select
		ct.teamid,
		sum(ld.work_time)
	from bugs b
		inner join longdescs ld	on		b.bug_id 	= ld.bug_id
		inner join scrums_componentteam ct on 	b.component_id 	= ct.component_id 
	where
		b.bug_severity = 'task' and
		ld.work_time > 0 and
		bug_when > '" . $time_span_start . "' and 
		bug_when < '" . $time_span_end . "'
	group by
		ct.teamid";

    return $query;
}

# This select gets tasks, that have been closed. Tasks, that are not finished yet, are left out.
# Tasks are selected according to closing date. Other timespan does not have any effect.
# If task is closed and later reopened during successive period,
# resulting hours are left out from later runs, because closing date is what counts.

sub _create_sql {
    my ($time_span_start, $time_span_end) = @_;

    my $query = "select 
		clsdtask.teamid, 
		sum(ld.work_time) 
	from 
	(select 
		ct.teamid as teamid,
		b.bug_id as bugi,
		min(ba.bug_when) as aika
	from bugs b
		inner join bugs_activity ba		on b.bug_id		= ba.bug_id		 		
		inner join scrums_componentteam ct 	on b.component_id 	= ct.component_id 
	where
		b.bug_severity = 'task' and
		ba.added = 'RESOLVED'
	group by 
		ct.teamid,
		b.bug_id) as clsdtask
		inner join longdescs ld			on clsdtask.bugi 	= ld.bug_id
	where 
		aika > '" . $time_span_start . "' and 
		aika < '" . $time_span_end . "' 
	group by
		clsdtask.teamid";

    return $query;
}

sub _create_time_span {
    my (undef, undef, undef, $localtime_day, $localtime_month, $localtime_year) = localtime();

    my $today = DateTime->new(
                              year  => $localtime_year + 1900,
                              month => $localtime_month + 1,
                              day   => $localtime_day,
                             );
    # print "Today: ", $today->day(), ".", $today->month(), ".",  $today->year(), "\n";
    my $today_week = $today->week();
    my $today_year = $today->year();

    # Convert the year / week into a date.
    my ($monday_year, $monday_month, $monday_day) = Monday_of_Week($today_week, $today_year);
    # print "Monday: ", $monday_day, ".", $monday_month, ".",  $monday_year, "\n";

    my $monday = DateTime->new(
                               year  => $monday_year,
                               month => $monday_month,
                               day   => $monday_day,
                              );

    # Left pad month and day numbers with a zero if required.
    $monday_month = sprintf("%02d", $monday_month);
    $monday_day   = sprintf("%02d", $monday_day);
    my $end_limit = $monday_year . "-" . $monday_month . "-" . $monday_day;
    my $d_one_week = DateTime::Duration->new(days => 7);

    # Remove 7 days from monday.
    $monday->subtract_duration($d_one_week);
    $monday_year  = $monday->year();
    $monday_month = $monday->month();
    $monday_day   = $monday->day();

    # Left pad month and day numbers with a zero if required.
    $monday_month = sprintf("%02d", $monday_month);
    $monday_day   = sprintf("%02d", $monday_day);
    my $start_limit = $monday_year . "-" . $monday_month . "-" . $monday_day;
    #    print "Last monday: ", $monday->day(), ".", $monday->month(), ".",  $monday->year(), "\n\n";
    #    print "Start limit: ", $start_limit, " End limit: ", $end_limit, "\n\n";

    return ($start_limit, $end_limit);
}

main();
