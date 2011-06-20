#!/usr/bin/perl

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
# The Initial Developer of the Original Code is "Nokia Corporation"
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Stephen Jayna <sdjayna@bayoteers.org>

package Bugzilla::Extension::Scrums::LoadTestData;

use strict;

use Data::Dumper;
use lib qw(. lib);

use Bugzilla;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::Util qw(trick_taint);

use Bugzilla::Extension::Scrums::Team;

use base qw(Exporter);

use Date::Calc qw(Today Add_Delta_Days Delta_Days Today Week_Number);

our @EXPORT = qw(
  load_test_data
  );

use constant TEAMCOUNT        => 30;
use constant TEAMSIZE         => 5;
use constant SPRINTCOUNT      => 7;
use constant SPRINTLENGTH     => 14;
use constant MAX_STORY_LENGTH => 16;

use vars qw(%data);

sub load_test_data($) {
    my ($vars) = @_;

    # Drop all existing data.
    _drop_existing_data();

    for my $i_team (1 .. TEAMCOUNT) {
        # Create a team based on an existing product.

        my ($product_id, $name) = _get_random_product();
        my $owner        = _get_random_user();
        my $scrum_master = _get_random_user();

        $vars->{'output'} .= "<p><strong>Loading Team $name</strong><br />";

        my $team = Bugzilla::Extension::Scrums::Team->create({ name => $name, owner => $owner, scrum_master => $scrum_master });
        my $backlog = _create_backlog($team->id);

        # Add members to this team.

        for my $i_member (1 .. TEAMSIZE) {
            my $member = _get_random_user();
            $vars->{'output'} .= "Adding Member $member<br />";

            $team->set_member($member);
        }

        # Get the components in this product and add them to this team's responsibilities.

        my $product = new Bugzilla::Product($product_id);
        foreach my $component (@{ $product->components }) {
            $team->set_component($component->id);
        }

        # Create sprints.

        # Figure out our starting point: the first day we're going to create a sprint for.
        my ($s_year, $s_month, $s_day) = Today(time());
        ($s_year, $s_month, $s_day) = Add_Delta_Days($s_year, $s_month, $s_day, -((SPRINTCOUNT * SPRINTLENGTH) / 1.3));

        for my $i_sprint (1 .. SPRINTCOUNT) {
            # Make the end of the sprint SPRINTLENGTH after our starting point.
            my ($year, $month, $day) = Add_Delta_Days($s_year, $s_month, $s_day, SPRINTLENGTH);

            my $s_week_number = Week_Number($s_year, $s_month, $s_day);
            my $e_week_number = Week_Number($year,   $month,   $day);

            # Mark sprints that end before today as not being active: ie. archived.
            my $is_active = 0;

            if (Delta_Days($year, $month, $day, Today()) < 0) {
                # Mark sprints that start after today as being active.
                $is_active = 1;
            }

            $vars->{'output'} .= "Creating Sprint $i_sprint Week $s_week_number -> $e_week_number Is Active? $is_active<br />";

            my $start_date = "$s_year-$s_month-$s_day";
            my $end_date   = "$year-$month-$day";

            my $sprint = _create_sprint($team->id, "NEW", 1, "Week $s_week_number-$e_week_number",
                                        $start_date, "Sprint for Week $s_week_number to Week $e_week_number",
                                        $is_active, $start_date, $end_date);

            # Find bugs that were created in the period before the sprint, and put them into the sprint.
            my ($w_year, $w_month, $w_day) = Add_Delta_Days($s_year, $s_month, $s_day, -(SPRINTLENGTH));
            my $week_earlier_date = "$w_year-$w_month-$w_day";

            my $query   = "SELECT bug_id FROM bugs WHERE creation_ts > '$week_earlier_date' and creation_ts < '$start_date' and product_id = $product_id";
            my $bug_ids = Bugzilla->dbh->selectcol_arrayref($query);

            my $s_counter = 1;
            my $b_counter = 1;
            my $counter   = 1;

            foreach my $bug_id (@{$bug_ids}) {
                my $bug = new Bugzilla::Bug($bug_id);

                $vars->{'output'} .= "Adding $bug_id to sprint " . $sprint->name . "<br /><br />";

                my $into_sprint = $counter < (TEAMSIZE * SPRINTLENGTH);

                my $estimate = int(rand(MAX_STORY_LENGTH)) + 1;

                _set_estimated_time($bug_id, $estimate, $start_date, 0);
                _set_remaining_time($bug_id, $estimate, $start_date, 0);

                # Put some bugs submitted during this period into the sprint, and some into the backlog.
                if ($into_sprint) {
                    Bugzilla->dbh->do('INSERT INTO scrums_sprint_bug_map (bug_id, sprint_id) values (?, ?)', undef, $bug_id, $sprint->id);
                    Bugzilla->dbh->do('INSERT INTO scrums_bug_order (bug_id, team) values (?, ?)',           undef, $bug_id, $s_counter);

                    $s_counter++;
                }
                else {
                    Bugzilla->dbh->do('INSERT INTO scrums_sprint_bug_map (bug_id, sprint_id) values (?, ?)', undef, $bug_id, $backlog->id);
                    Bugzilla->dbh->do('INSERT INTO scrums_bug_order (bug_id, team) values (?, ?)',           undef, $bug_id, $b_counter);

                    $b_counter++;
                }

                if ($into_sprint) {
                    my $days = 0;

                    # Now for each day in the sprint increase the amount of actual work done on the bug
                    while ($days < SPRINTLENGTH) {
                        #Re-fetch bug.
                        $bug = new Bugzilla::Bug($bug_id);

                        if ($bug->remaining_time > 0) {
                            my ($t_year, $t_month, $t_day) = Add_Delta_Days($s_year, $s_month, $s_day, $days);

                            my $today_date = "$t_year-$t_month-$t_day";
                            my $work_done  = int(rand($estimate + 2));    # Ensure that when estimate reaches 1 we get a result of 0 or 1

                            if ($work_done < 0) {
                                $work_done = 0;
                            }
                            else{
                                _set_work_time($bug_id, $work_done, $today_date, 1);
                            }

                            if ($work_done) {
                                my $new_remaining_time = $bug->remaining_time - $work_done;

                                if ($new_remaining_time < 0) {
                                    $new_remaining_time = 0;
                                }

                                _set_remaining_time($bug_id, $new_remaining_time, $today_date, 1);
                            }

                            $bug = new Bugzilla::Bug($bug_id);
                            $vars->{'output'} .= "Estimate $estimate Work Done: $work_done Remaining: " . $bug->remaining_time . "<br />";
                        }
                        $days++;
                    }
                    $vars->{'output'} .= "<br />";
                }

                $counter++;
            }

            # Move the starting point along by SPRINTLENGTH.
            ($s_year, $s_month, $s_day) = ($year, $month, $day);
        }

        $vars->{'output'} .= "</p>";
    }

    $vars->{'output'} .= '<p>Loaded Complete</p>';
}

sub _set_work_time($$$$) {
    my ($bug_id, $work_time, $bug_when, $log) = @_;

    my $bug = new Bugzilla::Bug($bug_id);

    my $wt = sprintf("%.2f", $work_time);

    my $command = "INSERT INTO longdescs (bug_id, who, bug_when, thetext, work_time) VALUES (?,?,?,?,?)";
    
    Bugzilla->dbh->do($command, undef, $bug_id, $bug->assigned_to->id, $bug_when,
                          'Logging Hours',
                          $wt,
                          );
}

sub _set_remaining_time($$$$) {
    my ($bug_id, $new_remaining_time, $bug_when, $log) = @_;

    my $bug = new Bugzilla::Bug($bug_id);

    my $old_remaining_time = $bug->remaining_time;

    my $nrt = sprintf("%.2f", $new_remaining_time);

    my $command = "UPDATE bugs SET remaining_time = ? WHERE bug_id = ?";
    Bugzilla->dbh->do($command, undef, $nrt, $bug_id);

    if ($log) {
        $command = "INSERT INTO bugs_activity (bug_id, who, bug_when, fieldid, added, removed) VALUES (?,?,?,?,?,?)";
        Bugzilla->dbh->do($command, undef, $bug_id, $bug->assigned_to->id, $bug_when,
                          get_field_id('remaining_time'),
                          $nrt,
                          $old_remaining_time);
    }
}

sub _set_estimated_time($$$$) {
    my ($bug_id, $new_estimated_time, $bug_when, $log) = @_;

    my $bug = new Bugzilla::Bug($bug_id);

    my $old_estimated_time = $bug->estimated_time;

    my $command = "UPDATE bugs SET estimated_time = ? WHERE bug_id = ?";
    Bugzilla->dbh->do($command, undef, $new_estimated_time, $bug_id);

    if ($log) {
        $command = "INSERT INTO bugs_activity (bug_id, who, bug_when, fieldid, added, removed) VALUES (?,?,?,?,?,?)";
        Bugzilla->dbh->do($command, undef, $bug_id, $bug->assigned_to->id, $bug_when,
                          get_field_id('estimated_time'),
                          sprintf("%.2f", $new_estimated_time),
                          $old_estimated_time);
    }
}

sub _create_backlog($) {
    my ($team_id) = @_;

    # Create a backlog, which is actually just a sprint in thin disguise.

    my ($backlog) =
      _create_sprint($team_id, "NEW", 2, "Product Backlog", "2000-01-01", "Automatically generated sprint that represents the Product Backlog", 1);

    return $backlog;
}

sub _create_sprint(@) {
    my ($team_id, $status, $item_type, $name, $nominal_schedule, $description, $is_active, $start_date, $end_date) = @_;

    if (!$start_date) {
        $start_date = "2000-01-01";
    }

    if (!$end_date) {
        $end_date = "2000-01-01";
    }

    # Create a sprint.

    my $sprint = Bugzilla::Extension::Scrums::Sprint->create(
                                                             {
                                                               team_id          => $team_id,
                                                               status           => $status,
                                                               item_type        => $item_type,
                                                               name             => $name,
                                                               nominal_schedule => $nominal_schedule,
                                                               description      => $description,
                                                               is_active        => $is_active,
                                                               start_date       => $start_date,
                                                               end_date         => $end_date,
                                                             }
                                                            );

    return $sprint;
}

sub _drop_existing_data() {
    my $dbh = Bugzilla->dbh;

    # Drop all existing data in scrums_* tables.

    my @tables = (
                  'scrums_bug_order', 'scrums_componentteam', 'scrums_flagtype_release_map', 'scrums_releases',
                  'scrums_sprints',   'scrums_team',          'scrums_teammember',           'scrums_sprint_bug_map'
                 );

    $dbh->bz_start_transaction();

    foreach my $table (@tables) {
        Bugzilla->dbh->do("delete from $table");
    }

    Bugzilla->dbh->do("delete from bugs_activity where fieldid=" . get_field_id('remaining_time'));

    $dbh->bz_commit_transaction();
}

sub _get_random_user() {
    my $dbh = Bugzilla->dbh;

    # Get random user, that hasn't been previously used during this run.

    my $user_id;

    do {
        my $query = "SELECT userid FROM profiles WHERE disabledtext = '' ORDER BY rand() limit 1;";
        $user_id = Bugzilla->dbh->selectrow_array($query);

    } until !$data{'user'}{$user_id};

    $data{'user'}{$user_id} = 1;

    return $user_id;
}

sub _get_random_product() {
    my $dbh = Bugzilla->dbh;

    # Get random product, that hasn't been previously used during this run.

    my ($id, $name);

    do {
        my $query = "SELECT id,name FROM products WHERE name LIKE 'H-%' or name LIKE 'Other' ORDER BY rand() limit 1;";
        ($id, $name) = Bugzilla->dbh->selectrow_array($query);

    } until !$data{'product'}{$id};

    $data{'product'}{$id} = 1;

    return ($id, $name);
}

1;
