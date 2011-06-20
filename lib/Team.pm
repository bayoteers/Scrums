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

use strict;

package Bugzilla::Extension::Scrums::Team;

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;

use base qw(Bugzilla::Object);

##### Constants
# TODO Move to Bugzilla/Constants.pm
# The longest team name allowed.
use constant MAX_TEAM_NAME_SIZE => 64;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE   => 'scrums_team';
use constant LIST_ORDER => 'name';

use constant DB_COLUMNS => qw(
  id
  name
  owner
  weekly_velocity_value
  weekly_velocity_start
  weekly_velocity_end
  scrum_master
  );

use constant REQUIRED_CREATE_FIELDS => qw(
  name
  owner
  );

use constant UPDATE_COLUMNS => qw(
  name
  owner
  scrum_master
  );

use constant VALIDATORS => { name => \&_check_name, };

###############################
####     Constructors     #####
###############################
# This is necessary method only because transaction handling is needed for multiple tables
sub remove_from_db {
    my $self = shift;

    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    my $team_id = $self->id;
    Bugzilla->dbh->do('delete from scrums_teammember where teamid = ?',    undef, $team_id);
    Bugzilla->dbh->do('delete from scrums_componentteam where teamid = ?', undef, $team_id);

    $self->SUPER::remove_from_db();

    $dbh->bz_commit_transaction();
}

###############################
####      Validators       ####
###############################

sub _check_name {
    my ($invocant, $name) = @_;

    $name = trim($name);
    $name || ThrowUserError('team_name_not_specified');

    if (length($name) > MAX_TEAM_NAME_SIZE) {
        ThrowUserError('team_name_too_long', { 'name' => $name });
    }

    my $team = new Bugzilla::Extension::Scrums::Team({ name => $name });
    if ($team && (!ref $invocant || $team->id != $invocant->id)) {
        ThrowUserError("team_already_exists", { name => $team->name });
    }

    return $name;
}

###############################
####       Methods         ####
###############################

sub set_name         { $_[0]->set('name',         $_[1]); }
sub set_owner        { $_[0]->set('owner',        $_[1]); }
sub set_scrum_master { $_[0]->set('scrum_master', $_[1]); }

sub set_component {
    my ($self, $component_id) = @_;

    my $team_id = $self->id;

    # Method can be used only when component had no previous team assigned.
    Bugzilla->dbh->do('INSERT INTO scrums_componentteam (component_id, teamid) VALUES (?, ?)', undef, $component_id, $team_id);
}

sub update_component {
    my ($self, $component_id) = @_;

    my $team_id = $self->id;

    # Method can be used only when component had previous team assigned.
    Bugzilla->dbh->do('UPDATE scrums_componentteam SET component_id = ? WHERE teamid = ?', undef, $component_id, $team_id);
}

sub remove_component {
    my ($invocant, $component_id) = @_;

    Bugzilla->dbh->do('DELETE FROM scrums_componentteam WHERE component_id = ?', undef, $component_id);
}

sub set_member {
    my ($self, $member_id) = @_;

    my $team_id = $self->id;
    my $team_member_ids =
      Bugzilla->dbh->selectcol_arrayref('SELECT userid FROM scrums_teammember WHERE teamid = ? AND userid = ?', undef, $self->id, $member_id);

    # User can not belong to same team several times
    if (scalar @{$team_member_ids} > 0) {
        ThrowUserError("user_already_member_of_team", { name => $self->name });
    }

    # Team can have many members. Member can belong to many teams.
    Bugzilla->dbh->do('INSERT INTO scrums_teammember (teamid, userid) VALUES (?, ?)', undef, $team_id, $member_id);
}

sub remove_member {
    my ($self, $member_id) = @_;

    my $team_id = $self->id;

    Bugzilla->dbh->do('DELETE FROM scrums_teammember WHERE userid = ? AND teamid = ?', undef, $member_id, $team_id);
}

sub team_memberships_of_user {
    my ($self, $user_id) = @_;

    my $user_team_ids = Bugzilla->dbh->selectall_arrayref('SELECT teamid FROM scrums_teammember WHERE userid = ?', undef, $user_id);

    return $user_team_ids;
}

sub team_of_component {
    my ($self, $component_id) = @_;

    my ($team_id) = Bugzilla->dbh->selectrow_array('SELECT teamid FROM scrums_componentteam WHERE component_id = ?', undef, $component_id);

    if (!$team_id || $team_id == 0) {
        return;
    }

    my $team = Bugzilla::Extension::Scrums::Team->new($team_id);

    return $team;
}

sub is_team_super_user {
    my ($self, $user) = @_;
    my $user_id = $user->id();

    my ($owner_id) = Bugzilla->dbh->selectrow_array('SELECT owner FROM scrums_team WHERE id = ? AND owner = ?', undef, $self->id, $user_id);
    if ($owner_id) {
        return 1;
    }
    my ($scrum_master_id) =
      Bugzilla->dbh->selectrow_array('SELECT scrum_master FROM scrums_team WHERE id = ? AND scrum_master = ?', undef, $self->id, $user_id);
    if ($scrum_master_id) {
        return 1;
    }
    return 0;
}

sub is_user_team_member {
    my ($self, $user) = @_;
    my $user_id = $user->id();

    if ($self->is_team_super_user($user)) {
        return 1;
    }

    my ($member_id) = Bugzilla->dbh->selectrow_array('SELECT userid FROM scrums_teammember WHERE teamid = ? AND userid = ?', undef, $self->id, $user_id);
    if ($member_id) {
        return 1;
    }

    return 0;
}

###############################
####      Accessors        ####
###############################

sub name                  { return $_[0]->{'name'}; }
sub owner                 { return $_[0]->{'owner'}; }
sub scrum_master          { return $_[0]->{'scrum_master'}; }
sub weekly_velocity_value { return $_[0]->{'weekly_velocity_value'}; }
sub weekly_velocity_start { return $_[0]->{'weekly_velocity_start'}; }
sub weekly_velocity_end   { return $_[0]->{'weekly_velocity_end'}; }

sub owner_user {
    my ($self) = @_;

    return Bugzilla::User->new($self->owner);
}

sub scrum_master_user {
    my ($self) = @_;

    return Bugzilla::User->new($self->scrum_master);
}

sub members {
    my $self = shift;

    return $self->{'members'} if exists $self->{'members'};
    return [] if $self->{'error'};

    my $dbh = Bugzilla->dbh;
    my $team_member_ids = $dbh->selectcol_arrayref('SELECT userid FROM scrums_teammember WHERE teamid = ?', undef, $self->id);
    $self->{'members'} = Bugzilla::User->new_from_list($team_member_ids);
    return $self->{'members'};
}

sub components {
    my $self = shift;

    return $self->{'components'} if exists $self->{'components'};
    return [] if $self->{'error'};

    my $dbh = Bugzilla->dbh;
    my $component_ids = $dbh->selectcol_arrayref('SELECT component_id FROM scrums_componentteam WHERE teamid = ?', undef, $self->id);
    $self->{'components'} = Bugzilla::Component->new_from_list($component_ids);
    return $self->{'components'};
}

sub all_teams {
    my ($self, $sort) = @_;

    my ($team_list) = [ Bugzilla::Extension::Scrums::Team->get_all ];

    if ($sort == 1) {
        @{$team_list} = sort { lc($a->name) cmp lc($b->name) } @{$team_list};
    }
    elsif ($sort == 2) {
        @{$team_list} = sort { lc($b->name) cmp lc($a->name) } @{$team_list};
    }
    elsif ($sort == 3) {
        @{$team_list} = sort { lc($a->owner_user->name) cmp lc($b->owner_user->name) } @{$team_list};
    }
    elsif ($sort == 4) {
        @{$team_list} = sort { lc($b->owner_user->name) cmp lc($a->owner_user->name) } @{$team_list};
    }
    elsif ($sort == 5) {
        @{$team_list} = sort { lc($a->owner_user->login) cmp lc($b->owner_user->login) } @{$team_list};
    }
    elsif ($sort == 6) {
        @{$team_list} = sort { lc($b->owner_user->login) cmp lc($a->owner_user->login) } @{$team_list};
    }
    else {
        @{$team_list} = sort { lc($a->id) cmp lc($b->id) } @{$team_list};
    }

    return $team_list;
}

#
# Condition for bug to be unscheduled is, that it is not in any active sprint and neither in team's product backlog (item_type =2)
# Bug does not have severity "change request", "feature" or "task".
#
sub unprioritised_bugs {
    my $self = shift;

    my $dbh = Bugzilla->dbh;

    my ($unscheduled_bugs) = $dbh->selectall_arrayref(
        'select
	b.bug_id,
        b.remaining_time,
	b.bug_status,
        p.realname,
        left(b.short_desc, 40),
        b.short_desc
    from 
	scrums_componentteam sct
    inner join
	bugs b on b.component_id = sct.component_id
    inner join 
        profiles p on p.userid = b.assigned_to
    inner join
	bug_status bs on b.bug_status = bs.value
    where 
        b.bug_severity not in("change request", "feature", "task") and
	sct.teamid = ? and
	bs.is_open = 1 and
        not exists (select null from scrums_sprint_bug_map sbm inner join scrums_sprints spr on sbm.sprint_id = spr.id where b.bug_id = sbm.bug_id and spr.is_active = 1 and spr.team_id = ?) 
    order by
	bug_id', undef, $self->id, $self->id
    );

    return $unscheduled_bugs;
}

#
# Condition for item to be unscheduled is, that it is not in any active sprint and neither in team's product backlog (srums_sprints.item_type =2)
# "Item" might be either task or bug. Task has severity "change request", "feature" or "task" and bug has some other reverity value.
#
sub unprioritised_items {
    my $self = shift;

    my $dbh = Bugzilla->dbh;

    my ($unscheduled_items) = $dbh->selectall_arrayref(
        'select
	b.bug_id,
        b.remaining_time,
	b.bug_status,
        p.realname,
        left(b.short_desc, 40),
        b.short_desc
    from 
	scrums_componentteam sct
    inner join
	bugs b on b.component_id = sct.component_id
    inner join 
        profiles p on p.userid = b.assigned_to
    inner join
	bug_status bs on b.bug_status = bs.value
    where 
	sct.teamid = ? and
	bs.is_open = 1 and
        not exists (select null from scrums_sprint_bug_map sbm inner join scrums_sprints spr on sbm.sprint_id = spr.id where b.bug_id = sbm.bug_id and spr.is_active = 1 and spr.team_id = ?) 
    order by
	bug_id', undef, $self->id, $self->id
    );

    return $unscheduled_items;
}

##
## Condition for task to be unscheduled is, that it is not in any active sprint and neither in team's product backlog (item_type =2)
## Task has severity "change request", "feature" or "task".
##
#sub unprioritised_tasks {
#    my $self = shift;
#
#    my $dbh = Bugzilla->dbh;
#
#    my ($unscheduled_tasks) = $dbh->selectall_arrayref(
#        'select
#	b.bug_id,
#	b.bug_status,
#        b.bug_severity,
#        left(b.short_desc, 40)
#    from
#	scrums_componentteam sct
#    inner join
#	bugs b on b.component_id = sct.component_id
#    inner join
#	bug_status bs on b.bug_status = bs.value
#    where
#        b.bug_severity in("change request", "feature", "task") and
#	sct.teamid = ? and
#	bs.is_open = 1 and
#        not exists (select null from scrums_sprint_bug_map sbm inner join scrums_sprints spr on sbm.sprint_id = spr.id where b.bug_id = sbm.bug_id and spr.is_active = 1 and spr.team_id = ?)
#    order by
#	bug_id', undef, $self->id, $self->id
#    );
#
#    return $unscheduled_tasks;
#}

sub mysort {
    lc($a->owner_user->name) cmp lc($b->owner_user->name);
}

1;

__END__

