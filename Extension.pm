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
# The Original Code is the Ultimate Scrum Bugzilla Extension.
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
use Bugzilla::Extension::Scrums::Sprintslib;

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

            if ($estimated_time == 0) {
                ThrowUserError("scrums_estimated_time_required");
            }
            elsif ($actual_time == 0) {
                ThrowUserError("scrums_actual_time_required");
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
    if ($bug->bug_id == $cgi->param('id')) {
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

        # Confirm we haven't got invalid status/resolution selections.
        _bug_check_bug_status($bug);
        _bug_check_resolution($bug);
    }
}

sub buglist_supptables {
    my ($self, $args) = @_;

    my $supptables = $args->{'supptables'};

    # Add this table to what can be referenced in MySQL when displaying search results
    push(@$supptables, 'LEFT JOIN scrums_bug_order ON scrums_bug_order.bug_id = bugs.bug_id');

    # Add this table to what can be referenced in MySQL when displaying search results
    push(@$supptables, 'LEFT JOIN dependencies ON dependencies.dependson = bugs.bug_id');

    # Add this table to what can be referenced in MySQL when displaying search results
    push(@$supptables, 'LEFT JOIN scrums_sprint_bug_map ON scrums_sprint_bug_map.bug_id = bugs.bug_id');

    # Add this table to what can be referenced in MySQL when displaying search results
    push(@$supptables, 'LEFT JOIN scrums_sprints ON scrums_sprints.id = scrums_sprint_bug_map.sprint_id ');
}

sub buglist_columns {
    my ($self, $args) = @_;

    my $columns = $args->{'columns'};

    # Describe how to access the extra columns described in colchange_columns()
    $columns->{'scrums_team_order'}    = { 'name' => 'scrums_bug_order.team',    'title' => 'Team Order' };
    $columns->{'scrums_release_order'} = { 'name' => 'scrums_bug_order.rlease',  'title' => 'Release Order' };
    $columns->{'scrums_program_order'} = { 'name' => 'scrums_bug_order.program', 'title' => 'Program Order' };

    $columns->{'scrums_blocked'} = { 'name' => 'dependencies.blocked', 'title' => 'Parent item' };

    $columns->{'sprint_name'} = { 'name' => 'scrums_sprints.name', 'title' => 'Sprint' };
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
}

sub buglist_supp_legal_fields {
    my ($self, $args) = @_;

    my $fields = $args->{'fields'};
    my $supp_fields = eval { Bugzilla::Field->match({ name => 'scrums_sprint_bug_map.sprint_id' }) } || [];
    if (@{$supp_fields}) {
        push(@{$fields}, @{$supp_fields}[0]);
    }
    else {
        my $sprint = Bugzilla::Field->create({ name => 'scrums_sprint_bug_map.sprint_id', description => 'Sprint id' });
        push(@{$fields}, $sprint);
    }
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
                                                item_type   => { TYPE => 'INT2', NOTNULL => 1, DEFAULT => '1' },
                                                start_date  => { TYPE => 'DATE' },
                                                end_date    => { TYPE => 'DATE' },
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

}

sub install_update_db {
    use constant WV_VALUE_DEFINITION => { TYPE => 'decimal(7,2)' };
    use constant WV_START_DEFINITION => { TYPE => 'DATE' };
    use constant WV_END_DEFINITION   => { TYPE => 'DATE' };

    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_value", WV_VALUE_DEFINITION, undef);
    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_start", WV_START_DEFINITION, undef);
    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_end",   WV_END_DEFINITION,   undef);

    Bugzilla->dbh->bz_add_column("scrums_team", "weekly_velocity_end", WV_END_DEFINITION, undef);

    use constant SPRINT_TYPE_DEFINITION => { TYPE => 'INT2', NOTNULL => 1, DEFAULT => '1' };
    Bugzilla->dbh->bz_add_column("scrums_sprints", "item_type", SPRINT_TYPE_DEFINITION, undef);

    use constant TEAM_SCRUM_MASTER => {
                                        TYPE       => 'INT3',
                                        REFERENCES => {
                                                        TABLE  => 'profiles',
                                                        COLUMN => 'userid',
                                                        DELETE => 'CASCADE'
                                                      }
                                      };
    Bugzilla->dbh->bz_add_column("scrums_team", "scrum_master", TEAM_SCRUM_MASTER, undef);

    use constant START_DATE_DEFINITION => { TYPE => 'DATE' };
    use constant END_DATE_DEFINITION   => { TYPE => 'DATE' };
    Bugzilla->dbh->bz_add_column("scrums_sprints", "start_date", START_DATE_DEFINITION, undef);
    Bugzilla->dbh->bz_add_column("scrums_sprints", "end_date",   END_DATE_DEFINITION,   undef);
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

    if ($page eq 'scrums/allteams.html') {
        show_all_teams($vars);
    }
    if ($page eq 'scrums/createteam.html') {
        show_create_team($vars);
    }
    if ($page eq 'scrums/addintoteam.html') {
        if (not Bugzilla->user->in_group('editteams')) {
            ThrowUserError('auth_failure', { group => "editteams", action => "edit", object => "team" });
        }
        add_into_team($vars);
    }
    if ($page eq 'scrums/searchperson.html') {
        search_person($vars);
    }
    if ($page eq 'scrums/newteam.html') {
        edit_team($vars);
    }
    if ($page eq 'scrums/teambugs.html') {
        show_team_and_sprints($vars);
    }
    if ($page eq 'scrums/teambugs2.html' || $page eq 'scrums/dailysprint.html') {
        show_team_and_sprints($vars);
    }
    if ($page eq 'scrums/backlogplanning.html') {
        show_backlog_and_items($vars);
    }
    if ($page eq 'scrums/archivedsprints.html') {
        show_archived_sprints($vars);
    }
    if ($page eq "scrums/ajax.html") {
        my $cgi    = Bugzilla->cgi;
        my $schema = $cgi->param('schema');
        if ($schema eq "release") {
            handle_release_bug_data($vars);
        }
        elsif ($schema eq "backlog") {
            update_team_bugs($vars, 1);
        }
        else {
            update_team_bugs($vars, 0);
        }
    }

    if ($page eq 'scrums/newsprint.html') {
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
    if ($page eq 'scrums/choose-classification.html') {
        my $cgi             = Bugzilla->cgi;
        my $team_id         = $cgi->param('teamid');
        my @classifications = Bugzilla::Classification->get_all();
        $vars->{'classifications'} = \@classifications;
        $vars->{'target'}          = "page.cgi?id=scrums/choose-product.html&teamid=" . $team_id;
    }
    if ($page eq 'scrums/choose-product.html') {
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
    if ($page eq 'scrums/choose-component.html') {
        my $cgi          = Bugzilla->cgi;
        my $team_id      = $cgi->param('teamid');
        my $product_name = $cgi->param('product');
        my $products     = Bugzilla::Product->match({ name => $product_name });
        if (scalar @{$products} > 0) {
            $vars->{'product'} = @$products[0];
        }
        $vars->{'target'} = "page.cgi?id=scrums/createteam.html&teamid=" . $team_id;
    }

    if ($page eq 'scrums/sprintburndown.html') {
        my $cgi       = Bugzilla->cgi;
        my $sprint_id = $cgi->param('sprintid');
        $vars->{'team_name'}   = $cgi->param('teamname');
        $vars->{'team_id'}     = $cgi->param('teamid');
        $vars->{'sprint_name'} = $cgi->param('sprintname');
        burndown_plot($vars, $sprint_id);
    }
}

sub _bug_check_bug_status {
    my ($bug) = @_;

    my @bug_status_black_list = ('INDEFINITION', 'ACCEPTED', 'WAITING');

    my @feature_status_black_list = ('ASSIGNED', 'WAITING FOR UPSTREAM');

    my $is_feature = ($bug->bug_severity() eq "task" || $bug->bug_severity() eq "feature");

    if ($is_feature) {
        foreach my $blacklisted (@feature_status_black_list) {
            if ($bug->status->{'value'} eq $blacklisted) {
                ThrowUserError("invalid_feature_status", { bug => $bug, invstatus => $blacklisted });
            }
        }
    }
    else {
        foreach my $blacklisted (@bug_status_black_list) {
            if ($bug->status->{'value'} eq $blacklisted) {
                ThrowUserError("invalid_bug_status", { bug => $bug, invstatus => $blacklisted });
            }
        }
    }
}

sub _bug_check_resolution {
    my ($bug) = @_;

    my @bug_resolution_black_list = ('READYFORINTEGRATION', 'REJECTED');

    my @feature_resolution_black_list = ('FIXED', 'INVALID', 'WONTFIX', 'WORKSFORME');

    my $is_feature = ($bug->bug_severity() eq "task" || $bug->bug_severity() eq "feature");

    if ($is_feature) {
        foreach my $blacklisted (@feature_resolution_black_list) {
            if ($bug->resolution eq $blacklisted) {
                ThrowUserError("invalid_feature_resolution", { bug => $bug, invresolution => $blacklisted });
            }
        }
    }
    else {
        foreach my $blacklisted (@bug_resolution_black_list) {
            if ($bug->resolution eq $blacklisted) {
                ThrowUserError("invalid_bug_resolution", { bug => $bug, invresolution => $blacklisted });
            }
        }
    }
}

# This must be the last line of your extension.
__PACKAGE__->NAME;
