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

package Bugzilla::Extension::Scrums;

use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;

use Bugzilla::Extension::Scrums::Teams;
use Bugzilla::Extension::Scrums::Releases;

use Data::Dumper;

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

            if ($estimated_time == 0) {
                ThrowUserError("scrums_estimated_time_required");
            }
            elsif ($actual_time == 0) {
                ThrowUserError("scrums_actual_time_required");
            }
        }
    }
}

sub buglist_supptables {
    my ($self, $args) = @_;

    my $supptables = $args->{'supptables'};

    # Add this table to what can be referenced in MySQL when displaying search results
    push(@$supptables, 'LEFT JOIN scrums_bug_order ON scrums_bug_order.bug_id = bugs.bug_id');
}

sub buglist_columns {
    my ($self, $args) = @_;

    my $columns = $args->{'columns'};

    # Describe how to access the extra columns described in colchange_columns()
    $columns->{'scrums_team_order'}    = { 'name' => 'scrums_bug_order.team',    'title' => 'Team Order' };
    $columns->{'scrums_release_order'} = { 'name' => 'scrums_bug_order.rlease',  'title' => 'Release Order' };
    $columns->{'scrums_program_order'} = { 'name' => 'scrums_bug_order.program', 'title' => 'Program Order' };
}

sub colchange_columns {
    my ($self, $args) = @_;

    my $columns = $args->{'columns'};

    # Make these columns available for diplaying in the colchange.cgi dialog
    push(@$columns, "scrums_team_order");
    push(@$columns, "scrums_release_order");
    push(@$columns, "scrums_program_order");
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
                                                name             => { TYPE => 'varchar(255)', NOTNULL => 1 },
                                                nominal_schedule => { TYPE => 'DATE',         NOTNULL => 1 },
                                                status           => { TYPE => 'varchar(20)',  NOTNULL => 1 },
                                                is_active        => { TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'TRUE' },
                                                description => { TYPE => 'varchar(255)' },
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
                                          
}

sub install_update_db {
    use constant WV_VALUE_DEFINITION => { TYPE => 'decimal(7,2)' };
    use constant WV_START_DEFINITION => { TYPE => 'DATE' };
    use constant WV_END_DEFINITION   => { TYPE => 'DATE' };

    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_value", WV_VALUE_DEFINITION, undef);
    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_start", WV_START_DEFINITION, undef);
    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_end",   WV_END_DEFINITION,   undef);
}

sub page_before_template {
    my ($self, $args) = @_;

    my ($vars, $page) = @$args{qw(vars page_id)};

    # User is stored as variable for user authorization
    $vars->{'user'} = Bugzilla->user;

    #    if($page eq 'debug.html') {
    #        my ($team_ids) = Bugzilla->dbh->selectrow_array('SELECT teamid FROM scrums_componentteam WHERE component_id = ?', undef, 2473);
    #        $vars->{'nono'} = $team_ids;
    #    }

    # Teams

    if ($page eq 'allteams.html') {
        show_all_teams($vars);
    }
    if ($page eq 'createteam.html') {
        show_create_team($vars);
    }
    if ($page eq 'userteams.html') {
        user_teams($vars);
    }
    if ($page eq 'addintoteam.html') {
        if (not Bugzilla->user->in_group('editteams')) {
            ThrowUserError('auth_failure', { group => "editteams", action => "edit", object => "team" });
        }
        add_into_team($vars);
    }
    if ($page eq 'componentteam.html') {
        if (not Bugzilla->user->in_group('editcomponents')) {
            ThrowUserError('auth_failure', { group => "editcomponents", action => "edit", object => "components" });
        }
        component_team($vars);
    }
    if ($page eq 'searchperson.html') {
        search_person($vars);
    }
    if ($page eq 'newteam.html') {
        if (not Bugzilla->user->in_group('admin')) {
            ThrowUserError('auth_failure', { group => "admin", action => "add", object => "team" });
        }
        edit_team($vars);
    }
    if ($page eq 'scrums/teambugs.html') {
        show_team_and_sprints($vars);
    }
    if ($page eq 'scrums/newsprint.html') {
# TODO
#        if (not Bugzilla->user->in_group('admin')) {
#            ThrowUserError('auth_failure', { group => "admin", action => "add", object => "team" });
#        }
        edit_sprint($vars);
    }

    # Releases

    if ($page eq 'scrums/allreleases.html') {
        all_releases($vars);
    }
    if ($page eq 'scrums/createrelease.html') {
        create_release($vars);
    }
    if ($page eq 'scrums/newrelease.html') {
        edit_release($vars);
    }
    if ($page eq 'scrums/releasebugs.html') {
        show_release_bugs($vars);
    }
    if ($page eq 'scrums/release_ajax.html') {
        my $cgi    = Bugzilla->cgi;
        my $action = $cgi->param('action');
        if ($action eq "orderteambugs") {
            $vars->{'error'} = "orderteambugs"
        } else
        {
            return handle_release_bug_data($vars);
        }
    }
}

# This must be the last line of your extension.
__PACKAGE__->NAME;
