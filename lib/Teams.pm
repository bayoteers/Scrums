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
# The Original Code is the PMO Bugzilla Extension.
#
# The Initial Developer of the Original Code is "Nokia corporation"
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Visa Korhonen <visa.korhonen@symbio.com>

package Bugzilla::Extension::Scrums::Teams;

use Bugzilla::Extension::Scrums::Team;
use Bugzilla::Extension::Scrums::Sprint;

use Bugzilla::Util qw(trick_taint);

use strict;
use base qw(Exporter);
our @EXPORT = qw(
  show_all_teams
  show_create_team
  user_teams
  add_into_team
  component_team
  search_person
  edit_team
  show_team_and_sprints
  edit_sprint
  create_sprint
  );

# This file can be loaded by your extension via
# "use Bugzilla::Extension::PMO::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub show_all_teams($) {
    my ($vars) = @_;

    my $cgi         = Bugzilla->cgi;
    my $delete_team = $cgi->param('deleteteam');
    if ($delete_team ne "") {
        if (not Bugzilla->user->in_group('admin')) {
            ThrowUserError('auth_failure', { group => "admin", action => "delete", object => "team" });
        }
        _delete_team($delete_team);
    }

    my $sort = $cgi->param('sort');
    my $team_list;
    $team_list = Bugzilla::Extension::Scrums::Team->all_teams($sort);

    $vars->{'sort'} = $sort;

    $vars->{'teamlist'} = $team_list;
}

sub _delete_team {
    my ($team_id) = @_;
    if ($team_id =~ /^([0-9]+)$/) {
        $team_id = $1;    # $data now untainted
        my $team = Bugzilla::Extension::Scrums::Team->new($team_id);
        $team->remove_from_db();
    }
}

sub show_create_team {
    my ($vars) = @_;

    my $error   = "";
    my $cgi     = Bugzilla->cgi;
    my $team_id = $cgi->param('teamid');
    if ($team_id ne "") {
        if ($team_id =~ /^([0-9]+)$/) {
            $team_id = $1;    # $data now untainted
            my $team = Bugzilla::Extension::Scrums::Team->new($team_id);
            if ($cgi->param('editteam') ne "") {

                my $team_name  = $cgi->param('name');
                my $team_owner = $cgi->param('userid');
                if ($team_owner =~ /^([0-9]+)$/) {
                    $team_owner = $1;                                        # $data now untainted
                    $error = _update_team($team, $team_name, $team_owner);
                }
                else {
                    $error .= "Illegal team owner";
                }
            }
            _show_existing_team($vars, $team);
        }
        else {
            $error .= "Illegal team id. ";
        }
        $vars->{'error'} = $error;
    }
    else {
        _new_team($vars);
    }
}

sub _show_existing_team {
    my ($vars, $team) = @_;

    my $cgi = Bugzilla->cgi;

    my $user_id = $cgi->param('userid');
    if ($user_id ne "") {
        if ($user_id =~ /^([0-9]+)$/) {
            $user_id = $1;    # $data now untainted
            my $add_into_team = $cgi->param('addintoteam');
            if ($add_into_team ne "") {
                $team->set_member($user_id);
            }
            else {
                $team->remove_member($user_id);
            }
        }
    }
    $vars->{'team'} = $team;
}

sub _new_team {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;

    my $name     = $cgi->param('name');
    my $owner_id = $cgi->param('userid');

    my $error = "";
    if ($name =~ /^([-\ \w]+)$/) {
        $name = $1;    # $data now untainted
    }
    else {
        $error = "Illegal name. ";
        $name  = "";
    }

    if ($owner_id =~ /^([-\ \w]+)$/) {
        $owner_id = $1;    # $data now untainted
    }
    else {
        $error .= "Illegal owner.";
        $owner_id = "";
    }

    if ($name and $owner_id) {
        my $team = Bugzilla::Extension::Scrums::Team->create({ name => $name, owner => $owner_id });
        _show_existing_team($vars, $team);
    }
    else {
        $vars->{'error'} = $error;
    }
    $vars->{'teamisnew'} = "true";
}

sub user_teams {
    my ($vars) = @_;

    my $cgi     = Bugzilla->cgi;
    my $user_id = $cgi->param('userid');
    if ($user_id ne "") {
        if ($user_id =~ /^([0-9]+)$/) {
            $user_id = $1;    # $data now untainted

            my $add_team = $cgi->param('addteam');
            my $rem_team = $cgi->param('remteam');
            if ($rem_team ne "") {
                if ($rem_team =~ /^([0-9]+)$/) {
                    $rem_team = $1;    # $data now untainted
                    my $team = Bugzilla::Extension::Scrums::Team->new($rem_team);
                    $team->remove_member($user_id);
                }
            }
            # else-condition is needed because addteam and remteam can be present at the same time
            # Addteam is then unintentional and is caused by select-element having unintentional value
            elsif ($add_team ne "") {
                if ($add_team =~ /^([0-9]+)$/) {
                    $add_team = $1;    # $data now untainted
                    my $team = Bugzilla::Extension::Scrums::Team->new($add_team);
                    $team->set_member($user_id);
                }
            }

            my $user_team_ids = Bugzilla::Extension::Scrums::Team->team_memberships_of_user($user_id);
            my $user_teams    = Bugzilla::Extension::Scrums::Team->new_from_list(@{$user_team_ids});
            $vars->{'userteamlist'} = $user_teams;

            $vars->{'allteams'}  = [ Bugzilla::Extension::Scrums::Team->get_all() ];
            $vars->{'userid'}    = $user_id;
            $vars->{'username'}  = $cgi->param('username');
            $vars->{'userlogin'} = $cgi->param('userlogin');
        }
        else {
            $vars->{'error'} = "Illegal user id. ";
        }
    }
}

sub add_into_team {
    my ($vars) = @_;

    my $cgi     = Bugzilla->cgi;
    my $user_id = $cgi->param('userid');
    my $team_id = $cgi->param('teamid');

    if ($team_id ne "") {
        if ($team_id =~ /^([0-9]+)$/) {
            $team_id = $1;    # $data now untainted
        }
        else {
            $vars->{'error'} .= "Illegal team id: " . $team_id;
        }
    }

    if ($user_id ne "") {
        if ($user_id =~ /^([0-9]+)$/) {
            $user_id = $1;    # $data now untainted

            $vars->{'userid'}       = $user_id;
            $vars->{'userrealname'} = $cgi->param('userrealname');
            $vars->{'userlogin'}    = $cgi->param('userlogin');
            $vars->{'teamid'}       = $cgi->param('teamid');
            $vars->{'teamname'}     = $cgi->param('teamname');
        }
        else {
            $vars->{'error'} .= "Illegal user id. ";
        }
    }
}

sub component_team {
    my ($vars) = @_;

    my $cgi     = Bugzilla->cgi;
    my $comp_id = $cgi->param('compid');
    if ($comp_id ne "") {
        if ($comp_id =~ /^([0-9]+)$/) {
            $comp_id = $1;    # $data now untainted

            my $add_team = $cgi->param('addteam');
            my $rem_team = $cgi->param('remteam');
            if ($rem_team ne "") {
                Bugzilla::Extension::Scrums::Team->remove_component($comp_id);
            }
            # else-condition is needed because addteam and remteam can be present at the same time
            # Addteam is then unintentional and is caused by select-element having unintentional value
            elsif ($add_team ne "") {
                if ($add_team =~ /^([0-9]+)$/) {
                    $add_team = $1;    # $data now untainted
                    my $team_id = $cgi->param('teamid');
                    if ($team_id ne "") {
                        # There was previous team id. Existing row must be updated.
                        my $team = Bugzilla::Extension::Scrums::Team->new($add_team);
                        $team->update_component($comp_id);
                    }
                    else {
                        my $team = Bugzilla::Extension::Scrums::Team->new($add_team);
                        $team->set_component($comp_id);
                    }
                }
            }

            $vars->{'componentteam'} = Bugzilla::Extension::Scrums::Team->team_of_component($comp_id);

            my ($all_teams) = [ Bugzilla::Extension::Scrums::Team->get_all() ];
            @{$all_teams} = sort { lc($a->id) cmp lc($b->id) } @{$all_teams};
            $vars->{'allteams'}    = $all_teams;
            $vars->{'compid'}      = $cgi->param('compid');
            $vars->{'compname'}    = $cgi->param('compname');
            $vars->{'productname'} = $cgi->param('productname');
        }
    }
}

sub search_person {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;

    my $matchvalue    = $cgi->param('matchvalue') || '';
    my $matchstr      = $cgi->param('matchstr');
    my $matchtype     = $cgi->param('matchtype');
    my $grouprestrict = $cgi->param('grouprestrict') || '0';
    my $query         = 'SELECT DISTINCT userid, login_name, realname, disabledtext ' . 'FROM profiles WHERE';
    my @bindValues;
    my $nextCondition;

    # Handle selection by login name, real name, or userid.
    if (defined($matchtype)) {
        $query .= " $nextCondition ";
        my $expr = "";
        if ($matchvalue eq 'userid') {
            if ($matchstr) {
                my $stored_matchstr = $matchstr;
                detaint_natural($matchstr)
                  || ThrowUserError('illegal_user_id', { userid => $stored_matchstr });
            }
            $expr = "profiles.userid";
        }
        elsif ($matchvalue eq 'realname') {
            $expr = "profiles.realname";
        }
        else {
            $expr = "profiles.login_name";
        }

        if ($matchstr =~ /^(regexp|notregexp|exact)$/) {
            $matchstr ||= '.';
        }
        else {
            $matchstr = '' unless defined $matchstr;
        }
        # We can trick_taint because we use the value in a SELECT only,
        # using a placeholder.
        trick_taint($matchstr);

        if ($matchtype eq 'regexp') {
            $query .= $dbh->sql_regexp($expr, '?', 0, $dbh->quote($matchstr));
        }
        elsif ($matchtype eq 'notregexp') {
            $query .= $dbh->sql_not_regexp($expr, '?', 0, $dbh->quote($matchstr));
        }
        elsif ($matchtype eq 'exact') {
            $query .= $expr . ' = ?';
        }
        else {    # substr or unknown
            $query .= $dbh->sql_istrcmp($expr, '?', 'LIKE');
            $matchstr = "%$matchstr%";
        }
        $nextCondition = 'AND';
        push(@bindValues, $matchstr);

        $query .= ' ORDER BY profiles.login_name';

        $vars->{'query'} = $query;
        $vars->{'users'} = $dbh->selectall_arrayref($query, { 'Slice' => {} }, @bindValues);
    }
    $vars->{'formname'} = $cgi->param('formname');
    $vars->{'submit'}   = $cgi->param('submit');
}

sub edit_team {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;
    $vars->{'editteam'}  = $cgi->param('editteam');
    $vars->{'teamid'}    = $cgi->param('teamid');
    $vars->{'teamname'}  = $cgi->param('teamname');
    $vars->{'realname'}  = $cgi->param('realname');
    $vars->{'loginname'} = $cgi->param('loginname');
    $vars->{'ownerid'}   = $cgi->param('ownerid');
}

# Show team bugs is a whole, which consists of team, sprints of team and
# list of bugs (ids) that belong to sprints
sub _show_team_bugs {
    my ($vars) = @_;

    my $cgi     = Bugzilla->cgi;
    my $team_id = $cgi->param('teamid');
    my $team    = Bugzilla::Extension::Scrums::Team->new($team_id);
    $vars->{'team'}               = $team;
    $vars->{'unprioritised_bugs'} = $team->unprioritised_bugs();

    #    $vars->{'sprints'} = [Bugzilla::Extension::Scrums::Sprint->get_all()];
    my $sprints = Bugzilla::Extension::Scrums::Sprint->match({ team_id => $team_id });
    #    $vars->{'sprints'} = $sprints;

    my %sprint_bug_map;
    my @team_sprints_array;
    for my $sprint (@{$sprints}) {
        my $spr_bugs = $sprint->get_bugs();
        my %team_sprint;
        %team_sprint->{'sprint'} = $sprint;
        %team_sprint->{'bugs'}   = $spr_bugs;
        push @team_sprints_array, \%team_sprint;
    }
    $vars->{'team_sprints_array'} = \@team_sprints_array;
}

sub edit_sprint {
    my ($vars) = @_;

    # TODO
    #    if (not Bugzilla->user->in_group('release_managers')) {
    #        ThrowUserError('auth_failure', { group => "release_managers", action => "edit", object => "release" });
    #    }

    my $cgi = Bugzilla->cgi;
    $vars->{'editsprint'}      = $cgi->param('editsprint');
    $vars->{'teamid'}          = $cgi->param('teamid');
    $vars->{'sprintid'}        = $cgi->param('sprintid');
    $vars->{'sprintname'}      = $cgi->param('sprintname');
    $vars->{'nominalschedule'} = $cgi->param('nominalschedule');
    $vars->{'description'}     = $cgi->param('description');
}

sub show_team_and_sprints {
    my ($vars) = @_;

    my $error     = "";
    my $cgi       = Bugzilla->cgi;
    my $sprint_id = $cgi->param('sprintid');
    if ($cgi->param('newsprint') ne "") {
        _new_sprint($vars);
    }
    elsif ($cgi->param('editsprint') ne "") {
        if ($sprint_id ne "") {
            if ($sprint_id =~ /^([0-9]+)$/) {
                $sprint_id = $1;                              # $data now untainted
                $error = _update_sprint($vars, $sprint_id);
            }
            else {
                $error = "Invalid sprint id";
            }
        }
    }
    elsif ($cgi->param('deletesprint') ne "") {
        $sprint_id = $cgi->param('deletesprint');
        if ($sprint_id =~ /^([0-9]+)$/) {
            $sprint_id = $1;                                  # $data now untainted
            my $sprint = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
            $sprint->remove_from_db();
        }
    }
    _show_team_bugs($vars);
}

sub _new_sprint {
    my ($vars) = @_;

    my $cgi             = Bugzilla->cgi;
    my $error           = "";
    my $teamid          = $cgi->param('teamid');
    my $name            = $cgi->param('sprintname');
    my $nominalschedule = $cgi->param('nominalschedule');
    my $description     = $cgi->param('description');

    ($error, $teamid, $name, $nominalschedule, $description) = _sanitise_sprint_data($teamid, $name, $nominalschedule, $description);

    if ($teamid and $name and $nominalschedule) {
        my $sprint = Bugzilla::Extension::Scrums::Sprint->create(
                     { team_id => $teamid, status => "NEW", name => $name, nominal_schedule => $nominalschedule, description => $description, is_active => 1 });
    }
    else {
        ThrowUserError($error);
        $vars->{'error'} = $error;
    }
}

sub _update_sprint {
    my ($vars, $sprint_id) = @_;

    my $cgi             = Bugzilla->cgi;
    my $error           = "";
    my $teamid          = $cgi->param('teamid');
    my $name            = $cgi->param('sprintname');
    my $nominalschedule = $cgi->param('nominalschedule');
    my $description     = $cgi->param('description');

    ($error, $teamid, $name, $nominalschedule, $description) = _sanitise_sprint_data($teamid, $name, $nominalschedule, $description);

    if ($teamid and $name and $nominalschedule) {
        my $sprint = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
        $sprint->set_name($name);
        $sprint->set_nominal_schedule($nominalschedule);
        $sprint->set_description($description);
        $sprint->update();
    }
    else {
        ThrowUserError($error);
        $vars->{'error'} = $error;
    }
}

sub _sanitise_sprint_data {
    my ($teamid, $name, $nominalschedule, $description) = @_;
    my $error = "";

    if ($teamid =~ /^([0-9]+)$/) {
        $teamid = $1;    # $data now untainted
    }
    else {
        $error .= "Illegal team id. ";
        $teamid = "";
    }

    if ($name =~ /^(\S.*)/) {
        $name = $1;      # $data now untainted
    }
    else {
        $error .= "Illegal name. ";
        $name = "";
    }

    if ($nominalschedule =~ /^(\d{4}\.\d{1,2}\.\d{1,2})/) {
        $nominalschedule = $1;    # $data now untainted
    }
    else {
        $error .= "Illegal nominal schedule. ";
        $nominalschedule = "";
    }

    if ($description =~ /(.*)/) {
        $description = $1;        # $data now untainted
    }
    else {
        $error .= "Illegal description. ";
        $description = "";
    }

    return ($error, $teamid, $name, $nominalschedule, $description);
}

sub _get_team_sprints {
    my ($vars, $team_id) = @_;
    $vars->{'sprints'} = Bugzilla::Extension::Scrums::Sprint->match({ team_id => $team_id });
}

sub _update_team {
    my ($team, $name, $owner) = @_;

    my $error = "";
    if ($name =~ /^([-\ \w]+)$/) {
        $name = $1;    # $data now untainted
    }
    else {
        $error = "Illegal name. ";
        $name  = "";
    }

    if ($owner =~ /^([0-9]+)$/) {
        $owner = $1;    # $data now untainted
    }
    else {
        $error .= "Illegal owner.";
        $owner = "";
    }

    if ($error eq "") {
        $team->set_name($name);
        $team->set_owner($owner);
        $team->update();
    }
    return $error;
}

1;
