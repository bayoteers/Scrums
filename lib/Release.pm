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

package Bugzilla::Extension::Scrums::Release;

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;

use base qw(Bugzilla::Object);

##### Constants
# TODO Move to Bugzilla/Constants.pm
# The longest release name allowed.
use constant MAX_RELEASE_SIZE => 64;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE   => 'scrums_releases';
use constant LIST_ORDER => 'name';

use constant DB_COLUMNS => qw(
  id
  name
  target_milestone_begin
  target_milestone_end
  capacity_algorithm
  original_capacity
  remaining_capacity
  );

use constant REQUIRED_CREATE_FIELDS => qw(
  name
  );

use constant UPDATE_COLUMNS => qw(
  name
  target_milestone_begin
  target_milestone_end
  capacity_algorithm
  original_capacity
  remaining_capacity
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

    my $release_id = $self->id;
    Bugzilla->dbh->do('delete from scrums_flagtype_release_map where release_id = ?', undef, $release_id);

    $self->SUPER::remove_from_db();

    $dbh->bz_commit_transaction();
}

###############################
####      Validators       ####
###############################

sub _check_name {
    my ($invocant, $name) = @_;

    $name = trim($name);
    $name || ThrowUserError('release_not_specified');

    if (length($name) > MAX_RELEASE_SIZE) {
        ThrowUserError('release_name_too_long', { 'name' => $name });
    }

    my $release = new Bugzilla::Extension::Scrums::Release({ name => $name });
    if ($release && (!ref $invocant || $release->id != $invocant->id)) {
        ThrowUserError("release_already_exists", { name => $release->name });
    }
    return $name;
}

###############################
####       Methods         ####
###############################

sub set_name                   { $_[0]->set('name',                   $_[1]); }
sub set_target_milestone_begin { $_[0]->set('target_milestone_begin', $_[1]); }
sub set_target_milestone_end   { $_[0]->set('target_milestone_end',   $_[1]); }
sub set_capacity_algorithm     { $_[0]->set('capacity_algorithm',     $_[1]); }
sub set_original_capacity      { $_[0]->set('capacity_algorithm',     $_[1]); }
sub set_remaining_capacity     { $_[0]->set('capacity_algorithm',     $_[1]); }

sub set_flag_type {
    my ($self, $type_id) = @_;

    my $release_id = $self->id;
    Bugzilla->dbh->do('INSERT INTO scrums_flagtype_release_map (flagtype_id, release_id) VALUES (?, ?)', undef, $type_id, $release_id);
}

sub remove_flag_type {
    my ($self, $type_id) = @_;

    my $release_id = $self->id;
    Bugzilla->dbh->do('DELETE FROM scrums_flagtype_release_map WHERE flagtype_id = ? AND release_id = ?', undef, $type_id, $release_id);
}

###############################
####      Accessors        ####
###############################

sub name                   { return $_[0]->{'name'}; }
sub target_milestone_begin { return $_[0]->{'target_milestone_begin'}; }
sub target_milestone_end   { return $_[0]->{'target_milestone_end'}; }
sub capacity_algorithm     { return $_[0]->{'capacity_algorithm'}; }
sub original_capacity      { return $_[0]->{'original_capacity'}; }
sub remaining_capacity     { return $_[0]->{'remaining_capacity'}; }

sub flag_types {
    my $self = shift;

    return $self->{'flag_types'} if exists $self->{'flag_types'};
    return [] if $self->{'error'};

    my $dbh = Bugzilla->dbh;
    my $flag_type_ids = $dbh->selectcol_arrayref('SELECT flagtype_id FROM scrums_flagtype_release_map WHERE release_id = ?', undef, $self->id);
    $self->{'flag_types'} = Bugzilla::FlagType->new_from_list($flag_type_ids);
    return $self->{'flag_types'};
}

sub scheduled_bugs {
    my $self = shift;

    my $dbh = Bugzilla->dbh;
    my ($scheduled_bugs) = $dbh->selectall_arrayref(
        'select
	b.bug_id,
        b.bug_status,
        b.bug_severity,
        left(b.short_desc, 40),
        t.name,
        s_a.name,
        t.id,
        s_a.id,
	bo.rlease
    from
	scrums_flagtype_release_map rfm
	inner join flags f on rfm.flagtype_id = f.type_id
	inner join bugs b on f.bug_id = b.bug_id
	inner join scrums_bug_order bo on f.bug_id = bo.bug_id
        left join scrums_componentteam ct on b.component_id = ct.component_id
        left join scrums_team t on ct.teamid = t.id
        left join scrums_sprint_bug_map sbm_a on b.bug_id = sbm_a.bug_id
        left join scrums_sprints s_a on s_a.id = sbm_a.sprint_id and s_a.item_type = 1
    where
	f.status = "+" and
        bo.rlease > 0 and
	rfm.release_id = ? and
	not exists (select null from scrums_sprint_bug_map sbm_b
        inner join scrums_sprints s_b on s_b.id = sbm_b.sprint_id and s_b.item_type = 1 
	where b.bug_id = sbm_b.bug_id and
	s_b.start_date > s_a.start_date)
    order by
	rlease', undef, $self->id
    );
    return $scheduled_bugs;
}

sub unprioritised_bugs {
    my $self = shift;

    my $dbh = Bugzilla->dbh;
    my ($unprioritised_bugs) = $dbh->selectall_arrayref(
        'select
	b.bug_id,
        b.bug_status,
        b.bug_severity,
        left(b.short_desc, 40),
        t.name,
        s_a.name,
        t.id,
        s_a.id
    from
	scrums_flagtype_release_map rfm
	inner join flags f on rfm.flagtype_id = f.type_id
	inner join bugs b on f.bug_id = b.bug_id
        inner join bug_status bs on b.bug_status = bs.value
        left join scrums_componentteam ct on b.component_id = ct.component_id
        left join scrums_team t on ct.teamid = t.id
        left join scrums_sprint_bug_map sbm_a on b.bug_id = sbm_a.bug_id
        left join scrums_sprints s_a on s_a.id = sbm_a.sprint_id and s_a.item_type = 1
    where
	not exists (select null from scrums_bug_order bo where f.bug_id = bo.bug_id and bo.rlease > 0) and
	not exists (select null from scrums_sprint_bug_map sbm_b
        inner join scrums_sprints s_b on s_b.id = sbm_b.sprint_id and s_b.item_type = 1 
	where b.bug_id = sbm_b.bug_id and
	s_b.start_date > s_a.start_date) and
	f.status = "+" and
	bs.is_open = 1 and
	rfm.release_id = ?', undef, $self->id
    );
    return $unprioritised_bugs;
}

1;

__END__

=head1 NAME

Bugzilla::Extension::Scrums::Release - Scrums release class.

=head1 SYNOPSIS

    use Bugzilla::Extension::Scrums::Release;
    my $release = Bugzilla::Extension::Scrums::Release->new($release_id);
    my $release = Bugzilla::Extension::Scrums::Release->new({ name => $name });

    my $name               = $release->name();
    my $milestone_begin    = $release->target_milestone_begin();
    my $milestone_end      = $release->target_milestone_end();
    my $flagtypes          = $release->flag_types();
    my $scheduled_bugs     = $release->scheduled_bugs();
    my $unprioritised_bugs = $release->unprioritised_bugs();

    my $release = Bugzilla::Extension::Scrums::Release->create({ name             => $name });

    $release->set_name($name); 
    $release->set_target_milestone_begin($milestone_begin);
    $release->set_target_milestone_end($milestone_end);
    $release->set_flag_type($flag_type_id);
    $release->remove_flag_type($flag_type_id);

    $release->update();

    $release->remove_from_db;

=head1 DESCRIPTION

Release.pm represents a release, that Scrums extension is used as an aid for planning.

=head1 METHODS

=over

=item C<new($release_id)>

 Description: The constructor is used to load an existing release
              by passing a release ID .

 Params:      $release_id - Release ID (integer) from the database that we want to
                       read in.

 Returns:     A Bugzilla::Extension::Scrums::Release object.

=item C<name()>

 Description: Returns name of release.

 Params:      none.

 Returns:     String.

=item C<target_milestone_begin()>

 Description: Returns starting limit of targe milestone.

 Params:      none.

 Returns:     Starting week (string in format 'yyyy-ww').

=item C<target_milestone_end()>

 Description: Returns ending limit of targe milestone.

 Params:      none.

 Returns:     Ending week (string in format 'yyyy-ww').

=item C<flag_types()>

 Description: Returns all flag types, that are part of the release.

 Params:      none.

 Returns:     Reference to an array of Bugzilla::FlagType objects.

=item C<scheduled_bugs()>

 Description: Returns all items, that are part of release and that are prioritised in release.

 Params:      none.

 Returns:     Reference to a table of data, that represents list of bugs.

=item C<unprioritised_bugs()>

 Description: Returns all items, that are part of release and that are not prioritised in release.

 Params:      none.

 Returns:     Reference to a table of data, that represents list of bugs.

=item C<_check_name($name)>

 Description: Checks name of release for its length and content.

 Params:      $name

 Returns:     Nothing. Throws exception if given name is not valid

=item C<set_name($name)>

 Description: Sets name of release.

 Params:      $name    - Name of release

 Returns:     Nothing.

=item C<set_target_milestone_begin($milestone_begin)>

 Description: Sets starting limit of targe milestone.

 Params:      none.

 Returns:     String.

=item C<set_target_milestone_end($milestone_end)>

 Description: Sets ending limit of targe milestone.

 Params:      none.

 Returns:     String.

=item C<set_flag_type($flag_type_id)>

 Description: Sets flag type to release.

 Params:      Id (integer) of flag type.

 Returns:     Nothing.

=item C<remove_flag_type($flag_type_id)>

 Description: Removes flag type from release.

 Params:      Id (integer) of flag type.

 Returns:     Nothing.

=back

=head1 CLASS METHODS

=over

=item C<create(\%params)>

 Description: Creates a new release.

 Params:      The hashref must have the following keys:
              team_id
              name                   - Name of the release (string). 
              The following keys are optional:
              target_milestone_begin - Starting limit of targe milestone
              target_milestone_end   - Ending limit of targe milestone

 Returns:     A Bugzilla::Extension::Scrums::Release object.

=back

=cut


