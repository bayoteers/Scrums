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
#   Stephen Jayna <ext-stephen.jayna@nokia.com>

package Bugzilla::Extension::Scrums;

use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;

use Bugzilla::Extension::Scrums::Teams;
use Bugzilla::Extension::Scrums::Releases;
use Bugzilla::Extension::Scrums::Sprintslib;
use Bugzilla::Extension::Scrums::LoadTestData;
use Bugzilla::Extension::Scrums::DebugLibrary;

use Bugzilla::Util qw(trick_taint);

our $VERSION = '1.0';

use constant CONST_FEATURE => "feature";
use constant CONST_TASK    => "task";

sub bug_end_of_update {
    my ($self, $args) = @_;

    my ($bug, $old_bug, $timestamp, $changes) = @$args{qw(bug old_bug timestamp changes)};

    if (my $status_change = $changes->{'bug_status'} and ($bug->bug_severity() eq CONST_FEATURE or $bug->bug_severity() eq CONST_TASK)) {
        my $old_status = new Bugzilla::Status({ name => $status_change->[0] });
        my $new_status = new Bugzilla::Status({ name => $status_change->[1] });

        if (!$new_status->is_open && $old_status->is_open) {
            # close ! It seems, that remaining time can not be tested because it is set zero while closing.
            my $estimated_time = $bug->estimated_time();
            my $actual_time    = $bug->actual_time();

            my $filling_forced                = 0;
            my $precondition_enabled_severity = Bugzilla->params->{"scrums_precondition_enabled_severity"};

            foreach my $enabled_severity (@$precondition_enabled_severity) {
                if ($enabled_severity eq $bug->bug_severity()) {
                    $filling_forced = 1;
                }
            }

            if ($filling_forced) {
                if ($estimated_time == 0) {
                    ThrowUserError("scrums_estimated_time_required");
                }
                elsif ($actual_time == 0) {
                    ThrowUserError("scrums_actual_time_required");
                }
            }
        }
    }

    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;

    # If the initial description has been updated we need
    # to take care of updated the database to reflect this.

    # Find out whether the user is a member of the group
    # that can change the initial description.

    # This ensures we only apply this change to the bug that
    # is being updated. Not, for example, a bug that is having
    # duplicate notation added to it.
    if ($bug->bug_id eq $cgi->param('id')) {
        if (Bugzilla->user->in_group('setfeature')) {
            # Current bug description
            my $description = ${ @{ $bug->comments }[0] }{'thetext'};

            # Current bug descriptions comment id (in longdescs table)
            my $comment_id = ${ @{ $bug->comments }[0] }{'comment_id'};

            # Possibly new description
            my $thetext = $cgi->param('comment_text_0');

            if ($thetext) {
                trick_taint($thetext);

                # Taken from Bug (_check_comment) ~ Line 1152
                $thetext =~ s/\s*$//s;
                $thetext =~ s/\r\n?/\n/g;    # Get rid of \r.

                if ($description ne $thetext) {
                    # There has been a change, update the description.

                    $dbh->do('UPDATE longdescs SET thetext = ? WHERE bug_id = ? and comment_id = ?', undef, $thetext, $bug->bug_id, $comment_id);

                    # Append a comment to the end of the bug stating that
                    # the description has been updated.

                    $thetext = "The feature's description has been updated.\n";

                    my $delta_ts = $dbh->selectrow_array("SELECT NOW()");

                    $dbh->do(
                        "INSERT INTO longdescs (bug_id, who, bug_when, thetext)
                      VALUES (?,?,?,?)", undef,
                        $bug->bug_id, Bugzilla->user->id, $delta_ts, $thetext
                            );
                }
            }
        }
    }

    my $scrums_action = $cgi->param('scrums_action');
    if ($scrums_action =~ /^(\d+)$/) {
        $scrums_action = $1;
        if ($scrums_action > -1) {
            if (not Bugzilla->user->in_group('scrums_editteams')) {
                ThrowUserError('auth_failure', { group => "scrums_editteams", action => "edit", object => "sprint" });
            }

            my $sprnt = Bugzilla::Extension::Scrums::Sprint->new($scrums_action);
            my $team  = $sprnt->get_team();
            if (!$team->is_team_responsible_for_component_id($bug->{component_id})) {
                my $responsible = $team->team_of_component($bug->{component_id});
                my $resp_name   = "[none]";
                if ($responsible) {
                    $resp_name = $responsible->name();
                }
                my $comp_name = $bug->component();
                ThrowUserError("scrums_not_responsible_team", { bug_id => $bug->bug_id, responsible_team_name => $resp_name, comp_name => $comp_name });
            }
            $sprnt->add_bug_into_sprint($bug->bug_id);
        }
    }

    return;
}

sub buglist_supptables {
    my ($self, $args) = @_;

    my $supptables = $args->{'supptables'};
    my $fields     = $args->{'fields'};

    # Add this table to what can be referenced in MySQL when displaying search results.

    foreach my $field (@$fields) {
        if (($field eq 'scrums_team_order') || ($field eq 'scrums_release_order') || ($field eq 'scrums_program_order')) {
            push(@$supptables, 'LEFT JOIN scrums_bug_order ON scrums_bug_order.bug_id = bugs.bug_id');
        }
        elsif ($field eq 'scrums_blocked') {
            push(@$supptables, 'LEFT JOIN dependencies ON dependencies.dependson = bugs.bug_id');
        }
        elsif ($field eq 'sprint_name') {
            push(@$supptables, 'LEFT JOIN scrums_sprint_bug_map ON scrums_sprint_bug_map.bug_id = bugs.bug_id');
            push(@$supptables, 'LEFT JOIN scrums_sprints ON scrums_sprints.id = scrums_sprint_bug_map.sprint_id ');
        }
    }

    return;
}

sub buglist_columns {
    my ($self, $args) = @_;

    my $columns = $args->{'columns'};

    # Describe how to access the extra columns described in colchange_columns()
    $columns->{'scrums_team_order'}    = { 'name' => 'scrums_bug_order.team',    'title' => 'Team Order' };
    $columns->{'scrums_release_order'} = { 'name' => 'scrums_bug_order.rlease',  'title' => 'Release Order' };
    $columns->{'scrums_program_order'} = { 'name' => 'scrums_bug_order.program', 'title' => 'Program Order' };
    $columns->{'scrums_blocked'}       = { 'name' => 'dependencies.blocked',     'title' => 'Parent' };

    $columns->{'sprint_name'} = { 'name' => 'scrums_sprints.name', 'title' => 'Sprint' };

    return;
}

sub colchange_columns {
    my ($self, $args) = @_;

    my $columns = $args->{'columns'};

    # Make these columns available for diplaying in the colchange.cgi dialog
    push(@$columns, "scrums_team_order");
    push(@$columns, "scrums_release_order");
    push(@$columns, "scrums_program_order");
    push(@$columns, "scrums_blocked");

    push(@$columns, "sprint_name");

    return;
}

sub buglist_supp_legal_fields {
    my ($self, $args) = @_;

    my $fields = $args->{'fields'};
    my $supp_fields = eval { Bugzilla::Field->match({ name => 'scrums_sprint_bug_map.sprint_id' }) } || [];

    if (@{$supp_fields}) {
        push(@{$fields}, @{$supp_fields}[0]);
    }
    else {
        my $sprint = Bugzilla::Field->create({ name => 'scrums_sprint_bug_map.sprint_id', description => 'Sprint ID' });
        push(@{$fields}, $sprint);
    }

    return;
}

sub db_schema_abstract_schema {
    my ($self, $args) = @_;

    my $schema = $args->{schema};

    # extension table for 'bugs': includes order nr for programme, release, team
    $schema->{'scrums_bug_order'} = {
                                      FIELDS => [
                                                  bug_id => {
                                                              TYPE       => 'INT3',
                                                              NOTNULL    => 1,
                                                              PRIMARYKEY => 1,
                                                              REFERENCES => {
                                                                              TABLE  => 'bugs',
                                                                              COLUMN => 'bug_id',
                                                                              DELETE => 'CASCADE'
                                                                            }
                                                            },
                                                  team    => { TYPE => 'INT3' },
                                                  rlease  => { TYPE => 'INT3' },
                                                  program => { TYPE => 'INT3' },
                                                ]
                                    };

    # "componentteam" indicates, that sub-component (component in database) has been assigned responsible team.
    $schema->{'scrums_componentteam'} = {
                                          FIELDS => [
                                                      component_id => {
                                                                        TYPE       => 'INT2',
                                                                        NOTNULL    => 1,
                                                                        PRIMARYKEY => 1,
                                                                        REFERENCES => {
                                                                                        TABLE  => 'components',
                                                                                        COLUMN => 'id',
                                                                                        DELETE => 'CASCADE'
                                                                                      }
                                                                      },
                                                      teamid => {
                                                                  TYPE       => 'INT2',
                                                                  NOTNULL    => 1,
                                                                  REFERENCES => {
                                                                                  TABLE  => 'scrums_team',
                                                                                  COLUMN => 'id',
                                                                                  DELETE => 'CASCADE'
                                                                                }
                                                                },
                                                    ],
                                        };

    # "scrums_flagtype_release_map" maps allowed flag types into releases
    $schema->{'scrums_flagtype_release_map'} = {
                                                 FIELDS => [
                                                             release_id => {
                                                                             TYPE       => 'INT2',
                                                                             NOTNULL    => 1,
                                                                             REFERENCES => {
                                                                                             TABLE  => 'scrums_releases',
                                                                                             COLUMN => 'id',
                                                                                             DELETE => 'CASCADE'
                                                                                           }
                                                                           },
                                                             flagtype_id => {
                                                                              TYPE       => 'INT2',
                                                                              NOTNULL    => 1,
                                                                              REFERENCES => {
                                                                                              TABLE  => 'flagtypes',
                                                                                              COLUMN => 'id',
                                                                                              DELETE => 'CASCADE'
                                                                                            }
                                                                            },
                                                           ],
                                               };

    # "release" is managed unit, that contains tasks
    $schema->{'scrums_releases'} = {
                                     FIELDS => [
                                                 id                     => { TYPE => 'SMALLSERIAL',  NOTNULL => 1, PRIMARYKEY => 1 },
                                                 name                   => { TYPE => 'varchar(255)', NOTNULL => 1 },
                                                 target_milestone_begin => { TYPE => 'varchar(20)' },
                                                 target_milestone_end   => { TYPE => 'varchar(20)' },
                                                 capacity_algorithm     => { TYPE => 'varchar(255)' },
                                                 original_capacity      => { TYPE => 'INT3' },
                                                 remaining_capacity     => { TYPE => 'INT3' },
                                               ],
                                   };

    $schema->{'scrums_sprints'} = {
                                    FIELDS => [
                                                id      => { TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1 },
                                                team_id => {
                                                             TYPE       => 'INT2',
                                                             NOTNULL    => 1,
                                                             REFERENCES => {
                                                                             TABLE  => 'scrums_team',
                                                                             COLUMN => 'id',
                                                                             DELETE => 'CASCADE'
                                                                           }
                                                           },
                                                name        => { TYPE => 'varchar(255)', NOTNULL => 1 },
                                                status      => { TYPE => 'varchar(20)',  NOTNULL => 1 },
                                                description => { TYPE => 'varchar(255)' },
                                                item_type          => { TYPE => 'INT2', NOTNULL => 1, DEFAULT => '1' },
                                                start_date         => { TYPE => 'DATE' },
                                                end_date           => { TYPE => 'DATE' },
                                                estimated_capacity => { TYPE => 'decimal(7,2)' },
                                              ]
                                  };

    # "team" is unit, which is reponsible for sub-component (component in database).
    $schema->{'scrums_team'} = {
                                 FIELDS => [
                                             id => {
                                                     TYPE       => 'SMALLSERIAL',
                                                     NOTNULL    => 1,
                                                     PRIMARYKEY => 1
                                                   },
                                             name  => { TYPE => 'varchar(50)', NOTNULL => 1 },
                                             owner => {
                                                        TYPE       => 'INT3',
                                                        NOTNULL    => 1,
                                                        REFERENCES => {
                                                                        TABLE  => 'profiles',
                                                                        COLUMN => 'userid',
                                                                        DELETE => 'CASCADE'
                                                                      }
                                                      },
                                             scrum_master => {
                                                               TYPE       => 'INT3',
                                                               REFERENCES => {
                                                                               TABLE  => 'profiles',
                                                                               COLUMN => 'userid',
                                                                               DELETE => 'CASCADE'
                                                                             }
                                                             },
                                             weekly_velocity_value => { TYPE => 'decimal(7,2)' },
                                             weekly_velocity_start => { TYPE => 'DATE' },
                                             weekly_velocity_end   => { TYPE => 'DATE' },
                                           ],
                               };

    # "teammember" is user, who belongs to team.
    $schema->{'scrums_teammember'} = {
                                       FIELDS => [
                                                   teamid => {
                                                               TYPE       => 'INT2',
                                                               NOTNULL    => 1,
                                                               REFERENCES => {
                                                                               TABLE  => 'scrums_team',
                                                                               COLUMN => 'id',
                                                                               DELETE => 'CASCADE'
                                                                             }
                                                             },
                                                   userid => {
                                                               TYPE       => 'INT3',
                                                               NOTNULL    => 1,
                                                               REFERENCES => {
                                                                               TABLE  => 'profiles',
                                                                               COLUMN => 'userid',
                                                                               DELETE => 'CASCADE'
                                                                             }
                                                             },
                                                 ],
                                       INDEXES => [
                                                    scrums_teammember_value_unique_idx => {
                                                                                            FIELDS => [qw(teamid userid)],
                                                                                            TYPE   => 'UNIQUE'
                                                                                          },
                                                  ],
                                     };

    $schema->{'scrums_sprint_bug_map'} = {
                                           FIELDS => [
                                                       bug_id => {
                                                                   TYPE       => 'INT3',
                                                                   NOTNULL    => 1,
                                                                   REFERENCES => {
                                                                                   TABLE  => 'bugs',
                                                                                   COLUMN => 'bug_id',
                                                                                   DELETE => 'CASCADE'
                                                                                 }
                                                                 },
                                                       sprint_id => {
                                                                      TYPE       => 'INT2',
                                                                      NOTNULL    => 1,
                                                                      REFERENCES => {
                                                                                      TABLE  => 'scrums_sprints',
                                                                                      COLUMN => 'id',
                                                                                      DELETE => 'CASCADE'
                                                                                    }
                                                                    },
                                                     ]
                                         };

    # "scrums_sprint_estimate" is sprint capacity of a user, who belongs to team.
    $schema->{'scrums_sprint_estimate'} = {
                                            FIELDS => [
                                                        sprintid => {
                                                                      TYPE       => 'INT2',
                                                                      NOTNULL    => 1,
                                                                      REFERENCES => {
                                                                                      TABLE  => 'scrums_sprints',
                                                                                      COLUMN => 'id',
                                                                                      DELETE => 'CASCADE'
                                                                                    }
                                                                    },
                                                        userid => {
                                                                    TYPE       => 'INT3',
                                                                    NOTNULL    => 1,
                                                                    REFERENCES => {
                                                                                    TABLE  => 'profiles',
                                                                                    COLUMN => 'userid',
                                                                                    DELETE => 'CASCADE'
                                                                                  }
                                                                  },
                                                        estimated_capacity => { TYPE => 'decimal(4,2)', NOTNULL => 1, DEFAULT => '0.00' },
                                                      ],
                                            INDEXES => [
                                                         scrums_sprint_estimate_unique_idx => {
                                                                                                FIELDS => [qw(sprintid userid)],
                                                                                                TYPE   => 'UNIQUE'
                                                                                              },
                                                       ],
                                          };
}

sub install_update_db {
    use constant WV_VALUE_DEFINITION => { TYPE => 'decimal(7,2)' };
    use constant WV_START_DEFINITION => { TYPE => 'DATE' };
    use constant WV_END_DEFINITION   => { TYPE => 'DATE' };

    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_value", WV_VALUE_DEFINITION, undef);
    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_start", WV_START_DEFINITION, undef);
    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_end",   WV_END_DEFINITION,   undef);

    use constant SPRINT_TYPE_DEFINITION => { TYPE => 'INT2', NOTNULL => 1, DEFAULT => '1' };
    use constant SPRINT_START_DATE_DEFINITION => { TYPE => 'DATE' };
    use constant SPRINT_END_DATE_DEFINITION   => { TYPE => 'DATE' };

    Bugzilla->dbh->bz_add_column("scrums_sprints", "item_type",  SPRINT_TYPE_DEFINITION,       undef);
    Bugzilla->dbh->bz_add_column("scrums_sprints", "start_date", SPRINT_START_DATE_DEFINITION, undef);
    Bugzilla->dbh->bz_add_column("scrums_sprints", "end_date",   SPRINT_END_DATE_DEFINITION,   undef);

    use constant TEAM_SCRUM_MASTER => {
                                        TYPE       => 'INT3',
                                        REFERENCES => {
                                                        TABLE  => 'profiles',
                                                        COLUMN => 'userid',
                                                        DELETE => 'CASCADE'
                                                      }
                                      };
    Bugzilla->dbh->bz_add_column("scrums_team", "scrum_master", TEAM_SCRUM_MASTER, undef);

    use constant CAPACITY_DEFINITION => { TYPE => 'decimal(7,2)' };

    Bugzilla->dbh->bz_add_column("scrums_sprints", "estimated_capacity", CAPACITY_DEFINITION, undef);

    Bugzilla->dbh->bz_drop_column("scrums_sprints", "nominal_schedule");
    Bugzilla->dbh->bz_drop_column("scrums_sprints", "is_active");

    use constant USAGE_FLAG_DEFINITION => { TYPE => 'INT2', NOTNULL => 1, DEFAULT => '1' };
    Bugzilla->dbh->bz_add_column("scrums_team", "is_using_backlog", USAGE_FLAG_DEFINITION, undef);

    return;
}

sub install_before_final_checks {
    my ($self, $args) = @_;

    my $name        = "scrums_editteams";
    my $description = "Can edit responsible teams";
    my $isbuggroup  = 1;
    my $isactive    = 0;
    my $group       = new Bugzilla::Group({ name => $name });
    if (!$group) {
        my $old_name = "editteams";
        $group = new Bugzilla::Group({ name => $old_name, description => $description });
        if ($group) {
            $group->set_name($name);
            $group->update();
        }
        else {
            $group = Bugzilla::Group->create({ name => $name, description => $description, isbuggroup => $isbuggroup, isactive => $isactive });
        }
    }
}

sub page_before_template {
    my ($self, $args) = @_;

    my ($vars, $page) = @$args{qw(vars page_id)};

    # User is stored as variable for user authorization
    $vars->{'user'} = Bugzilla->user;

    # Loading Test Data

    if ($page eq 'scrums/loadtestdata.html') {
        load_test_data($vars);
    }
    if ($page eq 'scrums/testing_utility.html') {
        my $cgi    = Bugzilla->cgi;
        my $action = $cgi->param('action');
        if ($action eq "add") {
            debug_function1($vars);
        }
        elsif ($action eq "remove") {
            debug_function2($vars);
        }
        elsif ($action eq "add_n_move") {
            debug_function3($vars);
        }
        elsif ($action eq "move2") {
            debug_function4($vars);
        }

        if ($action eq "set2func1") {
            debug_set2_func1($vars);
        }
    }

    # Teams
    elsif ($page eq 'scrums/scrums.html') {
        my $teams = Bugzilla::Extension::Scrums::Team->user_teams(Bugzilla->user->id());
        $vars->{'teams'} = $teams;

        my @sprints;
        for my $team (@{$teams}) {
            my $sprint = $team->get_team_current_sprint();
            # When there is no active sprint, undef is pushed.
            push(@sprints, $sprint);
        }
        $vars->{'sprints'} = \@sprints;
    }
    elsif ($page eq 'scrums/allteams.html') {
        Bugzilla::Extension::Scrums::Teams::show_all_teams($vars);
    }
    elsif ($page eq 'scrums/createteam.html') {
        Bugzilla::Extension::Scrums::Teams::show_create_team($vars);
    }
    elsif ($page eq 'scrums/addintoteam.html') {
        if (not Bugzilla->user->in_group('scrums_editteams')) {
            ThrowUserError('auth_failure', { group => "scrums_editteams", action => "edit", object => "team" });
        }

        Bugzilla::Extension::Scrums::Teams::add_into_team($vars);
    }
    elsif ($page eq 'scrums/searchperson.html') {
        Bugzilla::Extension::Scrums::Teams::search_person($vars);
    }
    elsif ($page eq 'scrums/newteam.html') {
        Bugzilla::Extension::Scrums::Teams::edit_team($vars);
    }
    elsif ($page eq 'scrums/ajaxsprintbugs.html') {

        my $cgi    = Bugzilla->cgi;
        my $schema = "";
        $schema = $cgi->param('schema');
        if ($schema && $schema eq "newsprint") {
            $vars->{'editsprint'} = 1;
            $cgi->param(-name => 'editsprint', -value => 'true');
            my $sprintid = _new_sprint($vars);
            $cgi->param(-name => 'sprintid', -value => $sprintid);
            Bugzilla::Extension::Scrums::Teams::ajax_sprint_bugs($vars);
        }
        elsif ($schema && $schema eq "editsprint") {
            $vars->{'editsprint'} = 1;
            Bugzilla::Extension::Scrums::Teams::show_team_and_sprints($vars);
            Bugzilla::Extension::Scrums::Teams::ajax_sprint_bugs($vars);

        }
        else {
            Bugzilla::Extension::Scrums::Teams::ajax_sprint_bugs($vars);
        }
    }
    elsif ($page eq 'scrums/ajaxbuglist.html') {
        my $cgi       = Bugzilla->cgi;
        my $action    = $cgi->param('action');
        my $team_id   = $cgi->param('team_id');
        my $sprint_id = $cgi->param('sprint_id');
        if ($action && $action eq "unprioritised_items") {
            my $team = Bugzilla::Extension::Scrums::Team->new($team_id);
            $vars->{'buglist'} = $team->unprioritised_items();
        }
        elsif ($action && $action eq "unprioritised_bugs") {
            my $team = Bugzilla::Extension::Scrums::Team->new($team_id);
            $vars->{'buglist'} = $team->unprioritised_bugs();
        }
        elsif ($action && $action eq "other_items_than_in_active_sprint") {
            # This includes also items in backlog (which is disabled)
            my $team = Bugzilla::Extension::Scrums::Team->new($team_id);
            $vars->{'buglist'} = $team->all_items_not_in_sprint();
        }
        else {
            my $sprint = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
            $vars->{'buglist'} = $sprint->get_bugs();
        }
    }
    elsif ($page eq 'scrums/teambugs.html' || $page eq 'scrums/dailysprint.html' || $page eq 'scrums/backlogplanning.html') {
        Bugzilla::Extension::Scrums::Teams::show_team_and_sprints($vars);
    }
    elsif ($page eq 'scrums/archivedsprints.html') {
        Bugzilla::Extension::Scrums::Teams::show_archived_sprints($vars);
    }
    elsif ($page eq "scrums/ajax.html") {
        my $cgi    = Bugzilla->cgi;
        my $schema = $cgi->param('schema');

        if ($schema eq "personcapacity") {
            my $data = $cgi->param('data');
            Bugzilla::Extension::Scrums::Sprintslib::handle_person_capacity($data, $vars);
        }
        elsif ($schema eq "release") {
            handle_release_bug_data($vars);
        }
        elsif ($schema eq "backlog") {
            Bugzilla::Extension::Scrums::Teams::update_team_bugs($vars, 1);
        }
        else {
            Bugzilla::Extension::Scrums::Teams::update_team_bugs($vars, 1);
        }
    }
    elsif ($page eq 'scrums/newsprint.html') {
        Bugzilla::Extension::Scrums::Teams::edit_sprint($vars);
    }

    # Releases

    if ($page eq 'scrums/allreleases.html') {
        all_releases($vars);
    }
    elsif ($page eq 'scrums/createrelease.html') {
        create_release($vars);
    }
    elsif ($page eq 'scrums/newrelease.html') {
        edit_release($vars);
    }
    elsif ($page eq 'scrums/releasebugs.html') {
        show_release_bugs($vars);
    }
    elsif ($page eq 'scrums/choose-classification.html') {
        my $cgi             = Bugzilla->cgi;
        my $team_id         = $cgi->param('teamid');
        my @classifications = Bugzilla::Classification->get_all();

        $vars->{'classifications'} = \@classifications;
        $vars->{'target'}          = "page.cgi?id=scrums/choose-product.html&teamid=" . $team_id;
    }
    elsif ($page eq 'scrums/choose-product.html') {
        my $cgi                 = Bugzilla->cgi;
        my $team_id             = $cgi->param('teamid');
        my $class_name          = $cgi->param('classification');
        my $classification_list = Bugzilla::Classification->match({ name => $class_name });
        my $classification      = @$classification_list[0];
        my $enterable_products  = $classification->products();
        my @classifications     = ({ object => $classification, products => $enterable_products });

        $vars->{'classifications'} = \@classifications;
        $vars->{'target'}          = "page.cgi?id=scrums/choose-component.html&teamid=" . $team_id;
    }
    elsif ($page eq 'scrums/choose-component.html') {
        my $cgi          = Bugzilla->cgi;
        my $team_id      = $cgi->param('teamid');
        my $product_name = $cgi->param('product');
        my $products     = Bugzilla::Product->match({ name => $product_name });

        if (scalar @{$products} > 0) {
            $vars->{'product'} = @$products[0];
        }

        $vars->{'target'} = "page.cgi?id=scrums/createteam.html&teamid=" . $team_id;
    }
    elsif ($page eq 'scrums/sprintburndown.html') {
        my $cgi       = Bugzilla->cgi;
        my $sprint_id = $cgi->param('sprintid');

        Bugzilla::Extension::Scrums::Sprintslib::sprint_summary($vars, $sprint_id);
    }

    return;
}

sub config {
    my ($self, $args) = @_;

    my $config = $args->{config};
    $config->{Scrums} = "Bugzilla::Extension::Scrums::ConfigScrums";

    return;
}

sub config_add_panels {
    my ($self, $args) = @_;

    my $modules = $args->{panel_modules};
    $modules->{Scrums} = "Bugzilla::Extension::Scrums::ConfigScrums";

    return;
}

sub template_before_process {
    my ($self, $args) = @_;

    my $file = $args->{file};
    if ($file eq "list/edit-multiple.html.tmpl") {
        my $vars = $args->{vars};
        my $dbh  = Bugzilla->dbh;
        use Data::Dumper;
        #        my $user_id = $vars->{'cgi'}->{'.cookies'}->{Bugzilla_login}->{value}[0];
        my $user = Bugzilla->login(LOGIN_REQUIRED);
        my $sprints =
          $dbh->selectall_arrayref(  "select s.id, s.name, scrums_team.name from "
                                   . "(select * from scrums_sprints where "
                                   . "item_type <> 2 "
                                   . "order by start_date desc) as s, scrums_team where s.team_id = scrums_team.id "
                                   . "group by team_id");
        $vars->{sprints} = $sprints;
    }
}

# This must be the last line of your extension.
__PACKAGE__->NAME;
